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

  # GenServer API
  def start_link(args \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @spec init(command_args :: keyword()) :: {:ok, map()}
  def init(command_args \\ []) do
    Process.flag(:trap_exit, true)

    {:ok, %{port: new(command_args), latest_output: nil, exit_status: nil} }
  end

  def new(args) do
    {bin_path, _assets_path, _static_path} = project_paths()

    cmd = Keyword.get(args, :cmd, "#{bin_path}/tailwindcss")

    unless File.dir?(bin_path) && File.exists?(cmd) do
      TailwindCustomDownload.download(cmd)
    end

    options =
      args
      |> Keyword.get(:opts, [])
      |> maybe_add_default_options(["-i", "--input"], [])
      |> maybe_add_default_options(["-o", "--output"], [])
      |> maybe_add_default_options(["-w", "--watch"], [])
      |> maybe_add_default_options(["-p", "--poll"], [])
      |> maybe_add_default_options(["--content"], [])
      |> maybe_add_default_options(["--postcss"], [])
      |> maybe_add_default_options(["-m", "--minify"], [])
      |> maybe_add_default_options(["-c", "--config"], [])
      |> maybe_add_default_options(["--no-autoprefixer"], [])

    wrapper_command = "#{bin_path}/tailwind_cli.sh"

    args = ["#{cmd}" | options]

    port = Port.open({:spawn_executable, wrapper_command}, [{:args, args}, :binary, :exit_status, :use_stdio, :stderr_to_stdout])

    Port.monitor(port)

    Logger.debug(["Running command #{wrapper_command} #{Enum.join(args, " ")}"], color: :magenta)

    Logger.debug(["Running command ", Path.basename(wrapper_command), " Port is monitored."])

    port
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
    |> Enum.filter(& &1 in keys)
    |> Enum.empty?()
  end

  # returns project paths
  def project_paths do
    project_path = :code.priv_dir(:tailwind_port)
    bin_path = Path.join([project_path, "bin"])
    assets_path = Path.join([project_path, "../", "assets"])
    static_path = Path.join([project_path, "static"])

    {bin_path, assets_path, static_path}
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
  def terminate(reason, %{port: port} = state) do
    Logger.info "** TERMINATE: #{inspect reason}. This is the last chance to clean up after this process."
    Logger.info "Final state: #{inspect state}"

    if Port.info(port) do
      Port.close(port)

      port
      |> Port.info()
      |> warn_if_orphaned()
    else
      Logger.debug("Port: #{port} does'n exist.")
    end

    :shutdown
  end

  defp warn_if_orphaned(port_info) do
    if os_pid = port_info[:os_pid] do
      Logger.warn "Orphaned OS process: #{os_pid}"
    end
  end

  # This callback handles data incoming from the command's STDOUT
  def handle_info({port, {:data, text_line}}, %{port: port} = state) do
    Logger.info "Data: #{inspect text_line}"
    {:noreply, %{state | latest_output: String.trim(text_line)}}
  end

  # This callback tells us when the process exits
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info "Port exit: :exit_status: #{status}"

    new_state = %{state | exit_status: status}

    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :port, port, :normal}, state) do
    Logger.info "Handled :DOWN message from port: #{inspect port}"
    {:noreply, state}
  end

  def handle_info({:EXIT, port, :normal}, state) do
    Logger.info "handle_info: EXIT - #{port}"
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.info "Unhandled message: #{inspect msg}"
    {:noreply, state}
  end
end
