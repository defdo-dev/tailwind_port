defmodule Defdo.TailwindPort.Pool do
  @moduledoc """
  A bounded, supervised pool of Tailwind CLI processes.

  A native Tailwind v4 CLI costs 150–300 MB of RSS per process, so the pool's
  first job is to keep that number bounded and to never leak one.

  ## Guarantees

    * **Hard size cap.** At most `:max_pool_size` CLI processes exist at once,
      across all configurations. When the pool is full, the least recently used
      idle port is retired to make room; when every port is busy the request
      waits in a bounded queue (`:max_queue`) and is rejected with
      `{:error, :busy}` once that queue is full.
    * **The pool never compiles.** The GenServer only checks ports out and in.
      Staging content, starting the CLI and waiting for its output happen in the
      calling process, so one slow tenant does not serialise every other one
      and no content binary sits in the pool's mailbox.
    * **Every port is supervised.** CLI processes run under
      `TailwindPort.DynamicSupervisor` and are registered in
      `TailwindPort.PoolRegistry`. Stopping the pool stops them; a pool that was
      killed outright reaps its predecessor's ports when it starts again.
    * **Every failure retires its port.** A compile that errors, times out, or
      whose caller dies stops the CLI process and deletes the pool-managed
      temporary files. A port is never left `:busy` with nobody using it.
    * **One-shot CLIs do not linger.** A port started without `:watch` compiles
      once and exits, so it is retired as soon as its compile is checked in.
      Only watch-mode ports stay idle in the pool, and only for
      `:port_idle_timeout_ms`.
    * **Single flight.** Concurrent compiles of identical content with an
      identical configuration share one CLI run and one result.

  ## Options

    * `:max_pool_size` — maximum CLI processes alive at once (default `3`).
    * `:max_queue` — callers allowed to wait for a port before new ones get
      `{:error, :busy}` (default `8`; `0` rejects immediately).
    * `:checkout_timeout_ms` — how long a queued caller waits for a port before
      `{:error, :checkout_timeout}` (default `30_000`).
    * `:compile_timeout_ms` — how long a compile waits for its output (default
      `20_000`).
    * `:port_ready_timeout` — how long to wait for the CLI's first build signal
      before carrying on in degraded mode (default `1_000`).
    * `:port_idle_timeout_ms` — how long an idle watch-mode port is kept
      (default `600_000`). In memory-constrained containers use `30_000`–
      `60_000`. `0` stops every port as soon as its compile finishes (scale to
      zero).
    * `:cleanup_interval` — how often idle ports are swept (default `60_000`).
    * `:single_flight` — share one run between concurrent identical compiles
      (default `true`).

  ## Usage

      {:ok, _pid} = Defdo.TailwindPort.Pool.start_link(max_pool_size: 2)
      {:ok, result} = Defdo.TailwindPort.Pool.compile(opts, content)
      {:ok, results} = Defdo.TailwindPort.Pool.batch_compile(operations)
  """

  use GenServer
  require Logger

  alias Defdo.TailwindPort.{CliCompatibility, Standalone}

  @supervisor TailwindPort.DynamicSupervisor
  @registry TailwindPort.PoolRegistry
  @config_cache_ttl :timer.minutes(30)
  @poll_interval_ms 75

  defstruct ports: %{},
            waiting: :queue.new(),
            config_cache: %{},
            stats: nil,
            options: []

  @type port_info :: %{
          config_hash: binary(),
          pid: pid() | nil,
          port_ref: reference() | nil,
          status: :idle | :busy,
          watch?: boolean(),
          lease_ref: reference() | nil,
          owner: pid() | nil,
          owner_ref: reference() | nil,
          content_key: binary() | nil,
          followers: [GenServer.from()],
          managed_paths: [String.t()],
          build_count: non_neg_integer(),
          created_at: integer(),
          last_used: integer()
        }

  @type compile_operation :: %{
          id: term(),
          opts: keyword(),
          content: String.t(),
          priority: :low | :normal | :high
        }

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts,
      name: __MODULE__,
      # The pool only ever holds references to CSS results while handing them
      # to single-flight followers; collect them promptly.
      spawn_opt: [fullsweep_after: 20],
      hibernate_after: 15_000
    )
  end

  @spec compile(keyword(), String.t()) :: {:ok, map()} | {:error, term()}
  def compile(opts, content) do
    operation = %{id: make_ref(), opts: opts, content: content, priority: :normal}

    case run_operation(operation) do
      {:ok, result} -> {:ok, result}
      {:error, reason, _id} -> {:error, reason}
    end
  end

  @doc """
  Compiles each operation in turn, in the calling process.

  Returns `{:ok, results}` where each entry is `{:ok, result}` or
  `{:error, reason, operation_id}`.
  """
  @spec batch_compile([compile_operation()]) :: {:ok, [term()]} | {:error, term()}
  def batch_compile(operations) when is_list(operations) do
    results = Enum.map(operations, &run_operation/1)
    GenServer.cast(__MODULE__, :record_batch)
    {:ok, results}
  end

  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Pre-starts watch-mode ports for the given configurations, within the size
  cap. Configurations without `:watch` are skipped: a one-shot CLI exits after
  its first build, so starting it early only spends memory.
  """
  @spec warm_up([keyword()]) :: :ok
  def warm_up(common_configs) do
    GenServer.cast(__MODULE__, {:warm_up, common_configs})
  end

  ## Caller-side compile

  defp run_operation(operation) do
    id = Map.get(operation, :id)
    content = Map.fetch!(operation, :content)
    opts = normalize_operation_opts(Map.get(operation, :opts, []))
    config_hash = hash_config(opts)
    start_time = System.monotonic_time(:microsecond)

    :telemetry.execute(
      [:tailwind_port_pool, :compile, :start],
      %{system_time: System.system_time(:microsecond)},
      %{
        operation_id: id,
        config_hash: config_hash,
        priority: Map.get(operation, :priority, :normal),
        content_size: byte_size(content)
      }
    )

    request = %{config_hash: config_hash, opts: opts, content_key: :erlang.md5(content)}

    case GenServer.call(__MODULE__, {:checkout, request}, :infinity) do
      {:ok, lease} ->
        outcome = execute_lease(lease, opts, content, id)
        duration = System.monotonic_time(:microsecond) - start_time

        counters =
          GenServer.call(__MODULE__, {:checkin, lease.ref, outcome, duration}, :infinity)

        emit_outcome(outcome, id, config_hash, duration, counters, lease.reused?)
        tag(outcome, id)

      {:shared, outcome} ->
        outcome |> retag(id) |> tag(id)

      {:error, reason} ->
        duration = System.monotonic_time(:microsecond) - start_time
        emit_outcome({:error, reason}, id, config_hash, duration, %{}, false)
        {:error, reason, id}
    end
  end

  defp tag({:ok, result}, _id), do: {:ok, result}
  defp tag({:error, reason}, id), do: {:error, reason, id}

  defp retag({:ok, result}, id), do: {:ok, %{result | operation_id: id}}
  defp retag(other, _id), do: other

  defp emit_outcome({:ok, _}, id, config_hash, duration, counters, reused?) do
    :telemetry.execute(
      [:tailwind_port_pool, :compile, :stop],
      %{duration: duration, cache_hits: Map.get(counters, :cache_hits, 0)},
      %{operation_id: id, config_hash: config_hash, port_reused: reused?}
    )
  end

  defp emit_outcome({:error, reason}, id, config_hash, duration, counters, _reused?) do
    :telemetry.execute(
      [:tailwind_port_pool, :compile, :error],
      %{duration: duration, error_count: Map.get(counters, :failed_compilations, 0)},
      %{operation_id: id, config_hash: config_hash, error: reason}
    )
  end

  # Runs in the caller. Whatever happens in here, the caller checks the lease
  # back in afterwards, and the pool retires the port on any error.
  defp execute_lease(lease, opts, content, id) do
    with {:ok, paths} <- stage(opts, content),
         {:ok, pid} <- acquire_port(lease, opts),
         {:ok, readiness} <- await_ready(pid, lease.port_ready_timeout),
         {:ok, css} <- await_output(paths.output_path, pid, lease.compile_timeout_ms) do
      finalize(css, pid, paths, id, readiness)
    end
  rescue
    error -> {:error, {:compile_crashed, Exception.message(error)}}
  catch
    :exit, reason -> {:error, {:compile_exit, reason}}
  end

  defp acquire_port(%{pid: pid}, _opts) when is_pid(pid) do
    if Process.alive?(pid), do: {:ok, pid}, else: {:error, :port_down}
  end

  defp acquire_port(lease, opts) do
    GenServer.call(__MODULE__, {:start_port, lease.ref, build_start_args(opts)}, 30_000)
  end

  # The content has to be on disk before the CLI starts, or the startup run
  # compiles the previous operation's content. The previous artifact is removed
  # FIRST, so its reappearance is the proof this run produced it — and so a
  # watcher reacting to the content write cannot have its fresh output deleted.
  defp stage(opts, content) do
    paths = build_port_paths(opts)

    with {:ok, content_path} <- select_primary_content_path(paths.content_paths),
         :ok <- ensure_directory(content_path),
         :ok <- ensure_directory(paths.output_path),
         :ok <- ensure_directory(paths.input_path),
         :ok <- ensure_input_placeholder(paths.input_path),
         :ok <- remove_file(paths.output_path),
         :ok <- File.write(content_path, content) do
      {:ok, Map.put(paths, :primary_content_path, content_path)}
    end
  end

  defp await_ready(pid, timeout) do
    cond do
      not Process.alive?(pid) ->
        {:error, :port_down}

      safe_ready?(pid) ->
        {:ok, :ready}

      true ->
        case safe_wait_until_ready(pid, timeout) do
          :ok ->
            {:ok, :ready}

          {:error, :timeout} ->
            Logger.debug("Port #{inspect(pid)} did not signal readiness within #{timeout}ms")
            {:ok, :degraded}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp safe_ready?(pid) do
    Standalone.ready?(pid)
  catch
    :exit, _ -> false
  end

  defp safe_wait_until_ready(pid, timeout) do
    Standalone.wait_until_ready(pid, timeout)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, {:noproc, _} -> {:error, :port_down}
    :exit, reason -> {:error, reason}
  end

  # Waits for the artifact this operation produced, without reading it until it
  # has settled: the file counts as finished once its size and mtime are the
  # same on two consecutive polls (Tailwind truncates before writing, so a read
  # can otherwise land mid-write). It is then read exactly once.
  #
  # Timing out is an error, never the previous artifact reported as success.
  defp await_output(path, pid, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_output(path, pid, deadline, nil)
  end

  defp poll_output(path, pid, deadline, previous) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :compile_timeout}
    else
      path |> File.stat(time: :posix) |> next_poll(path, pid, deadline, previous)
    end
  end

  defp next_poll({:ok, %File.Stat{size: size, mtime: mtime}}, path, _pid, _deadline, previous)
       when {size, mtime} == previous,
       do: File.read(path)

  defp next_poll({:ok, %File.Stat{size: size, mtime: mtime}}, path, pid, deadline, _previous) do
    Process.sleep(@poll_interval_ms)
    poll_output(path, pid, deadline, {size, mtime})
  end

  defp next_poll({:error, :enoent}, path, pid, deadline, _previous) do
    if Process.alive?(pid) do
      Process.sleep(@poll_interval_ms)
      poll_output(path, pid, deadline, nil)
    else
      {:error, :port_down}
    end
  end

  defp next_poll({:error, reason}, _path, _pid, _deadline, _previous), do: {:error, reason}

  # No artifact is a failure, never a success carrying `""`.
  defp finalize(css, _pid, _paths, _id, _readiness) when css in [nil, ""],
    do: {:error, :no_compiled_output}

  defp finalize(css, pid, paths, id, readiness) do
    {:ok,
     %{
       compiled_css: css,
       output_path: paths.output_path,
       port: get_port_from_pid(pid),
       operation_id: id,
       readiness: readiness
     }}
  end

  defp get_port_from_pid(pid) do
    case Standalone.state(pid) do
      %{port: port} -> port
      _ -> nil
    end
  catch
    :exit, _ -> nil
  end

  ## GenServer

  @impl true
  def init(opts) do
    # Trap exits so terminate/2 runs on shutdown and stops every CLI we own.
    Process.flag(:trap_exit, true)
    options = Keyword.merge(default_options(), opts)

    reap_orphans()
    schedule_cleanup(options)

    {:ok, %__MODULE__{stats: init_stats(), options: options}}
  end

  @impl true
  def handle_call({:checkout, request}, from, state) do
    case try_grant(request, from, state) do
      {:granted, lease, state} ->
        {:reply, {:ok, lease}, state}

      {:joined, state} ->
        {:noreply, update_in(state.stats.single_flight_hits, &(&1 + 1))}

      :wait ->
        enqueue_or_reject(request, from, state)
    end
  end

  def handle_call({:start_port, lease_ref, start_args}, {owner, _}, state) do
    case find_by_lease(state, lease_ref) do
      %{owner: ^owner} = entry ->
        start_leased_port(entry, start_args, state)

      _ ->
        {:reply, {:error, :lease_not_found}, state}
    end
  end

  def handle_call({:checkin, lease_ref, outcome, duration}, _from, state) do
    state =
      case find_by_lease(state, lease_ref) do
        nil -> state
        entry -> checkin(entry, outcome, state)
      end

    stats =
      state.stats
      |> record_outcome(outcome)
      |> update_stats({:compilation_time, duration})

    state = dispatch(%{state | stats: stats})

    {:reply, Map.take(state.stats, [:cache_hits, :failed_compilations]), state}
  end

  def handle_call(:get_stats, _from, state) do
    {:reply, build_stats(state), state}
  end

  @impl true
  def handle_cast(:record_batch, state) do
    {:noreply, update_in(state.stats.batch_compilations, &(&1 + 1))}
  end

  def handle_cast({:warm_up, configs}, state) do
    {:noreply, Enum.reduce(configs, state, &warm_one/2)}
  end

  @impl true
  def handle_info(:cleanup_idle_ports, state) do
    state = cleanup_idle_ports(state)
    schedule_cleanup(state.options)
    {:noreply, state}
  end

  def handle_info({:checkout_timeout, wait_id}, state) do
    {expired, kept} =
      state.waiting
      |> :queue.to_list()
      |> Enum.split_with(fn waiter -> waiter.wait_id == wait_id end)

    Enum.each(expired, &GenServer.reply(&1.from, {:error, :checkout_timeout}))
    {:noreply, %{state | waiting: :queue.from_list(kept)}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    {:noreply, handle_down(ref, reason, state)}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    # Ports are linked to the supervisor, not to the pool; a parent EXIT is
    # handled by gen_server itself. Anything else is not ours to act on.
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("Unhandled message in Pool TailwindPort: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(:queue.to_list(state.waiting), &GenServer.reply(&1.from, {:error, :shutdown}))

    _state =
      Enum.reduce(Map.values(state.ports), state, fn entry, acc ->
        reply_followers(entry, {:error, :shutdown})
        retire(entry, acc, :shutdown)
      end)

    :ok
  end

  ## Checkout / checkin

  defp try_grant(request, from, state) do
    case Map.get(state.ports, request.config_hash) do
      %{status: :busy, content_key: key} = entry
      when key == request.content_key ->
        if state.options[:single_flight] do
          {:joined, put_entry(state, %{entry | followers: [from | entry.followers]})}
        else
          :wait
        end

      %{status: :busy} ->
        :wait

      %{status: :idle} = entry ->
        state = update_in(state.stats, &update_stats(&1, :port_reused))

        :telemetry.execute(
          [:tailwind_port_pool, :pool, :port_reused],
          %{
            port_age_ms: System.monotonic_time(:millisecond) - entry.last_used,
            build_count: entry.build_count
          },
          %{config_hash: entry.config_hash, port: nil}
        )

        lease(entry, request, from, state, true)

      nil ->
        grant_new_slot(request, from, state)
    end
  end

  defp grant_new_slot(request, from, state) do
    cond do
      map_size(state.ports) < state.options[:max_pool_size] ->
        lease(new_entry(request), request, from, cache_config(state, request), false)

      victim = lru_idle(state) ->
        state = retire(victim, state, :evicted)
        lease(new_entry(request), request, from, cache_config(state, request), false)

      true ->
        :wait
    end
  end

  defp lease(entry, request, {owner, _}, state, reused?) do
    ref = make_ref()

    entry = %{
      entry
      | status: :busy,
        lease_ref: ref,
        owner: owner,
        owner_ref: Process.monitor(owner),
        content_key: request.content_key,
        followers: [],
        last_used: System.monotonic_time(:millisecond)
    }

    lease = %{
      ref: ref,
      config_hash: entry.config_hash,
      pid: entry.pid,
      reused?: reused?,
      compile_timeout_ms: state.options[:compile_timeout_ms],
      port_ready_timeout: state.options[:port_ready_timeout]
    }

    {:granted, lease, put_entry(state, entry)}
  end

  defp new_entry(request) do
    now = System.monotonic_time(:millisecond)

    %{
      config_hash: request.config_hash,
      pid: nil,
      port_ref: nil,
      status: :busy,
      watch?: watch_mode?(request.opts),
      lease_ref: nil,
      owner: nil,
      owner_ref: nil,
      content_key: nil,
      followers: [],
      managed_paths: managed_paths(request.opts),
      build_count: 0,
      created_at: now,
      last_used: now
    }
  end

  defp enqueue_or_reject(request, from, state) do
    if :queue.len(state.waiting) < state.options[:max_queue] do
      wait_id = make_ref()

      timer =
        Process.send_after(
          self(),
          {:checkout_timeout, wait_id},
          state.options[:checkout_timeout_ms]
        )

      waiter = %{from: from, request: request, wait_id: wait_id, timer: timer}
      {:noreply, %{state | waiting: :queue.in(waiter, state.waiting)}}
    else
      :telemetry.execute(
        [:tailwind_port_pool, :pool, :exhausted],
        %{pool_size: map_size(state.ports), max_size: state.options[:max_pool_size]},
        %{config_hash: request.config_hash}
      )

      stats = state.stats |> update_stats(:pool_exhausted) |> update_stats(:compile_error)
      {:reply, {:error, :busy}, %{state | stats: stats}}
    end
  end

  # Hands freed capacity to waiting callers, in arrival order.
  defp dispatch(state) do
    {kept, state} =
      state.waiting
      |> :queue.to_list()
      |> Enum.reduce({[], state}, &dispatch_waiter/2)

    %{state | waiting: :queue.from_list(Enum.reverse(kept))}
  end

  defp dispatch_waiter(waiter, {kept, state}) do
    {caller, _} = waiter.from

    result =
      if Process.alive?(caller),
        do: try_grant(waiter.request, waiter.from, state),
        else: {:gone, state}

    case result do
      {:granted, lease, state} ->
        Process.cancel_timer(waiter.timer)
        GenServer.reply(waiter.from, {:ok, lease})
        {kept, state}

      {:joined, state} ->
        Process.cancel_timer(waiter.timer)
        {kept, update_in(state.stats.single_flight_hits, &(&1 + 1))}

      {:gone, state} ->
        Process.cancel_timer(waiter.timer)
        {kept, state}

      :wait ->
        {[waiter | kept], state}
    end
  end

  defp start_leased_port(%{pid: pid} = _entry, _start_args, state)
       when is_pid(pid) do
    # Never start a second CLI over an entry whose process is alive.
    if Process.alive?(pid),
      do: {:reply, {:ok, pid}, state},
      else: {:reply, {:error, :port_down}, state}
  end

  defp start_leased_port(entry, start_args, state) do
    started_at = System.monotonic_time(:microsecond)

    case start_supervised_port(start_args) do
      {:ok, pid} ->
        entry = %{
          entry
          | pid: pid,
            port_ref: Process.monitor(pid),
            created_at: System.monotonic_time(:millisecond)
        }

        state = put_entry(state, entry)

        stats =
          state.stats
          |> update_stats(:port_created)
          |> update_stats({:pool_size_update, map_size(state.ports)})

        :telemetry.execute(
          [:tailwind_port_pool, :pool, :port_created],
          %{
            creation_duration: System.monotonic_time(:microsecond) - started_at,
            pool_size: map_size(state.ports)
          },
          %{config_hash: entry.config_hash, port: nil, pid: pid, opts: start_args}
        )

        {:reply, {:ok, pid}, %{state | stats: stats}}

      {:error, reason} ->
        :telemetry.execute(
          [:tailwind_port_pool, :pool, :port_creation_failed],
          %{creation_duration: System.monotonic_time(:microsecond) - started_at},
          %{config_hash: entry.config_hash, error: reason, opts: start_args}
        )

        {:reply, {:error, reason}, state}
    end
  end

  defp start_supervised_port(start_args) do
    name = {:via, Registry, {@registry, {__MODULE__, make_ref()}}}

    spec = %{
      id: Standalone,
      start: {Standalone, :start_link, [Keyword.put(start_args, :name, name)]},
      restart: :temporary,
      shutdown: 5_000
    }

    case DynamicSupervisor.start_child(@supervisor, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  catch
    :exit, reason -> {:error, {:supervisor_unavailable, reason}}
  end

  defp checkin(entry, outcome, state) do
    demonitor(entry.owner_ref)
    reply_followers(entry, outcome)

    entry = %{
      entry
      | build_count: entry.build_count + 1,
        last_used: System.monotonic_time(:millisecond),
        owner: nil,
        owner_ref: nil,
        lease_ref: nil,
        followers: []
    }

    keep? =
      match?({:ok, _}, outcome) and entry.watch? and is_pid(entry.pid) and
        Process.alive?(entry.pid) and state.options[:port_idle_timeout_ms] > 0

    cond do
      keep? -> put_entry(state, %{entry | status: :idle, content_key: nil})
      match?({:ok, _}, outcome) -> retire(entry, state, :completed)
      true -> retire(entry, state, :compile_failed)
    end
  end

  defp reply_followers(%{followers: followers}, outcome) do
    Enum.each(followers, &GenServer.reply(&1, {:shared, outcome}))
  end

  defp handle_down(ref, reason, state) do
    cond do
      entry = Enum.find(Map.values(state.ports), &(&1.owner_ref == ref)) ->
        # The caller holding this port died mid-compile. Nobody will check it
        # in, so retire it now and give its slot to the next waiter.
        Logger.debug("Pool caller went down (#{inspect(reason)}); retiring its port")
        reply_followers(entry, {:error, :owner_down})
        state = retire(%{entry | owner_ref: nil}, state, :owner_down)
        dispatch(%{state | stats: update_stats(state.stats, :compile_error)})

      entry = Enum.find(Map.values(state.ports), &(&1.port_ref == ref)) ->
        Logger.info("Tailwind process #{inspect(entry.pid)} went down: #{inspect(reason)}")

        case entry.status do
          :idle ->
            dispatch(retire(%{entry | port_ref: nil}, state, :port_down))

          :busy ->
            # Its caller will notice and check in an error, which retires it.
            put_entry(state, %{entry | pid: nil, port_ref: nil})
        end

      true ->
        state
    end
  end

  # Stops the CLI process, deletes the pool-managed temp files and frees the
  # slot. The single exit path for every port.
  defp retire(entry, state, reason) do
    demonitor(entry.port_ref)
    demonitor(entry.owner_ref)
    stop_port(entry.pid)
    Enum.each(entry.managed_paths, &File.rm/1)

    now = System.monotonic_time(:millisecond)
    lifetime = now - entry.created_at

    :telemetry.execute(
      [:tailwind_port_pool, :pool, :port_terminated],
      %{
        port_lifetime: lifetime,
        build_count: entry.build_count,
        idle_time: now - entry.last_used
      },
      %{config_hash: entry.config_hash, port: nil, reason: reason}
    )

    stats =
      if entry.pid,
        do: update_stats(state.stats, {:port_terminated, lifetime, entry.build_count}),
        else: state.stats

    %{state | ports: Map.delete(state.ports, entry.config_hash), stats: stats}
  end

  defp stop_port(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      case DynamicSupervisor.terminate_child(@supervisor, pid) do
        :ok -> :ok
        {:error, :not_found} -> GenServer.stop(pid, :shutdown, 5_000)
      end
    end

    :ok
  catch
    :exit, _ -> :ok
  end

  defp stop_port(_), do: :ok

  # A pool that was killed outright never ran terminate/2. Its ports are still
  # registered under the pool's key; stop them before serving anything.
  defp reap_orphans do
    if Process.whereis(@registry) do
      @registry
      |> Registry.select([{{{__MODULE__, :_}, :"$1", :_}, [], [:"$1"]}])
      |> Enum.each(&stop_port/1)
    end

    :ok
  end

  defp warm_one(config, state) do
    opts = normalize_operation_opts(config)
    config_hash = hash_config(opts)

    cond do
      not watch_mode?(opts) ->
        state

      Map.has_key?(state.ports, config_hash) ->
        state

      map_size(state.ports) >= state.options[:max_pool_size] ->
        state

      true ->
        warm_start(opts, config_hash, state)
    end
  end

  defp warm_start(opts, config_hash, state) do
    request = %{config_hash: config_hash, opts: opts, content_key: nil}
    paths = build_port_paths(opts)

    with :ok <- ensure_directory(paths.output_path),
         :ok <- ensure_directory(paths.input_path),
         :ok <- ensure_input_placeholder(paths.input_path),
         {:ok, pid} <- start_supervised_port(build_start_args(opts)) do
      entry = %{new_entry(request) | pid: pid, port_ref: Process.monitor(pid), status: :idle}

      state
      |> cache_config(request)
      |> put_entry(entry)
      |> Map.update!(:stats, &update_stats(&1, :port_created))
    else
      _ -> state
    end
  end

  defp cleanup_idle_ports(state) do
    started = System.monotonic_time(:microsecond)
    now = System.monotonic_time(:millisecond)
    idle_timeout = state.options[:port_idle_timeout_ms]

    expired =
      state.ports
      |> Map.values()
      |> Enum.filter(&(&1.status == :idle and now - &1.last_used >= idle_timeout))

    state = Enum.reduce(expired, state, &retire(&1, &2, :idle_timeout))

    {active_cache, expired_cache} =
      Enum.split_with(state.config_cache, fn {_hash, {_config, ts}} ->
        ts >= now - @config_cache_ttl
      end)

    :telemetry.execute(
      [:tailwind_port_pool, :maintenance, :cleanup_completed],
      %{
        cleanup_duration: System.monotonic_time(:microsecond) - started,
        ports_terminated: length(expired),
        cache_entries_expired: length(expired_cache),
        active_ports: map_size(state.ports),
        active_cache_entries: length(active_cache)
      },
      %{}
    )

    dispatch(%{state | config_cache: Map.new(active_cache)})
  end

  ## Helpers

  defp put_entry(state, entry),
    do: %{state | ports: Map.put(state.ports, entry.config_hash, entry)}

  defp find_by_lease(state, lease_ref) do
    Enum.find(Map.values(state.ports), &(&1.lease_ref == lease_ref))
  end

  defp lru_idle(state) do
    state.ports
    |> Map.values()
    |> Enum.filter(&(&1.status == :idle))
    |> Enum.min_by(& &1.last_used, fn -> nil end)
  end

  defp cache_config(state, request) do
    entry = {request.opts, System.monotonic_time(:millisecond)}
    %{state | config_cache: Map.put(state.config_cache, request.config_hash, entry)}
  end

  defp demonitor(ref) when is_reference(ref), do: Process.demonitor(ref, [:flush])
  defp demonitor(_), do: true

  defp schedule_cleanup(options) do
    Process.send_after(self(), :cleanup_idle_ports, options[:cleanup_interval])
  end

  defp record_outcome(stats, {:ok, result}) do
    stats
    |> update_stats(:compile_success)
    |> maybe_update_for_degraded(result)
  end

  defp record_outcome(stats, _error), do: update_stats(stats, :compile_error)

  defp build_stats(state) do
    stats = state.stats
    ports = Map.values(state.ports)
    total_compilations = max(stats.total_compilations, 1)

    avg_port_lifetime_ms =
      if stats.terminated_ports > 0,
        do: stats.total_port_lifetime / stats.terminated_ports,
        else: 0.0

    compilation_count_per_port =
      if stats.port_creations > 0,
        do: stats.total_compilations / stats.port_creations,
        else: 0.0

    average_compilation_time_ms = stats.average_compilation_time / 1_000.0
    baseline_ms = state.options[:baseline_compilation_time_ms]

    compilation_time_improvement =
      if is_number(baseline_ms) and baseline_ms > 0 and average_compilation_time_ms > 0,
        do: (baseline_ms - average_compilation_time_ms) / baseline_ms,
        else: nil

    derived_metrics = %{
      port: %{
        reuse_rate: stats.port_reuses / total_compilations,
        avg_lifetime_ms: avg_port_lifetime_ms,
        compilation_count_per_port: compilation_count_per_port
      },
      performance: %{
        average_compilation_time_ms: average_compilation_time_ms,
        compilation_time_improvement: compilation_time_improvement,
        degraded_rate: stats.degraded_compilations / total_compilations
      }
    }

    enhanced =
      Map.merge(stats, %{
        active_ports: length(ports),
        busy_ports: Enum.count(ports, &(&1.status == :busy)),
        max_pool_size: state.options[:max_pool_size],
        cache_size: map_size(state.config_cache),
        active_watches: Enum.count(ports, & &1.watch?),
        queue_size: :queue.len(state.waiting),
        derived_metrics: derived_metrics
      })

    :telemetry.execute(
      [:tailwind_port_pool, :metrics, :snapshot],
      %{
        reuse_rate: derived_metrics.port.reuse_rate,
        avg_port_lifetime_ms: derived_metrics.port.avg_lifetime_ms,
        compilation_count_per_port: derived_metrics.port.compilation_count_per_port,
        average_compilation_time_ms: average_compilation_time_ms,
        degraded_rate: derived_metrics.performance.degraded_rate,
        compilation_time_improvement: compilation_time_improvement
      },
      %{
        active_ports: enhanced.active_ports,
        cache_size: enhanced.cache_size,
        queue_size: enhanced.queue_size
      }
    )

    enhanced
  end

  defp hash_config(opts) do
    normalized =
      opts
      |> Enum.sort()
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    :crypto.hash(:sha256, :erlang.term_to_binary(normalized))
    |> Base.encode16()
  end

  defp watch_mode?(opts) do
    case Keyword.get(opts, :watch) do
      nil -> false
      false -> false
      _ -> true
    end
  end

  defp build_start_args(opts) do
    {cmd, _remainder} = Keyword.pop(opts, :cmd)

    keyword_opts =
      [
        input: Keyword.get(opts, :input),
        output: Keyword.get(opts, :output),
        content: Keyword.get(opts, :content),
        config: Keyword.get(opts, :config),
        postcss: Keyword.get(opts, :postcss),
        minify: Keyword.get(opts, :minify),
        watch: Keyword.get(opts, :watch),
        poll: Keyword.get(opts, :poll),
        optimize: Keyword.get(opts, :optimize),
        cwd: Keyword.get(opts, :cwd),
        map: Keyword.get(opts, :map)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> CliCompatibility.filter_args_for_current_version()

    []
    |> maybe_put(:cmd, normalize_cmd(cmd))
    |> Keyword.put(:opts, build_cli_args_from_opts(keyword_opts))
  end

  defp build_cli_args_from_opts(opts) when is_list(opts) do
    Enum.reduce(opts, [], &append_cli_arg/2)
  end

  defp append_cli_arg({:input, value}, acc), do: add_cli_option(acc, "-i", value)
  defp append_cli_arg({:output, value}, acc), do: add_cli_option(acc, "-o", value)
  defp append_cli_arg({:content, value}, acc), do: add_cli_option(acc, "--content", value)
  defp append_cli_arg({:config, value}, acc), do: add_cli_option(acc, "-c", value)
  defp append_cli_arg({:postcss, value}, acc), do: add_cli_option(acc, "--postcss", value)
  defp append_cli_arg({:minify, value}, acc), do: add_cli_flag(acc, "--minify", value)
  defp append_cli_arg({:watch, value}, acc), do: add_cli_flag(acc, "--watch", value)
  defp append_cli_arg({:poll, value}, acc), do: add_cli_flag(acc, "--poll", value)
  defp append_cli_arg({:optimize, value}, acc), do: add_cli_flag(acc, "--optimize", value)
  defp append_cli_arg({:cwd, value}, acc), do: add_cli_option(acc, "--cwd", value)
  defp append_cli_arg({:map, value}, acc), do: add_cli_flag(acc, "--map", value)
  defp append_cli_arg({_key, _value}, acc), do: acc

  defp add_cli_option(opts, _flag, nil), do: opts

  defp add_cli_option(opts, flag, value) when is_list(value) do
    Enum.reduce(value, opts, fn single, acc -> add_cli_option(acc, flag, single) end)
  end

  defp add_cli_option(opts, flag, value), do: opts ++ [flag, to_string(value)]

  defp add_cli_flag(opts, _flag, nil), do: opts
  defp add_cli_flag(opts, flag, true), do: opts ++ [flag]
  defp add_cli_flag(opts, _flag, false), do: opts

  defp add_cli_flag(opts, flag, value) when is_binary(value),
    do: add_cli_flag(opts, flag, String.downcase(value) == "true")

  defp add_cli_flag(opts, flag, value) when is_atom(value),
    do: add_cli_flag(opts, flag, value == true)

  defp add_cli_flag(opts, _flag, _value), do: opts

  defp maybe_put(list, _key, nil), do: list
  defp maybe_put(list, key, value), do: Keyword.put(list, key, value)

  defp normalize_cmd(nil), do: nil

  defp normalize_cmd(cmd) when is_binary(cmd) do
    cond do
      Path.type(cmd) == :absolute and File.exists?(cmd) -> cmd
      File.exists?(Path.expand(cmd)) -> Path.expand(cmd)
      executable = System.find_executable(cmd) -> executable
      true -> cmd
    end
  end

  # Hash the caller-provided opts once so every managed default path is stable
  # for the same logical configuration — this keeps the config hash (and so
  # port reuse) intact across compiles.
  defp normalize_operation_opts(opts) when is_list(opts) do
    hash = :erlang.phash2(opts)

    opts
    |> put_default_opt(:content, managed_path("content_#{hash}.html"))
    |> put_default_opt(:input, managed_path("input_#{hash}.css"))
    |> put_default_opt(:output, managed_path("output_#{hash}.css"))
  end

  defp normalize_operation_opts(opts), do: opts |> Enum.into([]) |> normalize_operation_opts()

  defp put_default_opt(opts, key, default) do
    case Keyword.get(opts, key) do
      nil -> Keyword.put(opts, key, default)
      [] -> Keyword.put(opts, key, default)
      _ -> opts
    end
  end

  @doc false
  # Pool-managed scratch location for callers that omit :input/:output/:content.
  # Files here belong to the pool and are deleted when their port retires.
  def managed_dir, do: Path.join(System.tmp_dir!(), "tailwind_port")

  defp managed_path(filename), do: Path.join(managed_dir(), filename)

  defp managed_paths(opts) do
    dir = managed_dir()

    [:content, :input, :output]
    |> Enum.map(&Keyword.get(opts, &1))
    |> Enum.filter(&(is_binary(&1) and Path.dirname(&1) == dir))
  end

  defp build_port_paths(opts) do
    %{
      content_paths: normalize_content_paths(Keyword.get(opts, :content)),
      output_path: normalized_path(Keyword.get(opts, :output)),
      input_path: normalized_path(Keyword.get(opts, :input))
    }
  end

  defp normalize_content_paths(nil), do: []

  defp normalize_content_paths(paths) when is_list(paths),
    do: Enum.flat_map(paths, &normalize_content_paths/1)

  defp normalize_content_paths(path) when is_binary(path), do: [Path.expand(path)]

  defp normalize_content_paths(path) when is_atom(path),
    do: [path |> Atom.to_string() |> Path.expand()]

  defp normalize_content_paths(path), do: [to_string(path) |> Path.expand()]

  defp normalized_path(nil), do: nil
  defp normalized_path(path) when is_binary(path), do: Path.expand(path)
  defp normalized_path(path) when is_atom(path), do: Path.expand(Atom.to_string(path))
  defp normalized_path(path), do: Path.expand(to_string(path))

  defp select_primary_content_path([]), do: {:error, :missing_content_path}

  defp select_primary_content_path(paths) do
    case Enum.find(paths, &writeable_content_path?/1) do
      nil -> {:error, :invalid_content_path}
      path -> {:ok, path}
    end
  end

  defp writeable_content_path?(path) when is_binary(path) do
    not String.contains?(path, "*") and not String.contains?(path, "?")
  end

  defp writeable_content_path?(_), do: false

  defp ensure_directory(nil), do: :ok
  defp ensure_directory(path), do: path |> Path.dirname() |> File.mkdir_p()

  defp ensure_input_placeholder(nil), do: :ok

  defp ensure_input_placeholder(path) do
    if File.exists?(path), do: :ok, else: File.write(path, "/* tailwind input */\n")
  end

  defp remove_file(nil), do: :ok

  defp remove_file(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  ## Stats

  defp init_stats do
    %{
      total_compilations: 0,
      successful_compilations: 0,
      failed_compilations: 0,
      degraded_compilations: 0,
      batch_compilations: 0,
      port_creations: 0,
      port_reuses: 0,
      cache_hits: 0,
      cache_misses: 0,
      single_flight_hits: 0,
      average_compilation_time: 0.0,
      peak_pool_size: 0,
      total_port_creation_time: 0,
      total_compilation_time: 0,
      last_compilation_duration: 0,
      pool_exhaustions: 0,
      config_variations: 0,
      terminated_ports: 0,
      total_port_lifetime: 0,
      total_port_builds_recorded: 0,
      started_at: System.monotonic_time(:millisecond)
    }
  end

  defp update_stats(stats, :compile_success) do
    %{
      stats
      | total_compilations: stats.total_compilations + 1,
        successful_compilations: stats.successful_compilations + 1
    }
  end

  defp update_stats(stats, :compile_error) do
    %{
      stats
      | total_compilations: stats.total_compilations + 1,
        failed_compilations: stats.failed_compilations + 1
    }
  end

  defp update_stats(stats, :degraded_compile),
    do: %{stats | degraded_compilations: stats.degraded_compilations + 1}

  defp update_stats(stats, :port_created),
    do: %{stats | port_creations: stats.port_creations + 1}

  defp update_stats(stats, :port_reused),
    do: %{stats | port_reuses: stats.port_reuses + 1, cache_hits: stats.cache_hits + 1}

  defp update_stats(stats, :pool_exhausted),
    do: %{stats | pool_exhaustions: stats.pool_exhaustions + 1}

  defp update_stats(stats, {:pool_size_update, size}),
    do: %{stats | peak_pool_size: max(stats.peak_pool_size, size)}

  defp update_stats(stats, {:compilation_time, duration_microseconds}) do
    new_total_time = stats.total_compilation_time + duration_microseconds

    new_avg =
      if stats.total_compilations > 0,
        do: new_total_time / stats.total_compilations,
        else: 0.0

    %{
      stats
      | total_compilation_time: new_total_time,
        average_compilation_time: new_avg,
        last_compilation_duration: duration_microseconds
    }
  end

  defp update_stats(stats, {:port_terminated, lifetime_ms, build_count}) do
    %{
      stats
      | terminated_ports: stats.terminated_ports + 1,
        total_port_lifetime: stats.total_port_lifetime + lifetime_ms,
        total_port_builds_recorded: stats.total_port_builds_recorded + build_count
    }
  end

  defp maybe_update_for_degraded(stats, %{readiness: :degraded}),
    do: update_stats(stats, :degraded_compile)

  defp maybe_update_for_degraded(stats, _result), do: stats

  defp default_options do
    [
      max_pool_size: 3,
      max_queue: 8,
      checkout_timeout_ms: 30_000,
      port_idle_timeout_ms: :timer.minutes(10),
      cleanup_interval: :timer.minutes(1),
      single_flight: true,
      port_ready_timeout: 1_000,
      baseline_compilation_time_ms: nil,
      # A cold Tailwind v4 run over a real project takes multiple seconds —
      # ~6s for a themed app. A deadline is an error, never the previous
      # artifact, so this must comfortably exceed a real cold build.
      compile_timeout_ms: 20_000
    ]
  end
end
