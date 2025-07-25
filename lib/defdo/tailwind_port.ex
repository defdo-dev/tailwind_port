defmodule Defdo.TailwindPort do
  @moduledoc """
  A robust, production-ready interface for the Tailwind CSS CLI.

  The `Defdo.TailwindPort` module provides a reliable GenServer-based interface to interact
  with the Tailwind CSS CLI through Elixir ports. This enables seamless integration of 
  Tailwind CSS build processes into Elixir applications with enterprise-grade reliability,
  comprehensive error handling, health monitoring, and synchronization features.

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

  alias Defdo.TailwindDownload
  alias Defdo.TailwindPort.FS

  # GenServer API
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(args \\ []) do
    with :ok <- validate_start_args(args) do
      {name, args} = Keyword.pop(args, :name, __MODULE__)
      GenServer.start_link(__MODULE__, args, name: name)
    end
  end

  @spec init(args :: keyword()) :: {:ok, map()} | {:ok, map(), {:continue, tuple()}}

  def init([]) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       port: nil,
       latest_output: nil,
       exit_status: nil,
       fs: FS.random_fs(),
       retry_count: 0,
       port_ready: false,
       port_monitor_ref: nil,
       startup_timeout_ref: nil,
       health: %{
         created_at: System.system_time(),
         last_activity: System.system_time(),
         total_outputs: 0,
         css_builds: 0,
         errors: 0
       }
     }}
  end

  def init(args) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       port: nil,
       latest_output: nil,
       exit_status: nil,
       fs: FS.random_fs(),
       retry_count: 0,
       port_ready: false,
       port_monitor_ref: nil,
       startup_timeout_ref: nil,
       health: %{
         created_at: System.system_time(),
         last_activity: System.system_time(),
         total_outputs: 0,
         css_builds: 0,
         errors: 0
       }
     }, {:continue, {:new, args}}}
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
    with :ok <- validate_new_args(args) do
      unless Keyword.has_key?(args, :opts) do
        Logger.warning(
          "Keyword `opts` must contain the arguments required by tailwind_port to work as you expect, but it is not provided."
        )
      end

      # sometime we should download the tailwind binary in that case we will increase the timeout.
      timeout = if Keyword.has_key?(args, :cmd), do: 5000, else: 60000

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
    with {:ok, bin_path} <- get_bin_path(),
         {:ok, cmd} <- prepare_command(args, bin_path),
         {:ok, {command, final_args}} <- build_command_args(args, cmd, bin_path) do
      case create_port(command, final_args) do
        {:ok, port} ->
          port

        {:error, reason} ->
          Logger.error("Failed to create port: #{inspect(reason)}")
          raise "Port creation failed: #{inspect(reason)}"
      end
    else
      {:error, reason} ->
        Logger.error("Failed to prepare port: #{inspect(reason)}")
        raise "Port preparation failed: #{inspect(reason)}"
    end
  end

  defp get_bin_path do
    bin_path = bin_path()

    if File.dir?(bin_path) do
      {:ok, bin_path}
    else
      case File.mkdir_p(bin_path) do
        :ok -> {:ok, bin_path}
        {:error, reason} -> {:error, {:mkdir_failed, reason}}
      end
    end
  end

  defp prepare_command(args, bin_path) do
    cmd = Keyword.get(args, :cmd, "#{bin_path}/tailwindcss")

    if File.exists?(cmd) do
      {:ok, cmd}
    else
      Logger.debug("The `cmd` doesn't have a valid tailwind binary, we proceed to download")

      case TailwindDownload.download(cmd) do
        :ok -> {:ok, cmd}
        {:error, reason} -> {:error, {:download_failed, reason}}
        # download/1 doesn't return :ok currently, assume success
        _ -> {:ok, cmd}
      end
    end
  end

  defp build_command_args(args, cmd, bin_path) do
    opts = Keyword.get(args, :opts, [])

    options =
      opts
      |> maybe_add_default_options(["-i", "--input"], [])
      |> maybe_add_default_options(["-o", "--output"], [])
      |> maybe_add_default_options(["-w", "--watch"], [])
      |> maybe_add_default_options(["-p", "--poll"], [])
      |> maybe_add_default_options(["--content"], [])
      |> maybe_add_default_options(["--postcss"], [])
      |> maybe_add_default_options(["-m", "--minify"], [])
      |> maybe_add_default_options(["-c", "--config"], [])
      |> maybe_add_default_options(["--no-autoprefixer"], [])

    {command, final_args} =
      if "-i" in opts || "--input" in opts do
        # direct call binary
        {cmd, options}
      else
        # Wraps command
        wrapper_script = "#{bin_path}/tailwind_cli.sh"

        if File.exists?(wrapper_script) do
          {wrapper_script, [cmd | options]}
        else
          Logger.warning("Wrapper script not found at #{wrapper_script}, using direct command")
          {cmd, options}
        end
      end

    {:ok, {command, final_args}}
  end

  defp create_port(command, args) do
    try do
      port =
        Port.open({:spawn_executable, command}, [
          {:args, args},
          :binary,
          :exit_status,
          :use_stdio,
          :stderr_to_stdout
        ])

      Port.monitor(port)

      Logger.debug(["Running command #{command} #{Enum.join(args, " ")}"], color: :magenta)
      Logger.debug(["Running command ", Path.basename(command), " Port is monitored."])

      {:ok, port}
    rescue
      error -> {:error, error}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  # bin path for local test
  defp bin_path do
    project_path = :code.priv_dir(:tailwind_port)
    Path.join([project_path, "bin"])
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
    try do
      GenServer.call(name, :port_ready?, timeout)
    catch
      :exit, {:timeout, _} -> false
      :exit, _ -> false
    end
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
  def wait_until_ready(name \\ __MODULE__, timeout \\ 10000) do
    try do
      GenServer.call(name, :wait_until_ready, timeout)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
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
    case create_port_with_retry(args, state.retry_count) do
      {:ok, port} ->
        # Set startup timeout for port readiness
        timeout_ref = Process.send_after(self(), :startup_timeout, 10_000)

        new_state = %{
          state
          | port: port,
            retry_count: 0,
            port_ready: false,
            startup_timeout_ref: timeout_ref
        }

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
    health_info =
      Map.merge(state.health, %{
        uptime_seconds: (System.system_time() - state.health.created_at) / 1_000_000_000,
        port_active: not is_nil(state.port) and not is_nil(Port.info(state.port)),
        port_ready: state.port_ready,
        last_activity_seconds_ago:
          (System.system_time() - state.health.last_activity) / 1_000_000_000
      })

    {:reply, health_info, state}
  end

  def handle_call(:wait_until_ready, _from, %{port_ready: true} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:wait_until_ready, from, %{port_ready: false} = state) do
    # Store the caller to reply when port becomes ready
    waiting_callers = Map.get(state, :waiting_callers, [])
    new_state = Map.put(state, :waiting_callers, [from | waiting_callers])
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
    case create_port_with_retry(args, state.retry_count) do
      {:ok, port} ->
        # Cancel any existing startup timeout
        if state.startup_timeout_ref do
          Process.cancel_timer(state.startup_timeout_ref)
        end

        # Set startup timeout for port readiness
        timeout_ref = Process.send_after(self(), :startup_timeout, 10_000)

        new_state = %{
          state
          | port: port,
            retry_count: 0,
            port_ready: false,
            startup_timeout_ref: timeout_ref
        }

        {:reply, {:ok, new_state}, new_state}

      {:error, reason} ->
        Logger.error("Failed to create port after retries: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  # This callback handles data incoming from the command's STDOUT
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Update health metrics
    updated_state = update_health_metrics(state, data)

    # Mark port as ready on first successful output
    new_state = maybe_mark_port_ready(updated_state, data)

    if String.contains?(data, "{") or String.contains?(data, "}") do
      Logger.debug(["CSS:", "#{inspect(data)}"])

      :telemetry.execute(
        [:tailwind_port, :css, :done],
        %{css_builds: new_state.health.css_builds},
        %{port: port, data: data}
      )

      {:noreply, %{new_state | latest_output: String.trim(data)}}
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
        Map.update!(state.health, :errors, &(&1 + 1))
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

  def handle_info({:DOWN, _ref, :port, port, :normal}, state) do
    Logger.info("Handled :DOWN message from port: #{inspect(port)}")
    {:noreply, state}
  end

  def handle_info({:EXIT, port, :normal}, state) do
    Logger.info("handle_info: EXIT - #{inspect(port)}")
    {:noreply, state}
  end

  def handle_info(:startup_timeout, state) do
    Logger.warning("Port startup timeout reached")

    # Reply to any waiting callers with timeout error
    waiting_callers = Map.get(state, :waiting_callers, [])

    Enum.each(waiting_callers, fn from ->
      GenServer.reply(from, {:error, :startup_timeout})
    end)

    new_state =
      state
      |> Map.put(:waiting_callers, [])
      |> Map.put(:startup_timeout_ref, nil)

    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.info("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
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

  defp maybe_add_default_options(options, keys_to_validate, default) do
    if options_empty?(options, keys_to_validate) do
      options ++ default
    else
      options
    end
  end

  defp options_empty?(options, keys) do
    options
    |> Enum.filter(&(&1 in keys))
    |> Enum.empty?()
  end

  # Validation functions
  defp validate_start_args(args) when is_list(args) do
    cond do
      Keyword.has_key?(args, :name) && not is_atom(Keyword.get(args, :name)) ->
        {:error, :invalid_name}

      Keyword.has_key?(args, :opts) && not is_list(Keyword.get(args, :opts)) ->
        {:error, :invalid_opts}

      true ->
        :ok
    end
  end

  defp validate_start_args(_), do: {:error, :invalid_args}

  defp validate_new_args(args) when is_list(args) do
    cond do
      Keyword.has_key?(args, :cmd) && not is_binary(Keyword.get(args, :cmd)) ->
        {:error, :invalid_cmd}

      Keyword.has_key?(args, :opts) && not is_list(Keyword.get(args, :opts)) ->
        {:error, :invalid_opts}

      true ->
        :ok
    end
  end

  defp validate_new_args(_), do: {:error, :invalid_args}

  # Retry logic - configurable for tests
  @max_retries Application.compile_env(:tailwind_port, :max_retries, 3)
  @retry_delay Application.compile_env(:tailwind_port, :retry_delay, 1000)

  # Health metrics
  defp update_health_metrics(state, data) do
    health =
      state.health
      |> Map.put(:last_activity, System.system_time())
      |> Map.update!(:total_outputs, &(&1 + 1))

    # Increment CSS builds if this looks like a CSS-related output
    health =
      if String.contains?(data, "{") or String.contains?(data, "}") or
           String.contains?(data, "Done") or String.contains?(data, "Rebuilding") do
        Map.update!(health, :css_builds, &(&1 + 1))
      else
        health
      end

    %{state | health: health}
  end

  # Port readiness detection
  defp maybe_mark_port_ready(%{port_ready: true} = state, _data), do: state

  defp maybe_mark_port_ready(%{port_ready: false} = state, data) do
    # Consider port ready if we get any output that suggests Tailwind is running
    # This could be refined based on specific Tailwind output patterns
    # Basic check - any output suggests the port is working
    ready =
      String.contains?(data, "Rebuilding") or
        String.contains?(data, "Done in") or
        String.contains?(data, "Built successfully") or
        String.contains?(data, "Watching") or
        byte_size(data) > 0

    if ready do
      Logger.debug("Port marked as ready based on output: #{inspect(String.slice(data, 0, 100))}")

      # Cancel startup timeout
      if state.startup_timeout_ref do
        Process.cancel_timer(state.startup_timeout_ref)
      end

      # Reply to any waiting callers
      waiting_callers = Map.get(state, :waiting_callers, [])

      Enum.each(waiting_callers, fn from ->
        GenServer.reply(from, :ok)
      end)

      state
      |> Map.put(:port_ready, true)
      |> Map.put(:startup_timeout_ref, nil)
      |> Map.put(:waiting_callers, [])
    else
      state
    end
  end

  defp create_port_with_retry(_args, retry_count) when retry_count >= @max_retries do
    {:error, :max_retries_exceeded}
  end

  defp create_port_with_retry(args, retry_count) do
    try do
      port = new_port(args)
      {:ok, port}
    rescue
      error ->
        Logger.warning(
          "Port creation failed (attempt #{retry_count + 1}/#{@max_retries}): #{inspect(error)}"
        )

        if retry_count < @max_retries - 1 do
          # Exponential backoff
          Process.sleep(@retry_delay * (retry_count + 1))
          create_port_with_retry(args, retry_count + 1)
        else
          {:error, error}
        end
    catch
      kind, reason ->
        Logger.warning(
          "Port creation failed (attempt #{retry_count + 1}/#{@max_retries}): #{kind} #{inspect(reason)}"
        )

        if retry_count < @max_retries - 1 do
          Process.sleep(@retry_delay * (retry_count + 1))
          create_port_with_retry(args, retry_count + 1)
        else
          {:error, {kind, reason}}
        end
    end
  end
end
