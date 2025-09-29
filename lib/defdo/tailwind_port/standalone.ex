defmodule Defdo.TailwindPort.Standalone do
  @moduledoc """
  Legacy single-port interface for the Tailwind CSS CLI.

  `Defdo.TailwindPort.Standalone` exposes the original GenServer-based workflow that
  interacts with the Tailwind CLI through Elixir ports. Use this module when you need
  full control over a single Tailwind process. For pooled, metric-rich operation,
  prefer `Defdo.TailwindPort`.

  ## Features

  - **Production-Ready Reliability**: Comprehensive error handling with proper return types
  - **Port Synchronization**: Reliable port startup with `ready?/2` and `wait_until_ready/2`
  - **Health Monitoring**: Real-time process metrics and telemetry
  - **Security**: Binary verification and input validation
  - **Retry Logic**: Automatic retry with exponential backoff
  - **Process Cleanup**: Graceful handling of orphaned processes

  ## Quick Start

  ### Basic Usage

      # Start a TailwindPort process
      {:ok, pid} = Defdo.TailwindPort.start_link([
        opts: ["-i", "./assets/css/app.css",
               "--content", "./lib/**/*.{ex,heex}",
               "-o", "./priv/static/css/app.css"]
      ])

      # Wait for the port to be ready (recommended over Process.sleep)
      :ok = Defdo.TailwindPort.wait_until_ready()

  ### Watch Mode for Development

      # Start with watch mode for automatic rebuilds
      {:ok, pid} = Defdo.TailwindPort.start_link([
        name: :dev_tailwind,
        opts: ["-i", "./assets/css/app.css",
               "--content", "./lib/**/*.{ex,heex}",
               "-o", "./priv/static/css/app.css",
               "--watch"]
      ])

      # Check if ready
      if Defdo.TailwindPort.ready?(:dev_tailwind) do
        IO.puts("Tailwind is watching for changes!")
      end

  ### Production Build

      # One-time build with minification
      {:ok, pid} = Defdo.TailwindPort.start_link([
        opts: ["-i", "./assets/css/app.css",
               "--content", "./lib/**/*.{ex,heex}",
               "-o", "./priv/static/css/app.css",
               "--minify"]
      ])

      # Wait for build completion
      :ok = Defdo.TailwindPort.wait_until_ready()

      # Build is complete when port becomes ready

  ## Configuration Options

  ### Start Options
    * `:name` - Name for the GenServer process (default: `__MODULE__`)
    * `:cmd` - Path to specific Tailwind binary (default: auto-downloaded)
    * `:opts` - List of CLI arguments passed to Tailwind

  ### CLI Options
    * `-i`, `--input` - Input CSS file path
    * `-o`, `--output` - Output CSS file path
    * `-w`, `--watch` - Watch for changes and rebuild automatically
    * `-p`, `--poll` - Use polling instead of filesystem events
    * `--content` - Content paths for unused class removal
    * `--postcss` - Load custom PostCSS configuration
    * `-m`, `--minify` - Minify the output CSS
    * `-c`, `--config` - Path to Tailwind config file
    * `--no-autoprefixer` - Disable autoprefixer

  ## Error Handling

  All functions return proper `{:ok, result}` or `{:error, reason}` tuples:

      case Defdo.TailwindPort.new(:my_port, opts: ["-i", "input.css"]) do
        {:ok, state} ->
          IO.puts("Port created successfully!")
        {:error, :max_retries_exceeded} ->
          IO.puts("Failed to create port after retries")
        {:error, reason} ->
          IO.puts("Error: \#{inspect(reason)}")
      end

  ## Health Monitoring

      # Get comprehensive health metrics
      health = Defdo.TailwindPort.health()
      # %{
      #   uptime_seconds: 120.5,
      #   port_ready: true,
      #   total_outputs: 15,
      #   css_builds: 3,
      #   errors: 0,
      #   last_activity_seconds_ago: 2.1
      # }

  ## Telemetry Events

  The module emits several telemetry events for monitoring:

  - `[:tailwind_port, :css, :done]` - CSS compilation completed
  - `[:tailwind_port, :other, :done]` - Other port output received
  - `[:tailwind_port, :port, :exit]` - Port process exited

  ## Best Practices

  1. **Use synchronization**: Always use `wait_until_ready/2` instead of `Process.sleep/1`
  2. **Handle errors**: Wrap calls in proper error handling
  3. **Monitor health**: Use `health/1` for observability in production
  4. **Named processes**: Use named processes for better debugging
  5. **Proper cleanup**: Processes clean up automatically, but call `terminate/1` for explicit shutdown

  """
  use GenServer, restart: :transient
  require Logger

  alias Defdo.TailwindPort.FS
  alias Defdo.TailwindPort.Health
  alias Defdo.TailwindPort.PortManager
  alias Defdo.TailwindPort.ProcessManager
  alias Defdo.TailwindPort.Retry
  alias Defdo.TailwindPort.Telemetry
  alias Defdo.TailwindPort.Validation

  # GenServer API
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(args \\ []) do
    with :ok <- Validation.validate_start_args(args) do
      {name, args} = Keyword.pop(args, :name, __MODULE__)
      GenServer.start_link(__MODULE__, args, name: name)
    end
  end

  @spec init(args :: keyword()) :: {:ok, map()} | {:ok, map(), {:continue, tuple()}}

  def init([]) do
    Process.flag(:trap_exit, true)

    state =
      %{
        port: nil,
        latest_output: nil,
        last_css_output: nil,
        preserved_css: nil,
        exit_status: nil,
        fs: FS.random_fs(),
        retry_count: 0,
        port_ready: false,
        port_monitor_ref: nil,
        health: Health.create_initial_health(),
        css_listeners: []
      }
      |> ProcessManager.initialize_state()

    {:ok, state}
  end

  def init(args) do
    Process.flag(:trap_exit, true)

    state =
      %{
        port: nil,
        latest_output: nil,
        last_css_output: nil,
        preserved_css: nil,
        exit_status: nil,
        fs: FS.random_fs(),
        retry_count: 0,
        port_ready: false,
        port_monitor_ref: nil,
        health: Health.create_initial_health(),
        css_listeners: []
      }
      |> ProcessManager.initialize_state()

    {:ok, state, {:continue, {:new, args}}}
  end

  @doc """
  Creates a new `TailwindPort` process with the given configuration.

  This function initializes a new Tailwind CSS build process with the specified
  options. It includes automatic retry logic and comprehensive error handling.

  ## Parameters

    * `name` - GenServer name (default: `__MODULE__`)
    * `args` - Keyword list of configuration options

  ## Options

    * `:cmd` - Path to specific Tailwind binary (default: auto-downloaded)
    * `:opts` - List of CLI arguments passed to Tailwind CSS
    * `:timeout` - Timeout for the operation in milliseconds (default: 5000 or 60000 for downloads)

  ## Returns

    * `{:ok, state}` - Process created successfully with current state
    * `{:error, reason}` - Creation failed with specific error reason

  ## Examples

      # Basic CSS build
      {:ok, state} = TailwindPort.new(:my_build, [
        opts: ["-i", "./input.css", "-o", "./output.css"]
      ])

      # Watch mode for development
      {:ok, state} = TailwindPort.new(:dev_watcher, [
        opts: ["-i", "./src/styles.css", "-o", "./dist/styles.css", "--watch"]
      ])

      # Custom binary with specific config
      {:ok, state} = TailwindPort.new(:custom_build, [
        cmd: "/usr/local/bin/tailwindcss",
        opts: ["-c", "./tailwind.config.js", "--minify"]
      ])

      # Error handling
      case TailwindPort.new(:failing_build, [cmd: "/invalid/path"]) do
        {:ok, result} -> IO.puts("Success: \#{inspect(result)}")
        {:error, :max_retries_exceeded} -> IO.puts("Failed after retries")
        {:error, reason} -> IO.puts("Error: \#{inspect(reason)}")
      end

  ## Error Reasons

    * `:invalid_cmd` - Invalid command path provided
    * `:invalid_opts` - Invalid options format
    * `:max_retries_exceeded` - Process creation failed after all retries
    * `:timeout` - Operation timed out
    * `{:download_failed, reason}` - Binary download failed
    * `{:port_creation_failed, reason}` - Port creation failed

  """
  @spec new(GenServer.name(), keyword()) :: {:ok, map()} | {:error, term()}
  def new(name \\ __MODULE__, args) do
    with :ok <- Validation.validate_port_args(args) do
      unless Keyword.has_key?(args, :opts) do
        Logger.warning(
          "Keyword `opts` must contain the arguments required by tailwind_port to work as you expect, but it is not provided."
        )
      end

      # sometime we should download the tailwind binary in that case we will increase the timeout.
      timeout = if Keyword.has_key?(args, :cmd), do: 5000, else: 60_000

      try do
        case GenServer.call(name, {:new, args}, timeout) do
          {:error, _} = error -> error
          result -> {:ok, result}
        end
      catch
        :exit, {:timeout, _} -> {:error, :timeout}
        :exit, reason -> {:error, {:exit, reason}}
      end
    end
  end

  defp new_port(args) do
    PortManager.create_port(args)
  end

  @doc """
  Initialize a directory structure into the filesystem
  """
  @spec init_fs(GenServer.name()) :: FS.t()
  def init_fs(name \\ __MODULE__) do
    GenServer.call(name, :init_fs)
  end

  @doc """
  Updates the FS struct into the state
  """
  @spec update_fs(GenServer.name(), keyword()) :: FS.t()
  def update_fs(name \\ __MODULE__, opts) do
    GenServer.call(name, {:update_fs, opts})
  end

  @doc """
  Similar to `update_fs/2` but automatically initialize the filesystem directory.
  """
  @spec update_and_init_fs(GenServer.name(), keyword()) :: FS.t()
  def update_and_init_fs(name \\ __MODULE__, opts) do
    GenServer.call(name, {:update_and_init_fs, opts})
  end

  @doc """
  Get the current state for the running process.
  """
  @spec state(GenServer.name()) :: map()
  def state(name \\ __MODULE__) do
    GenServer.call(name, :get_state)
  end

  @doc """
  Check if the Tailwind port is ready and operational.

  This function provides a quick, non-blocking way to check if the Tailwind CSS
  process is ready to handle builds. It's useful for health checks and ensuring
  the process is in a good state before proceeding.

  ## Parameters

    * `name` - GenServer name (default: `__MODULE__`)
    * `timeout` - Timeout in milliseconds (default: 5000)

  ## Returns

    * `true` - Port is ready and operational
    * `false` - Port is not ready, starting up, or has failed

  ## Examples

      # Quick readiness check
      if TailwindPort.ready?() do
        IO.puts("Tailwind is ready for builds!")
      else
        IO.puts("Tailwind is still starting up...")
      end

      # Check specific named process
      case TailwindPort.ready?(:my_tailwind, 1000) do
        true -> proceed_with_build()
        false -> wait_or_restart()
      end

      # Use in conditional logic
      ready_processes = [:dev, :prod, :test]
      |> Enum.filter(&TailwindPort.ready?/1)
      |> length()

      IO.puts("\#{ready_processes} processes ready")

  ## Notes

  - This function uses a short timeout and catches exceptions
  - Returns `false` for any error condition (timeout, process down, etc.)
  - Safe to call frequently for health monitoring
  - Does not block the calling process

  """
  @spec ready?(GenServer.name(), timeout()) :: boolean()
  def ready?(name \\ __MODULE__, timeout \\ 5000) do
    GenServer.call(name, :port_ready?, timeout)
  catch
    :exit, {:timeout, _} -> false
    :exit, _ -> false
  end

  @doc """
  Wait for the Tailwind port to become ready.

  This function blocks until the Tailwind CSS process is fully initialized and
  ready to handle builds. It's the recommended way to synchronize with port
  startup instead of using `Process.sleep/1`.

  ## Parameters

    * `name` - GenServer name (default: `__MODULE__`)
    * `timeout` - Maximum wait time in milliseconds (default: 10000)

  ## Returns

    * `:ok` - Port is ready
    * `{:error, :timeout}` - Timed out waiting for readiness

  ## Examples

      # Basic synchronization
      {:ok, _pid} = TailwindPort.start_link(opts: ["-w"])
      :ok = TailwindPort.wait_until_ready()
      IO.puts("Tailwind is now ready!")

      # With custom timeout
      case TailwindPort.wait_until_ready(TailwindPort, 30_000) do
        :ok ->
          IO.puts("Ready after waiting")
        {:error, :timeout} ->
          IO.puts("Timed out waiting for readiness")
      end

      # Named process with error handling
      {:ok, _pid} = TailwindPort.start_link(name: :my_build, opts: opts)

      case TailwindPort.wait_until_ready(:my_build, 15_000) do
        :ok ->
          # Proceed with operations that require ready port
          trigger_css_build()
        {:error, :timeout} ->
          # Handle timeout - maybe restart or log error
          Logger.error("Tailwind port failed to become ready")
          TailwindPort.terminate(:my_build)
      end

      # Pipeline usage
      :my_tailwind
      |> TailwindPort.start_link(opts: opts)
      |> case do
        {:ok, _pid} -> TailwindPort.wait_until_ready(:my_tailwind)
        error -> error
      end
      |> case do
        :ok -> run_build_pipeline()
        error -> handle_error(error)
      end

  ## Notes

  - Replaces unreliable `Process.sleep/1` patterns
  - Blocks the calling process until ready or timeout
  - Safe to call multiple times (returns immediately if already ready)
  - Integrates with the port's internal readiness detection

  """
  @spec wait_until_ready(GenServer.name(), timeout()) :: :ok | {:error, :timeout}
  def wait_until_ready(name \\ __MODULE__, timeout \\ 10_000) do
    GenServer.call(name, :wait_until_ready, timeout)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  @doc """
  Get comprehensive health metrics for the Tailwind port process.

  This function returns detailed health and performance metrics for monitoring
  and debugging purposes. It's useful for observability in production systems.

  ## Parameters

    * `name` - GenServer name (default: `__MODULE__`)

  ## Returns

  A map containing health metrics:

    * `:uptime_seconds` - How long the process has been running
    * `:port_ready` - Whether the port is ready for operations
    * `:port_active` - Whether the underlying port is still active
    * `:total_outputs` - Total number of outputs received from Tailwind
    * `:css_builds` - Number of CSS compilation events
    * `:errors` - Number of errors encountered
    * `:last_activity` - Timestamp of last activity (system time)
    * `:last_activity_seconds_ago` - Seconds since last activity
    * `:created_at` - Process creation timestamp

  ## Examples

      # Basic health check
      health = TailwindPort.health()
      IO.inspect(health)
      # %{
      #   uptime_seconds: 120.5,
      #   port_ready: true,
      #   port_active: true,
      #   total_outputs: 15,
      #   css_builds: 3,
      #   errors: 0,
      #   last_activity_seconds_ago: 2.1,
      #   created_at: 1706364000000000000,
      #   last_activity: 1706364120000000000
      # }

      # Health monitoring for multiple processes
      processes = [:dev, :prod, :test]
      health_report = processes
      |> Enum.map(fn name ->
        {name, TailwindPort.health(name)}
      end)
      |> Enum.into(%{})

      # Check for unhealthy processes
      unhealthy = health_report
      |> Enum.filter(fn {_name, health} ->
        not health.port_ready or health.errors > 0
      end)

      # Performance monitoring
      health = TailwindPort.health(:my_build)
      if health.last_activity_seconds_ago > 300 do
        Logger.warning("Tailwind process inactive for 5+ minutes")
      end

      # Build rate calculation
      build_rate = health.css_builds / health.uptime_seconds
      IO.puts("Average build rate: \#{Float.round(build_rate, 2)} builds/second")

      # Error rate monitoring
      error_rate = health.errors / health.total_outputs
      if error_rate > 0.1 do
        Logger.error("High error rate detected: \#{Float.round(error_rate * 100, 1)}%")
      end

  ## Use Cases

  - **Production Monitoring**: Regular health checks in production
  - **Debugging**: Understanding process behavior and performance
  - **Alerting**: Setting up alerts based on health metrics
  - **Performance Analysis**: Analyzing build patterns and efficiency
  - **Load Balancing**: Distributing work based on process health

  """
  @spec health(GenServer.name()) :: map()
  def health(name \\ __MODULE__) do
    GenServer.call(name, :get_health)
  end

  @doc """
  Complete the execution for running process.
  """
  @spec terminate(GenServer.name()) :: :ok
  def terminate(name \\ __MODULE__) do
    GenServer.stop(name)
  end

  ####
  # This is a GenServer callback triggered when Process is flag as :trap_exit
  # by default it is not added, but we want to close the port to prevent Orphaned OS process
  # we wrap with binary via tailwind_cli.sh which kills watch the stdin to gracefully
  # terminate the OS process.
  ####
  # Note the tailwind_cli.sh above hijacks stdin, so you won't be able to communicate with
  # the underlying software via stdin
  # (on the positive side, software that reads from stdin typically terminates when stdin closes).
  def terminate(reason, %{port: port}) do
    if Port.info(port) do
      Port.close(port)

      port
      |> Port.info()
      |> warn_if_orphaned()
    else
      Logger.debug("Port: #{inspect(port)} doesn't exist.")
    end

    {:shutdown, reason}
  end

  def handle_continue({:new, [opts: []]}, state) do
    {:noreply, state}
  end

  def handle_continue({:new, args}, state) do
    case Retry.with_backoff(fn -> new_port(args) end) do
      {:ok, port} ->
        new_state =
          %{
            state
            | port: port,
              retry_count: 0,
              port_ready: false
          }
          |> ProcessManager.setup_startup_timeout(10_000)

        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to create port during initialization: #{inspect(reason)}")
        {:stop, {:port_creation_failed, reason}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:port_ready?, _from, state) do
    {:reply, state.port_ready, state}
  end

  def handle_call(:get_health, _from, state) do
    health_info = Health.calculate_health_info(state)
    {:reply, health_info, state}
  end

  def handle_call(:wait_until_ready, _from, %{port_ready: true} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:wait_until_ready, from, %{port_ready: false} = state) do
    # Store the caller to reply when port becomes ready
    new_state = ProcessManager.add_waiting_caller(state, from)
    {:noreply, new_state}
  end

  def handle_call(:init_fs, _from, state) do
    new_fs = FS.init_path(state.fs)
    new_state = %{state | fs: new_fs}

    {:reply, new_state.fs, new_state}
  end

  def handle_call({:update_fs, opts}, _from, state) do
    updated_fs = FS.update(state.fs, opts)
    new_state = %{state | fs: updated_fs}

    {:reply, new_state.fs, new_state}
  end

  def handle_call({:update_and_init_fs, opts}, _from, state) do
    updated_fs = FS.update(state.fs, opts)
    new_state = %{state | fs: FS.init_path(updated_fs)}

    {:reply, new_state.fs, new_state}
  end

  def handle_call({:new, args}, _from, state) do
    case Retry.with_backoff(fn -> new_port(args) end) do
      {:ok, port} ->
        new_state =
          %{
            state
            | port: port,
              retry_count: 0,
              port_ready: false
          }
          |> ProcessManager.cancel_startup_timeout()
          |> ProcessManager.setup_startup_timeout(10_000)

        {:reply, {:ok, new_state}, new_state}

      {:error, reason} ->
        Logger.error("Failed to create port after retries: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  # This callback handles data incoming from the command's STDOUT
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Update health metrics
    updated_health = Health.update_metrics(state.health, data)
    updated_state = %{state | health: updated_health}

    # Mark port as ready on first successful output
    new_state = Health.maybe_mark_port_ready(updated_state, data)

    if String.contains?(data, "{") or String.contains?(data, "}") do
      Logger.debug(["CSS:", "#{inspect(data)}"])

      Telemetry.increment_counter(:css_builds, %{port: inspect(port)})

      :telemetry.execute(
        [:tailwind_port, :css, :done],
        %{css_builds: new_state.health.css_builds},
        %{port: port, data: data}
      )

      css_output = String.trim(data)

      # Store CSS immediately in multiple places to prevent loss
      persistent_state = %{
        new_state
        | latest_output: css_output,
          last_css_output: css_output,
          preserved_css: css_output
      }

      # Store in process dictionary for alternative extraction
      Process.put(:tailwind_css_output, css_output)
      Process.put(:css_generation_timestamp, System.monotonic_time(:millisecond))

      # Immediately notify all registered CSS listeners
      notify_css_listeners(persistent_state.css_listeners, css_output)

      {:noreply, persistent_state}
    else
      :telemetry.execute(
        [:tailwind_port, :other, :done],
        %{total_outputs: new_state.health.total_outputs},
        %{port: port, data: data}
      )

      {:noreply, new_state}
    end
  end

  # This callback tells us when the process exits
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("Port exit: :exit_status: #{status}")

    # Update health metrics for exit
    health =
      if status != 0 do
        Telemetry.track_error(:port_exit, {:exit_status, status}, %{port: inspect(port)})
        Health.increment_errors(state.health)
      else
        state.health
      end

    new_state = %{state | exit_status: status, health: health}

    :telemetry.execute(
      [:tailwind_port, :port, :exit],
      %{exit_status: status},
      %{port: port}
    )

    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :port, port, reason}, state) do
    new_state = ProcessManager.handle_port_down(state, port, reason)
    {:noreply, new_state}
  end

  def handle_info({:EXIT, port, reason}, state) do
    new_state = ProcessManager.handle_port_exit(state, port, reason)
    {:noreply, new_state}
  end

  def handle_info(:startup_timeout, state) do
    new_state = ProcessManager.handle_startup_timeout(state)
    {:noreply, new_state}
  end

  def handle_info({:ping_for_css, ref, from}, state) do
    # Try multiple CSS sources
    css =
      state.preserved_css ||
        state.last_css_output ||
        state.latest_output ||
        Process.get(:tailwind_css_output) ||
        ""

    send(from, {:css_response, ref, css})
    {:noreply, state}
  end

  def handle_info({:force_regenerate, from}, state) do
    # Intentar forzar regeneración de CSS
    case state do
      %{preserved_css: css} when is_binary(css) and css != "" ->
        send(from, {:regenerated_css, css})
        {:noreply, state}

      %{port: port, last_css_output: css}
      when not is_nil(port) and is_binary(css) and css != "" ->
        send(from, {:regenerated_css, css})
        {:noreply, state}

      %{port: port, latest_output: css} when not is_nil(port) and is_binary(css) and css != "" ->
        send(from, {:regenerated_css, css})
        {:noreply, state}

      %{port: port} when not is_nil(port) ->
        try do
          Port.command(port, "\n")
          send(from, {:regeneration_failed, :no_css_available})
        rescue
          error ->
            send(from, {:regeneration_failed, {:port_error, error}})
        end

        {:noreply, state}

      _ ->
        # No hay puerto disponible
        send(from, {:regeneration_failed, :no_port})
        {:noreply, state}
    end
  end

  # Handle registration of CSS listeners from Pool
  def handle_info({:register_css_listener, listener_pid, capture_ref, operation_id}, state) do
    Logger.debug(
      "Standalone: Registering CSS listener #{inspect(listener_pid)} for operation #{inspect(operation_id)}"
    )

    listener = %{
      pid: listener_pid,
      ref: capture_ref,
      operation_id: operation_id,
      registered_at: System.monotonic_time(:millisecond)
    }

    new_listeners = [listener | state.css_listeners]
    new_state = %{state | css_listeners: new_listeners}

    {:noreply, new_state}
  end

  # Handle CSS generation trigger from Pool
  def handle_info({:trigger_css_generation, from}, state) do
    Logger.debug("Standalone: CSS generation trigger received from #{inspect(from)}")

    # If we already have CSS available, send it immediately
    case get_available_css(state) do
      css when is_binary(css) and css != "" ->
        Logger.debug("Standalone: Sending existing CSS immediately (#{byte_size(css)} bytes)")
        notify_css_listeners(state.css_listeners, css)
        {:noreply, state}

      _ ->
        Logger.debug("Standalone: No existing CSS, will notify when generated")
        # CSS will be sent when generated in handle_info({port, {:data, data}})
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.info("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Notify all registered CSS listeners with the generated CSS
  defp notify_css_listeners([], _css), do: :ok

  defp notify_css_listeners(listeners, css) when is_binary(css) and css != "" do
    Logger.debug(
      "Standalone: Notifying #{length(listeners)} CSS listeners with #{byte_size(css)} bytes"
    )

    Enum.each(listeners, fn listener ->
      try do
        send(listener.pid, {:css_generated, listener.ref, css})

        Logger.debug(
          "Standalone: CSS sent to listener #{inspect(listener.pid)} for operation #{inspect(listener.operation_id)}"
        )
      rescue
        error ->
          Logger.warning(
            "Standalone: Failed to notify CSS listener #{inspect(listener.pid)}: #{inspect(error)}"
          )
      end
    end)
  end

  defp notify_css_listeners(listeners, _invalid_css) do
    Logger.warning("Standalone: Invalid CSS for #{length(listeners)} listeners")

    Enum.each(listeners, fn listener ->
      try do
        send(listener.pid, {:css_generation_failed, listener.ref, :invalid_css})
      rescue
        error ->
          Logger.warning(
            "Standalone: Failed to notify CSS failure to listener #{inspect(listener.pid)}: #{inspect(error)}"
          )
      end
    end)
  end

  # Get available CSS from any source in order of preference
  defp get_available_css(state) do
    cond do
      is_binary(state.preserved_css) and state.preserved_css != "" ->
        state.preserved_css

      is_binary(state.last_css_output) and state.last_css_output != "" ->
        state.last_css_output

      is_binary(state.latest_output) and state.latest_output != "" ->
        state.latest_output

      true ->
        # Try process dictionary as last resort
        Process.get(:tailwind_css_output) || ""
    end
  end

  defp warn_if_orphaned(port_info) do
    if os_pid = port_info[:os_pid] do
      Logger.warning("Orphaned OS process: #{os_pid}")

      # Attempt to kill the orphaned process
      case System.cmd("kill", ["-TERM", "#{os_pid}"], stderr_to_stdout: true) do
        {_, 0} ->
          Logger.info("Successfully terminated orphaned process #{os_pid}")

        {output, _} ->
          Logger.warning("Failed to terminate orphaned process #{os_pid}: #{output}")
      end
    end
  end
end
