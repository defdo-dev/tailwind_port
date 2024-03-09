defmodule Defdo.TailwindPort do
  @doc """
  Commands:
   init [options]

  Options:
    -i, --input              Input file
    -o, --output             Output file
    -w, --watch              Watch for changes and rebuild as needed
    -p, --poll               Use polling instead of filesystem events when watching
        --content            Content paths to use for removing unused classes
        --postcss            Load custom PostCSS configuration
    -m, --minify             Minify the output
    -c, --config             Path to a custom config file
        --no-autoprefixer    Disable autoprefixer
    -h, --help               Display usage information

  {:ok, state} = Defdo.TailwindPort.init [opts: ["--watch", "--content", "#{File.cwd!()}/priv/static/html/**/*.{html,js}", "-c", "#{File.cwd!()}/assets/tailwind.config.js"]]
  """
  # content: "../src/**/*.{html,js}"
  # config: "./assets/tailwind.config.js"
  # Download file and put into bin directory ignore it by .gitignore
  # https://storage.defdo.de/tailwind_cli_daisyui/tailwindcss-linux-arm64
  # https://storage.defdo.de/tailwind_cli_daisyui/tailwindcss-linux-x64
  # https://storage.defdo.de/tailwind_cli_daisyui/tailwindcss-macos-arm64
  # https://storage.defdo.de/tailwind_cli_daisyui/tailwindcss-macos-x64
  # https://storage.defdo.de/tailwind_cli_daisyui/tailwindcss-windows-x64.exe
  use GenServer, restart: :transient
  require Logger

  alias Defdo.TailwindCustomDownload
  alias Defdo.TailwindPort.FS

  # GenServer API
  def start_link(args \\ []) do
    {name, args} = get_from_args(args, :name, __MODULE__)

    GenServer.start_link(__MODULE__, args, name: name)
  end

  @spec init(args :: keyword()) :: {:ok, map()}

  def init([]) do
    Process.flag(:trap_exit, true)
    {:ok, %{port: nil, latest_output: nil, exit_status: nil, fs: random_fs()}}
  end

  def init(args) do
    Process.flag(:trap_exit, true)

    {:ok, %{port: nil, latest_output: nil, exit_status: nil, fs: random_fs()},
     {:continue, {:new, args}}}
  end

  @doc """
  Creates a new `TailwindPort`.

  Options:

    * `cmd` - Should contain the binary to run, default to downloadable binary.
    * `opts` - Are passed directly to the binary, see details at module options.
  """
  def new(name \\ __MODULE__, args) do
    unless Keyword.has_key?(args, :opts) do
      Logger.warning(
        "Keyword `opts` must contain the arguments required by tailwind_port to work as you expect, but it is not provided."
      )
    end
    # sometime we should download the tailwind binary in that case we will increase the timeout.
    timeout = if Keyword.has_key?(args, :cmd), do: 5000, else: 60000
    GenServer.call(name, {:new, args}, timeout)
  end

  defp new_port(args) do
    bin_path = bin_path()

    cmd = Keyword.get(args, :cmd, "#{bin_path}/tailwindcss")

    unless File.dir?(bin_path) && File.exists?(cmd) do
      Logger.debug("The `cmd` doesn't have a valid tailwind binary, we proceed to download")
      TailwindCustomDownload.download(cmd)
    end

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

    {command, args} =
      if "-i" in opts || "--input" in opts do
        # direct call binary
        {cmd, options}
      else
        # Wraps command
        {"#{bin_path}/tailwind_cli.sh", ["#{cmd}" | options]}
      end

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

    port
  end

  # bin path for local test
  defp bin_path do
    project_path = :code.priv_dir(:tailwind_port)
    Path.join([project_path, "bin"])
  end

  @doc """
  Obtain a random temporal directory structure
  """
  def random_fs do
    path = [System.tmp_dir(), random_dir_name()] |> Enum.reject(&is_nil/1) |> Path.join()

    FS.new(path: path)
  end

  @doc """
  Obtain a random name to use as dynamic directory.
  """
  def random_dir_name(len \\ 10) do
    :crypto.strong_rand_bytes(len) |> Base.encode64(padding: false)
  end

  @doc """
  Initialize a directory structure into the filesystem
  """
  def init_fs(name \\ __MODULE__) do
    GenServer.call(name, :init_fs)
  end

  @doc """
  Updates the FS struct into the state
  """
  def update_fs(name \\ __MODULE__, opts) do
    GenServer.call(name, {:update_fs, opts})
  end

  @doc """
  Similar to `update_fs/2` but automatically initialize the filesystem directory.
  """
  def update_and_init_fs(name \\ __MODULE__, opts) do
    GenServer.call(name, {:update_and_init_fs, opts})
  end

  @doc """
  Get the current state for the running process.
  """
  def state(name \\ __MODULE__) do
    GenServer.call(name, :get_state)
  end

  @doc """
  Complete the execution for running process.
  """
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
      Logger.debug("Port: #{inspect(port)} does'n exist.")
    end

    {:shutdown, reason}
  end

  def handle_continue({:new, args}, state) do
    {:noreply, %{state | port: new_port(args)}}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
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
    port = new_port(args)
    new_state = %{state | port: port}

    {:reply, new_state, new_state}
  end

  # This callback handles data incoming from the command's STDOUT
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    if String.contains?(data, "{") or String.contains?(data, "}") do
      Logger.debug(["CSS:", "#{inspect(data)}"])

      :telemetry.execute(
        [:tailwind_port, :css, :done],
        %{},
        %{port: port, data: data}
      )

      {:noreply, %{state | latest_output: String.trim(data)}}
    else
      :telemetry.execute(
        [:tailwind_port, :other, :done],
        %{},
        %{port: port, data: data}
      )

      {:noreply, state}
    end
  end

  # This callback tells us when the process exits
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("Port exit: :exit_status: #{status}")

    new_state = %{state | exit_status: status}

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

  def handle_info(msg, state) do
    Logger.info("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp warn_if_orphaned(port_info) do
    if os_pid = port_info[:os_pid] do
      Logger.warning("Orphaned OS process: #{os_pid}")
    end
  end

  defp get_from_args(list, key, default) when is_list(list) do
    if element = list[key] do
      {element, list}
    else
      {default, list}
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
end
