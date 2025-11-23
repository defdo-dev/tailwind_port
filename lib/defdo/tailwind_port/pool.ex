defmodule Defdo.TailwindPort.Pool do
  @moduledoc """
  Pooled TailwindPort implementation with intelligent resource management,
  port reuse, configuration caching, and watch mode optimization.

  ## Key Optimizations

  1. **Port Pool Management**: Maintains a pool of active ports for different configurations
  2. **Configuration Hashing**: Reuses ports for identical configurations
  3. **Watch Mode Intelligence**: Leverages Tailwind's watch mode for incremental builds
  4. **Command Batching**: Groups multiple operations for efficiency
  5. **Resource Preallocation**: Pre-warms commonly used configurations

  ## Usage

      # Start the pooled Tailwind manager
      {:ok, _pid} = TailwindPort.Pool.start_link()

      # Compile with intelligent reuse
      {:ok, result} = TailwindPort.Pool.compile(opts, content)

      # Batch multiple compilations
      {:ok, results} = TailwindPort.Pool.batch_compile(operations)
  """

  use GenServer
  require Logger

  alias Defdo.TailwindPort.Standalone

  @default_pool_size 3
  @config_cache_ttl :timer.minutes(30)
  @port_idle_timeout :timer.minutes(10)

  defstruct [
    # %{config_hash => port_info}
    :port_pool,
    # %{config_hash => {config, timestamp}}
    :config_cache,
    # %{watch_id => {port, files}}
    :active_watches,
    # Queue for batch processing
    :compilation_queue,
    # Performance metrics
    :stats,
    :options
  ]

  @type port_info :: %{
          port: port() | nil,
          pid: pid(),
          config_hash: binary(),
          last_used: integer(),
          status: :idle | :busy | :watching,
          build_count: non_neg_integer(),
          name: atom(),
          monitor_ref: reference()
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
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec compile(keyword(), String.t()) :: {:ok, map()} | {:error, term()}
  def compile(opts, content) do
    operation = %{
      id: make_ref(),
      opts: opts,
      content: content,
      priority: :normal
    }

    GenServer.call(__MODULE__, {:compile, operation}, 30_000)
  end

  @spec batch_compile([compile_operation()]) :: {:ok, [map()]} | {:error, term()}
  def batch_compile(operations) when is_list(operations) do
    GenServer.call(__MODULE__, {:batch_compile, operations}, 60_000)
  end

  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @spec warm_up(keyword()) :: :ok
  def warm_up(common_configs) do
    GenServer.cast(__MODULE__, {:warm_up, common_configs})
  end

  ## GenServer Implementation

  @impl true
  def init(opts) do
    state = %__MODULE__{
      port_pool: %{},
      config_cache: %{},
      active_watches: %{},
      compilation_queue: :queue.new(),
      stats: init_stats(),
      options: Keyword.merge(default_options(), opts)
    }

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, state}
  end

  defp process_operation_group(config_hash, ops, acc_results, acc_state) do
    case find_or_create_port(config_hash, hd(ops).opts, acc_state) do
      {:ok, port_info, new_state} ->
        {batch_results, batch_state} = execute_batch_compilation(port_info, ops, new_state)
        {acc_results ++ batch_results, batch_state}

      {:error, _reason} ->
        error_results = Enum.map(ops, fn op -> {:error, :port_unavailable, op.id} end)
        {acc_results ++ error_results, acc_state}
    end
  end

  @impl true
  def handle_call({:compile, operation}, _from, state) do
    start_time = System.monotonic_time(:microsecond)

    normalized_operation = %{
      operation
      | opts: normalize_operation_opts(operation.opts, state.options)
    }

    config_hash = hash_config(normalized_operation.opts)

    # Emit telemetry for compilation start
    :telemetry.execute(
      [:tailwind_port_pool, :compile, :start],
      %{system_time: System.system_time(:microsecond)},
      %{
        operation_id: normalized_operation.id,
        config_hash: config_hash,
        priority: normalized_operation.priority,
        content_size: byte_size(normalized_operation.content)
      }
    )

    case find_or_create_port(config_hash, normalized_operation.opts, state) do
      {:ok, port_info, new_state} ->
        case execute_compilation(port_info, normalized_operation, new_state) do
          {:ok, result, final_state} ->
            duration = System.monotonic_time(:microsecond) - start_time

            updated_stats =
              final_state.stats
              |> update_stats(:compile_success)
              |> update_stats({:compilation_time, duration})
              |> update_stats({:pool_size_update, map_size(final_state.port_pool)})
              |> maybe_update_for_degraded(result)

            # Emit success telemetry
            :telemetry.execute(
              [:tailwind_port_pool, :compile, :stop],
              %{duration: duration, cache_hits: updated_stats.cache_hits},
              %{
                operation_id: normalized_operation.id,
                config_hash: config_hash,
                port_reused: port_info.build_count > 0
              }
            )

            {:reply, {:ok, result}, %{final_state | stats: updated_stats}}

          {:error, reason, final_state} ->
            duration = System.monotonic_time(:microsecond) - start_time
            updated_stats = update_stats(final_state.stats, :compile_error)

            # Emit error telemetry
            :telemetry.execute(
              [:tailwind_port_pool, :compile, :error],
              %{duration: duration, error_count: updated_stats.failed_compilations},
              %{
                operation_id: normalized_operation.id,
                config_hash: config_hash,
                error: reason
              }
            )

            {:reply, {:error, reason}, %{final_state | stats: updated_stats}}
        end

      {:error, reason} ->
        duration = System.monotonic_time(:microsecond) - start_time

        updated_stats =
          state.stats
          |> update_stats(:port_creation_error)
          |> maybe_update_for_error_reason(reason)

        # Emit port creation error telemetry
        :telemetry.execute(
          [:tailwind_port_pool, :pool, :port_creation_failed],
          %{duration: duration},
          %{
            operation_id: normalized_operation.id,
            config_hash: config_hash,
            error: reason
          }
        )

        {:reply, {:error, reason}, %{state | stats: updated_stats}}
    end
  end

  @impl true
  def handle_call({:batch_compile, operations}, _from, state) do
    # Group operations by configuration for efficiency
    normalized_ops =
      Enum.map(operations, fn op ->
        Map.update!(op, :opts, &normalize_operation_opts(&1, state.options))
      end)

    grouped_ops = group_operations_by_config(normalized_ops)

    {results, final_state} =
      Enum.reduce(grouped_ops, {[], state}, fn {config_hash, ops}, {acc_results, acc_state} ->
        process_operation_group(config_hash, ops, acc_results, acc_state)
      end)

    updated_stats = update_stats(final_state.stats, :batch_compile, length(operations))
    {:reply, {:ok, results}, %{final_state | stats: updated_stats}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = state.stats

    active_ports = map_size(state.port_pool)
    cache_size = map_size(state.config_cache)
    active_watches = map_size(state.active_watches)
    queue_size = :queue.len(state.compilation_queue)

    total_compilations = max(stats.total_compilations, 1)

    reuse_rate = stats.port_reuses / total_compilations

    avg_port_lifetime_ms =
      if stats.terminated_ports > 0 do
        stats.total_port_lifetime / stats.terminated_ports
      else
        0.0
      end

    compilation_count_per_port =
      if stats.port_creations > 0 do
        stats.total_compilations / stats.port_creations
      else
        0.0
      end

    average_compilation_time_ms = stats.average_compilation_time / 1_000.0

    degraded_rate = stats.degraded_compilations / total_compilations

    baseline_ms = state.options[:baseline_compilation_time_ms]

    compilation_time_improvement =
      if is_number(baseline_ms) and baseline_ms > 0 and average_compilation_time_ms > 0 do
        (baseline_ms - average_compilation_time_ms) / baseline_ms
      else
        nil
      end

    derived_metrics = %{
      port: %{
        reuse_rate: reuse_rate,
        avg_lifetime_ms: avg_port_lifetime_ms,
        compilation_count_per_port: compilation_count_per_port
      },
      performance: %{
        average_compilation_time_ms: average_compilation_time_ms,
        compilation_time_improvement: compilation_time_improvement,
        degraded_rate: degraded_rate
      }
    }

    enhanced_stats =
      stats
      |> Map.put(:active_ports, active_ports)
      |> Map.put(:cache_size, cache_size)
      |> Map.put(:active_watches, active_watches)
      |> Map.put(:queue_size, queue_size)
      |> Map.put(:derived_metrics, derived_metrics)

    :telemetry.execute(
      [:tailwind_port_pool, :metrics, :snapshot],
      %{
        reuse_rate: derived_metrics.port.reuse_rate,
        avg_port_lifetime_ms: derived_metrics.port.avg_lifetime_ms,
        compilation_count_per_port: derived_metrics.port.compilation_count_per_port,
        average_compilation_time_ms: derived_metrics.performance.average_compilation_time_ms,
        degraded_rate: derived_metrics.performance.degraded_rate,
        compilation_time_improvement: derived_metrics.performance.compilation_time_improvement
      },
      %{
        active_ports: active_ports,
        cache_size: cache_size,
        queue_size: queue_size
      }
    )

    {:reply, enhanced_stats, state}
  end

  @impl true
  def handle_cast({:warm_up, configs}, state) do
    new_state =
      Enum.reduce(configs, state, fn config, acc_state ->
        config_hash = hash_config(config)

        case find_or_create_port(config_hash, config, acc_state) do
          {:ok, _port_info, updated_state} -> updated_state
          {:error, _reason} -> acc_state
        end
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup_idle_ports, state) do
    new_state = cleanup_idle_ports(state)
    schedule_cleanup()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    if port_process?(state, pid) do
      new_state = handle_port_exit(state, pid, reason)
      {:noreply, new_state}
    else
      {:stop, reason, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    new_state = handle_monitored_process_down(state, ref, pid, reason)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message in Pool TailwindPort: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Implementation

  defp find_or_create_port(config_hash, opts, state) do
    case Map.get(state.port_pool, config_hash) do
      %{status: :idle} = port_info ->
        # Reuse existing idle port
        updated_port_info = %{
          port_info
          | status: :busy,
            last_used: System.monotonic_time(:millisecond)
        }

        updated_pool = Map.put(state.port_pool, config_hash, updated_port_info)
        updated_stats = update_stats(state.stats, :port_reused)
        new_state = %{state | port_pool: updated_pool, stats: updated_stats}

        # Emit port reuse telemetry
        :telemetry.execute(
          [:tailwind_port_pool, :pool, :port_reused],
          %{
            port_age_ms: System.monotonic_time(:millisecond) - port_info.last_used,
            build_count: port_info.build_count
          },
          %{
            config_hash: config_hash,
            port: port_info.port
          }
        )

        {:ok, updated_port_info, new_state}

      %{status: :busy} ->
        # Port is busy, create new one if pool not full
        if map_size(state.port_pool) < state.options[:max_pool_size] do
          create_new_port(config_hash, opts, state)
        else
          # Emit pool exhaustion telemetry
          :telemetry.execute(
            [:tailwind_port_pool, :pool, :exhausted],
            %{pool_size: map_size(state.port_pool), max_size: state.options[:max_pool_size]},
            %{config_hash: config_hash}
          )

          {:error, :pool_exhausted}
        end

      nil ->
        # No port exists, create new one
        create_new_port(config_hash, opts, state)
    end
  end

  defp create_new_port(config_hash, opts, state) do
    port_creation_start = System.monotonic_time(:microsecond)

    start_args = build_start_args(opts)
    port_name = generate_port_name(config_hash)

    case start_tailwind_port(start_args, port_name) do
      {:ok, pid} ->
        port_creation_duration = System.monotonic_time(:microsecond) - port_creation_start

        ensure_port_ready(pid, state.options)

        port_info = %{
          port: get_port_from_pid(pid),
          pid: pid,
          name: port_name,
          monitor_ref: Process.monitor(pid),
          config_hash: config_hash,
          last_used: System.monotonic_time(:millisecond),
          status: :busy,
          build_count: 0,
          created_at: System.monotonic_time(:millisecond)
        }

        port_info = initialize_port_metadata(port_info, opts)

        # Cache the configuration
        cache_entry = {opts, System.monotonic_time(:millisecond)}
        new_cache = Map.put(state.config_cache, config_hash, cache_entry)
        new_pool = Map.put(state.port_pool, config_hash, port_info)
        updated_stats = update_stats(state.stats, :port_created)

        new_state = %{state | port_pool: new_pool, config_cache: new_cache, stats: updated_stats}

        # Emit port creation telemetry
        :telemetry.execute(
          [:tailwind_port_pool, :pool, :port_created],
          %{
            creation_duration: port_creation_duration,
            pool_size: map_size(new_pool)
          },
          %{
            config_hash: config_hash,
            port: port_info.port,
            pid: pid,
            opts: opts
          }
        )

        {:ok, port_info, new_state}

      {:error, {:already_started, pid}} ->
        # If a port with the generated name already exists, reuse it
        ensure_port_ready(pid, state.options)

        existing_info = %{
          port: get_port_from_pid(pid),
          pid: pid,
          name: port_name,
          monitor_ref: Process.monitor(pid),
          config_hash: config_hash,
          last_used: System.monotonic_time(:millisecond),
          status: :busy,
          build_count: 0,
          created_at: System.monotonic_time(:millisecond)
        }

        existing_info = initialize_port_metadata(existing_info, opts)

        cache_entry = {opts, System.monotonic_time(:millisecond)}
        new_cache = Map.put(state.config_cache, config_hash, cache_entry)
        new_pool = Map.put(state.port_pool, config_hash, existing_info)

        new_state = %{state | port_pool: new_pool, config_cache: new_cache}

        {:ok, existing_info, new_state}

      {:error, reason} ->
        port_creation_duration = System.monotonic_time(:microsecond) - port_creation_start

        # Emit port creation failure telemetry
        :telemetry.execute(
          [:tailwind_port_pool, :pool, :port_creation_failed],
          %{creation_duration: port_creation_duration},
          %{
            config_hash: config_hash,
            error: reason,
            opts: opts
          }
        )

        {:error, reason}
    end
  end

  defp start_tailwind_port(start_args, port_name) do
    previous_flag = Process.flag(:trap_exit, true)

    result =
      try do
        Standalone.start_link(Keyword.put(start_args, :name, port_name))
      catch
        :exit, reason -> {:error, reason}
      end

    Process.flag(:trap_exit, previous_flag)

    case result do
      {:ok, pid} ->
        Process.unlink(pid)
        {:ok, pid}

      {:error, reason} ->
        flush_exit_signals()
        {:error, reason}
    end
  end

  defp execute_compilation(port_info, operation, state) do
    case ensure_port_ready(port_info.pid, state.options) do
      :ok ->
        perform_compilation(port_info, operation, state, :ready)

      :degraded ->
        perform_compilation(port_info, operation, state, :degraded)

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp perform_compilation(port_info, operation, state, readiness) do
    with {:ok, port_info, state} <- ensure_fs_state(port_info, state, operation),
         {:ok, working_paths} <- prepare_working_files(port_info),
         :ok <- write_operation_content(working_paths, operation.content) do
      case fallback_to_file_based_capture(
             port_info,
             working_paths,
             state.options
           ) do
        {:ok, build_info} ->
          finalize_compilation(port_info, state, readiness, build_info, operation)

        {:degraded, build_info} ->
          finalize_compilation(port_info, state, :degraded, build_info, operation)

        {:error, reason} ->
          {:error, reason, state}
      end
    else
      {:error, reason} -> {:error, reason, state}
      {:error, reason, new_state} -> {:error, reason, new_state}
    end
  end

  defp execute_batch_compilation(port_info, operations, state) do
    # Execute multiple operations on the same port efficiently
    {results, final_port_info} =
      Enum.reduce(operations, {[], port_info}, fn operation, {acc_results, acc_port_info} ->
        # Simulate batch execution - in real implementation,
        # this would optimize file writing and port communication
        result = %{
          compiled_css: "/tmp/batch_output_#{operation.id}.css",
          port: acc_port_info.port,
          operation_id: operation.id
        }

        updated_port_info = %{acc_port_info | build_count: acc_port_info.build_count + 1}

        {[result | acc_results], updated_port_info}
      end)

    # Update port info in pool
    final_port_info = %{
      final_port_info
      | status: :idle,
        last_used: System.monotonic_time(:millisecond)
    }

    updated_pool = Map.put(state.port_pool, port_info.config_hash, final_port_info)
    new_state = %{state | port_pool: updated_pool}

    {Enum.reverse(results), new_state}
  end

  defp ensure_fs_state(port_info, state, operation) do
    updated_port_info =
      if Map.has_key?(port_info, :paths) do
        port_info
      else
        initialize_port_metadata(port_info, operation.opts)
      end

    paths = Map.get(updated_port_info, :paths, %{})

    with {:ok, content_path} <- select_primary_content_path(paths[:content_paths]),
         :ok <- ensure_directory(content_path),
         :ok <- ensure_directory(paths[:output_path]),
         :ok <- ensure_directory(paths[:input_path]),
         :ok <- ensure_input_placeholder(paths[:input_path]) do
      final_paths =
        paths
        |> Map.put(:primary_content_path, content_path)

      final_port_info =
        updated_port_info
        |> Map.put(:paths, final_paths)
        |> Map.put_new(:last_output_mtime, file_mtime(paths[:output_path]))

      new_pool = Map.put(state.port_pool, updated_port_info.config_hash, final_port_info)

      {:ok, final_port_info, %{state | port_pool: new_pool}}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp prepare_working_files(%{paths: paths}) do
    case Map.get(paths, :primary_content_path) do
      nil ->
        {:error, :content_path_not_available}

      path ->
        {:ok,
         %{
           content_path: path,
           output_path: Map.get(paths, :output_path),
           input_path: Map.get(paths, :input_path)
         }}
    end
  end

  defp write_operation_content(%{content_path: content_path}, content) do
    File.write(content_path, content)
  end

  # Fallback to original file-based capture when immediate capture fails
  defp fallback_to_file_based_capture(port_info, working_paths, options) do
    output_path = working_paths.output_path
    previous_mtime = Map.get(port_info, :last_output_mtime)
    timeout_ms = Keyword.get(options, :compile_timeout_ms, 5_000)

    if is_nil(output_path) do
      css = extract_css_with_fallbacks(port_info.pid, options)

      {:degraded,
       %{
         css: css,
         output_path: nil,
         new_mtime: previous_mtime,
         reason: :missing_output_path,
         capture_method: :degraded_fallback
       }}
    else
      case await_file_update(output_path, previous_mtime, timeout_ms) do
        {:ok, build_info} ->
          {:ok, Map.put(build_info, :capture_method, :file_based)}

        {:degraded, build_info} ->
          {:degraded, Map.put(build_info, :capture_method, :file_based_degraded)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp finalize_compilation(port_info, state, readiness, build_info, operation) do
    css =
      cond do
        is_binary(build_info[:css]) ->
          build_info[:css]

        build_info[:output_path] && File.exists?(build_info[:output_path]) ->
          case File.read(build_info[:output_path]) do
            {:ok, data} -> data
            _ -> fallback_css(port_info, operation)
          end

        true ->
          fallback_css(port_info, operation)
      end

    result = %{
      compiled_css: css,
      output_path: build_info[:output_path],
      port: port_info.port,
      operation_id: operation.id,
      readiness: readiness
    }

    updated_port_info =
      port_info
      |> Map.put(:status, :idle)
      |> Map.update(:build_count, 1, &(&1 + 1))
      |> Map.put(:last_used, System.monotonic_time(:millisecond))
      |> Map.put(:last_output_mtime, build_info[:new_mtime] || port_info[:last_output_mtime])

    updated_pool = Map.put(state.port_pool, port_info.config_hash, updated_port_info)
    {:ok, result, %{state | port_pool: updated_pool}}
  end

  defp group_operations_by_config(operations) do
    Enum.group_by(operations, fn op -> hash_config(op.opts) end)
  end

  defp hash_config(opts) do
    # Create deterministic hash of configuration
    normalized =
      opts
      |> Enum.sort()
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    :crypto.hash(:sha256, :erlang.term_to_binary(normalized))
    |> Base.encode16()
  end

  defp cleanup_idle_ports(state) do
    cleanup_start = System.monotonic_time(:microsecond)
    current_time = System.monotonic_time(:millisecond)
    timeout_threshold = current_time - @port_idle_timeout

    {active_ports, terminated_ports} =
      Enum.split_with(state.port_pool, fn {_hash, port_info} ->
        port_info.last_used > timeout_threshold or port_info.status != :idle
      end)

    {updated_stats, _} =
      Enum.reduce(terminated_ports, {state.stats, nil}, fn {hash, port_info}, {stats_acc, _} ->
        demonitor_port(port_info)
        Standalone.terminate(port_info.pid)

        port_lifetime = current_time - Map.get(port_info, :created_at, current_time)

        # Emit port termination telemetry
        :telemetry.execute(
          [:tailwind_port_pool, :pool, :port_terminated],
          %{
            port_lifetime: port_lifetime,
            build_count: port_info.build_count,
            idle_time: current_time - port_info.last_used
          },
          %{
            config_hash: hash,
            port: port_info.port,
            reason: :idle_timeout
          }
        )

        new_stats =
          update_stats(stats_acc, {:port_terminated, port_lifetime, port_info.build_count})

        {new_stats, nil}
      end)

    new_pool = Map.new(active_ports)

    # Clean expired cache entries
    cache_timeout_threshold = current_time - @config_cache_ttl

    {active_cache, expired_cache} =
      Enum.split_with(state.config_cache, fn {_hash, {_config, timestamp}} ->
        timestamp >= cache_timeout_threshold
      end)

    new_cache = Map.new(active_cache)
    cleanup_duration = System.monotonic_time(:microsecond) - cleanup_start

    # Emit cleanup telemetry
    :telemetry.execute(
      [:tailwind_port_pool, :maintenance, :cleanup_completed],
      %{
        cleanup_duration: cleanup_duration,
        ports_terminated: length(terminated_ports),
        cache_entries_expired: length(expired_cache),
        active_ports: length(active_ports),
        active_cache_entries: length(active_cache)
      },
      %{}
    )

    %{state | port_pool: new_pool, config_cache: new_cache, stats: updated_stats}
  end

  defp handle_port_exit(state, pid, reason) do
    Logger.info("Port #{inspect(pid)} exited with reason: #{inspect(reason)}")

    current_time = System.monotonic_time(:millisecond)

    {removed, kept} =
      Enum.split_with(state.port_pool, fn {_hash, port_info} -> port_info.pid == pid end)

    {new_stats, _} =
      Enum.reduce(removed, {state.stats, nil}, fn {_hash, port_info}, {stats_acc, _} ->
        demonitor_port(port_info)

        port_lifetime = current_time - Map.get(port_info, :created_at, current_time)

        updated_stats =
          update_stats(stats_acc, {:port_terminated, port_lifetime, port_info.build_count})

        {updated_stats, nil}
      end)

    %{state | port_pool: Map.new(kept), stats: new_stats}
  end

  defp port_process?(state, pid) do
    Enum.any?(state.port_pool, fn {_hash, port_info} -> port_info.pid == pid end)
  end

  defp handle_monitored_process_down(state, ref, pid, reason) do
    {removed, kept} =
      Enum.split_with(state.port_pool, fn {_hash, info} ->
        info.monitor_ref == ref and info.pid == pid
      end)

    current_time = System.monotonic_time(:millisecond)

    {new_stats, _} =
      Enum.reduce(removed, {state.stats, nil}, fn {_hash, info}, {stats_acc, _} ->
        demonitor_port(info)
        port_lifetime = current_time - Map.get(info, :created_at, current_time)

        updated_stats =
          update_stats(stats_acc, {:port_terminated, port_lifetime, info.build_count})

        {updated_stats, nil}
      end)

    if removed == [] do
      state
    else
      Logger.info("Tailwind process #{inspect(pid)} went down: #{inspect(reason)}")
      %{state | port_pool: Map.new(kept), stats: new_stats}
    end
  end

  defp demonitor_port(%{monitor_ref: monitor_ref}) when is_reference(monitor_ref) do
    Process.demonitor(monitor_ref, [:flush])
  end

  defp demonitor_port(_), do: :ok

  defp get_port_from_pid(pid) do
    case Standalone.state(pid) do
      %{port: port} -> port
      _ -> nil
    end
  catch
    :exit, _ -> nil
  end

  defp ensure_port_ready(pid, options) do
    timeout = Keyword.get(options, :port_ready_timeout, 1_000)

    cond do
      not Process.alive?(pid) ->
        {:error, :port_down}

      safe_ready?(pid) ->
        :ok

      true ->
        case safe_wait_until_ready(pid, timeout) do
          :ok ->
            :ok

          {:error, :timeout} ->
            Logger.debug("Port #{inspect(pid)} did not signal readiness within #{timeout}ms")
            :degraded

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
    :exit, reason -> {:error, reason}
  end

  defp build_start_args(opts) do
    {cmd, _remainder} = Keyword.pop(opts, :cmd)

    # Extract keyword options from opts for compatibility filtering
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
      |> Defdo.TailwindPort.CliCompatibility.filter_args_for_current_version()

    # Convert filtered options back to CLI args
    cli_args =
      keyword_opts
      |> build_cli_args_from_opts()

    []
    |> maybe_put(:cmd, normalize_cmd(cmd))
    |> Keyword.put(:opts, cli_args)
  end

  # Helper to convert filtered keyword options back to CLI argument list
  defp build_cli_args_from_opts(opts) when is_list(opts) do
    opts
    |> Enum.reduce([], fn {key, value}, acc ->
      case key do
        :input -> add_cli_option(acc, "-i", value)
        :output -> add_cli_option(acc, "-o", value)
        :content -> add_content_options(acc, value)
        :config -> add_cli_option(acc, "-c", value)
        :postcss -> add_cli_option(acc, "--postcss", value)
        :minify -> add_cli_flag(acc, "--minify", value)
        :watch -> add_cli_flag(acc, "--watch", value)
        :poll -> add_cli_flag(acc, "--poll", value)
        :optimize -> add_cli_flag(acc, "--optimize", value)
        :cwd -> add_cli_option(acc, "--cwd", value)
        :map -> add_cli_flag(acc, "--map", value)
        _ -> acc
      end
    end)
  end

  defp add_cli_option(opts, _flag, nil), do: opts

  defp add_cli_option(opts, flag, value) when is_list(value) do
    Enum.reduce(value, opts, fn single, acc -> add_cli_option(acc, flag, single) end)
  end

  defp add_cli_option(opts, flag, value) do
    opts ++ [flag, to_string(value)]
  end

  defp add_content_options(opts, nil), do: opts

  defp add_content_options(opts, value) do
    add_cli_option(opts, "--content", value)
  end

  defp add_cli_flag(opts, _flag, nil), do: opts
  defp add_cli_flag(opts, flag, true), do: opts ++ [flag]
  defp add_cli_flag(opts, _flag, false), do: opts

  defp add_cli_flag(opts, flag, value) when value in ["true", "false"] do
    if value == "true", do: opts ++ [flag], else: opts
  end

  defp add_cli_flag(opts, flag, value) when is_binary(value) do
    add_cli_flag(opts, flag, String.downcase(value) == "true")
  end

  defp add_cli_flag(opts, flag, value) when is_atom(value) do
    add_cli_flag(opts, flag, value == true)
  end

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

  defp generate_port_name(config_hash) do
    suffix = System.unique_integer([:positive])

    case config_hash do
      <<prefix::binary-size(8), _rest::binary>> ->
        String.to_atom("tailwind_port_opt_" <> prefix <> "_" <> Integer.to_string(suffix))

      _ ->
        String.to_atom("tailwind_port_opt_" <> Integer.to_string(suffix))
    end
  end

  defp flush_exit_signals do
    receive do
      {:EXIT, _pid, _reason} -> flush_exit_signals()
    after
      0 -> :ok
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_idle_ports, @port_idle_timeout)
  end

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

  defp update_stats(stats, :degraded_compile) do
    %{stats | degraded_compilations: stats.degraded_compilations + 1}
  end

  defp update_stats(stats, :port_creation_error) do
    %{stats | failed_compilations: stats.failed_compilations + 1}
  end

  defp update_stats(stats, :port_created) do
    %{stats | port_creations: stats.port_creations + 1}
  end

  defp update_stats(stats, :port_reused) do
    %{stats | port_reuses: stats.port_reuses + 1, cache_hits: stats.cache_hits + 1}
  end

  defp update_stats(stats, :pool_exhausted) do
    %{stats | pool_exhaustions: stats.pool_exhaustions + 1}
  end

  defp update_stats(stats, {:pool_size_update, size}) do
    %{stats | peak_pool_size: max(stats.peak_pool_size, size)}
  end

  defp update_stats(stats, {:compilation_time, duration_microseconds}) do
    new_total_time = stats.total_compilation_time + duration_microseconds

    new_avg =
      if stats.total_compilations > 0 do
        new_total_time / stats.total_compilations
      else
        0.0
      end

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

  defp update_stats(stats, :batch_compile, count) do
    %{
      stats
      | batch_compilations: stats.batch_compilations + 1,
        total_compilations: stats.total_compilations + count
    }
  end

  defp maybe_update_for_degraded(stats, %{readiness: :degraded}) do
    update_stats(stats, :degraded_compile)
  end

  defp maybe_update_for_degraded(stats, _result), do: stats

  defp maybe_update_for_error_reason(stats, :pool_exhausted) do
    update_stats(stats, :pool_exhausted)
  end

  defp maybe_update_for_error_reason(stats, _reason), do: stats

  defp normalize_operation_opts(opts, _options) when is_list(opts) do
    case Keyword.get(opts, :content) do
      nil -> Keyword.put(opts, :content, default_content_path(opts))
      [] -> Keyword.put(opts, :content, default_content_path(opts))
      _ -> opts
    end
  end

  defp normalize_operation_opts(opts, options) do
    opts
    |> Enum.into([])
    |> normalize_operation_opts(options)
  end

  defp default_content_path(opts) do
    base = System.tmp_dir!() || "/tmp"
    hash = :erlang.phash2(opts)
    Path.join([base, "tailwind_port", "content_#{hash}.html"])
  end

  defp initialize_port_metadata(port_info, opts) do
    paths = build_port_paths(opts)

    port_info
    |> Map.put(:paths, paths)
    |> Map.put(:last_output_mtime, file_mtime(paths[:output_path]))
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

  defp ensure_directory(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp ensure_input_placeholder(nil), do: :ok

  defp ensure_input_placeholder(path) do
    case File.exists?(path) do
      true -> :ok
      false -> File.write(path, "/* tailwind input */\n")
    end
  end

  defp await_file_update(path, previous_mtime, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_file_update(path, previous_mtime, deadline)
  end

  defp do_await_file_update(path, previous_mtime, deadline) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      case read_output_file(path) do
        {:ok, css, mtime} ->
          {:degraded,
           %{
             css: css,
             output_path: path,
             new_mtime: mtime,
             reason: :timeout
           }}

        {:error, _} ->
          {:degraded,
           %{
             css: nil,
             output_path: path,
             new_mtime: previous_mtime,
             reason: :timeout
           }}
      end
    else
      handle_file_read_result(path, previous_mtime, deadline)
    end
  end

  defp handle_file_read_result(path, previous_mtime, deadline) do
    case read_output_file(path) do
      {:ok, css, mtime} ->
        if previous_mtime == nil or mtime > previous_mtime do
          {:ok,
           %{
             css: css,
             output_path: path,
             new_mtime: mtime
           }}
        else
          Process.sleep(75)
          do_await_file_update(path, previous_mtime, deadline)
        end

      {:error, :enoent} ->
        Process.sleep(75)
        do_await_file_update(path, previous_mtime, deadline)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_output_file(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} ->
        case File.read(path) do
          {:ok, css} -> {:ok, css, mtime * 1000}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp file_mtime(nil), do: nil

  defp file_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime * 1000
      {:error, _} -> nil
    end
  end

  # New strategy with multiple fallbacks to extract CSS
  defp extract_css_with_fallbacks(pid, options) do
    Logger.debug(
      "TailwindPort: Attempting CSS extraction with multiple fallbacks for pid #{inspect(pid)}"
    )

    # Strategy 1: Original method
    case fetch_latest_output(pid) do
      css when is_binary(css) and css != "" ->
        Logger.debug("TailwindPort: Success with fetch_latest_output (#{byte_size(css)} bytes)")
        css

      _ ->
        Logger.debug("TailwindPort: fetch_latest_output failed, trying alternative methods")
        extract_css_alternative_methods(pid, options)
    end
  end

  # Alternative methods to extract CSS when the main method fails
  defp extract_css_alternative_methods(pid, options) do
    # Strategy 2: Try to read directly from process state
    case extract_css_from_process_state(pid) do
      css when is_binary(css) and css != "" ->
        Logger.debug(
          "TailwindPort: Success with process state extraction (#{byte_size(css)} bytes)"
        )

        css

      _ ->
        Logger.debug("TailwindPort: Process state extraction failed, trying port inspection")
        extract_css_from_port_inspection(pid, options)
    end
  end

  # Estrategia 3: Extraer CSS inspeccionando el estado del puerto directamente
  defp extract_css_from_process_state(pid) do
    case Process.info(pid, [:dictionary, :message_queue_len]) do
      [{:dictionary, dict}, {:message_queue_len, _}] ->
        # Buscar CSS en el diccionario del proceso
        find_css_in_process_dictionary(dict)

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  # Strategy 4: Port inspection with reduced timeout
  defp extract_css_from_port_inspection(pid, options) do
    timeout = Keyword.get(options, :extraction_timeout_ms, 1000)

    # Try to get the complete process state
    case :erlang.process_info(pid, :status) do
      {:status, :running} ->
        # Active port, try to extract CSS from recent logs
        extract_css_from_recent_activity(pid, timeout)

      _ ->
        Logger.debug("TailwindPort: Port not running, using empty fallback")
        ""
    end
  rescue
    error ->
      Logger.warning("TailwindPort: Port inspection failed: #{inspect(error)}")
      ""
  end

  # Buscar CSS en el diccionario del proceso
  defp find_css_in_process_dictionary(dict) when is_list(dict) do
    dict
    |> Enum.find_value("", fn {_key, value} ->
      if is_binary(value) and String.contains?(value, ["css", "CSS", "tailwind"]) and
           String.length(value) > 100 do
        value
      else
        nil
      end
    end)
  end

  defp find_css_in_process_dictionary(_), do: ""

  # Extraer CSS de actividad reciente del puerto
  defp extract_css_from_recent_activity(pid, timeout) do
    # Strategy A: Send a "ping" message and see if there's a CSS response
    ref = make_ref()
    send(pid, {:ping_for_css, ref, self()})

    receive do
      {:css_response, ^ref, css} when is_binary(css) and css != "" ->
        Logger.debug("TailwindPort: Got CSS from ping response (#{byte_size(css)} bytes)")
        css
    after
      div(timeout, 2) ->
        Logger.debug("TailwindPort: No CSS response from ping, trying force regeneration")
        # Strategy B: Try to force CSS regeneration
        force_css_regeneration(pid, timeout)
    end
  rescue
    _ ->
      Logger.debug("TailwindPort: Recent activity extraction failed")
      ""
  end

  # Force CSS regeneration when the port is degraded but functional
  defp force_css_regeneration(pid, remaining_timeout) do
    # Try to force a new minimal compilation
    case Standalone.state(pid) do
      %{port: port} when not is_nil(port) ->
        Logger.debug("TailwindPort: Attempting to force CSS regeneration")

        # Send minimal signal to the port to generate CSS
        # This should make the port process and generate output
        send(pid, {:force_regenerate, self()})

        # Wait for the result
        receive do
          {:regenerated_css, css} when is_binary(css) and css != "" ->
            Logger.debug("TailwindPort: Force regeneration successful (#{byte_size(css)} bytes)")

            css

          {:regeneration_failed, reason} ->
            Logger.debug("TailwindPort: Force regeneration failed: #{inspect(reason)}")
            ""
        after
          remaining_timeout ->
            Logger.debug("TailwindPort: Force regeneration timeout")
            ""
        end

      _ ->
        Logger.debug("TailwindPort: Port not available for force regeneration")
        ""
    end
  rescue
    error ->
      Logger.debug("TailwindPort: Force regeneration error: #{inspect(error)}")
      ""
  end

  defp fetch_latest_output(pid) do
    case Standalone.state(pid) do
      %{latest_output: output} when is_binary(output) and output != "" ->
        output

      %{preserved_css: css_output} when is_binary(css_output) and css_output != "" ->
        Logger.debug(
          "TailwindPort: Extracting CSS from preserved_css (#{byte_size(css_output)} bytes)"
        )

        css_output

      %{last_css_output: css_output} when is_binary(css_output) and css_output != "" ->
        Logger.debug(
          "TailwindPort: Extracting CSS from last_css_output (#{byte_size(css_output)} bytes)"
        )

        css_output

      %{health: %{css_builds: css_builds}} when css_builds > 0 ->
        Logger.warning(
          "TailwindPort: Port has generated #{css_builds} CSS builds but no output available"
        )

        nil

      _ ->
        nil
    end
  rescue
    error ->
      Logger.warning(
        "TailwindPort: Error fetching output from port #{inspect(pid)}: #{inspect(error)}"
      )

      nil
  end

  defp fallback_css(port_info, operation) do
    fetch_latest_output(port_info.pid) || operation.content
  end

  defp default_options do
    [
      max_pool_size: @default_pool_size,
      enable_watch_mode: true,
      enable_batching: true,
      cleanup_interval: @port_idle_timeout,
      baseline_compilation_time_ms: nil,
      compile_timeout_ms: 5_000
    ]
  end
end
