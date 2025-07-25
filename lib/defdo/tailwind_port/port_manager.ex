defmodule Defdo.TailwindPort.PortManager do
  @moduledoc """
  Port management functionality for TailwindPort.

  This module handles the creation, configuration, and management of Elixir ports
  that interface with the Tailwind CSS CLI binary. It provides a clean separation
  of concerns for port-related operations.

  ## Features

  - **Binary Path Management**: Handles binary discovery and download coordination
  - **Command Building**: Constructs appropriate command arguments for different scenarios
  - **Port Creation**: Creates and monitors Elixir ports with proper error handling
  - **Wrapper Script Support**: Handles both direct binary execution and wrapper scripts

  ## Usage

      # Create a new port with options
      case PortManager.create_port([opts: ["-i", "input.css", "-o", "output.css"]]) do
        {:ok, port} -> 
          # Port created successfully
        {:error, reason} -> 
          # Handle error
      end

  """

  require Logger
  alias Defdo.TailwindDownload
  alias Defdo.TailwindPort.Validation

  @doc """
  Creates a new Elixir port for Tailwind CSS CLI execution.

  This is the main entry point for port creation. It handles the complete workflow
  from binary path resolution to port creation with proper error handling.

  ## Parameters

    * `args` - Keyword list of options for port creation
      * `:cmd` - Custom command path (optional)
      * `:opts` - List of CLI arguments to pass to Tailwind

  ## Returns

    * `{:ok, port}` - Successfully created port
    * `{:error, reason}` - Creation failed with specific reason

  ## Examples

      # Basic port creation
      {:ok, port} = PortManager.create_port(opts: ["-i", "input.css"])

      # With custom binary
      {:ok, port} = PortManager.create_port(cmd: "/usr/local/bin/tailwindcss", opts: [])

      # Watch mode
      {:ok, port} = PortManager.create_port(opts: ["-w", "-i", "src.css", "-o", "dist.css"])

  ## Error Handling

  Common error reasons include:
  - `{:mkdir_failed, reason}` - Failed to create binary directory
  - `{:download_failed, reason}` - Failed to download Tailwind binary
  - `{:port_creation_failed, reason}` - Failed to create the Elixir port

  """
  @spec create_port(keyword()) :: {:ok, port()} | {:error, term()}
  def create_port(args) do
    with {:ok, bin_path} <- get_bin_path(),
         {:ok, cmd} <- prepare_command(args, bin_path),
         {:ok, {command, final_args}} <- build_command_args(args, cmd, bin_path) do
      case create_elixir_port(command, final_args) do
        {:ok, port} ->
          {:ok, port}

        {:error, reason} ->
          Logger.error("Failed to create port: #{inspect(reason)}")
          {:error, {:port_creation_failed, reason}}
      end
    else
      {:error, reason} ->
        Logger.error("Failed to prepare port: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets or creates the binary directory path.

  Ensures the binary directory exists and is accessible for storing
  the Tailwind CSS binary and related files.

  ## Returns

    * `{:ok, path}` - Binary directory path
    * `{:error, {:mkdir_failed, reason}}` - Failed to create directory

  """
  @spec get_bin_path() :: {:ok, String.t()} | {:error, {:mkdir_failed, term()}}
  def get_bin_path do
    bin_path = get_default_bin_path()

    if File.dir?(bin_path) do
      {:ok, bin_path}
    else
      case File.mkdir_p(bin_path) do
        :ok -> {:ok, bin_path}
        {:error, reason} -> {:error, {:mkdir_failed, reason}}
      end
    end
  end

  @doc """
  Prepares the command path, downloading the binary if necessary.

  This function resolves the actual binary path to use, either from
  the provided command or by using the default path. If the binary
  doesn't exist, it coordinates with TailwindDownload to fetch it.

  ## Parameters

    * `args` - Keyword list containing potential `:cmd` override
    * `bin_path` - Default binary directory path

  ## Returns

    * `{:ok, cmd_path}` - Resolved command path
    * `{:error, {:download_failed, reason}}` - Download failed

  """
  @spec prepare_command(keyword(), String.t()) ::
          {:ok, String.t()} | {:error, {:download_failed, term()}}
  def prepare_command(args, bin_path) do
    cmd = Keyword.get(args, :cmd, "#{bin_path}/tailwindcss")

    if File.exists?(cmd) do
      {:ok, cmd}
    else
      Logger.debug("The `cmd` doesn't have a valid tailwind binary, we proceed to download")

      case TailwindDownload.download(cmd) do
        :ok -> {:ok, cmd}
        {:error, reason} -> {:error, {:download_failed, reason}}
        # download/1 doesn't return :ok currently, assume success if not error tuple
        _ -> {:ok, cmd}
      end
    end
  end

  @doc """
  Builds the final command and arguments for port execution.

  This function processes the provided options and determines whether to use
  the binary directly or through a wrapper script. It also handles various
  Tailwind CLI options and their defaults.

  ## Parameters

    * `args` - Keyword list containing `:opts` and other parameters
    * `cmd` - Path to the Tailwind binary
    * `bin_path` - Binary directory path

  ## Returns

    * `{:ok, {command, args}}` - Tuple with final command and argument list

  """
  @spec build_command_args(keyword(), String.t(), String.t()) :: {:ok, {String.t(), [String.t()]}}
  def build_command_args(args, cmd, bin_path) do
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
      if has_input_option?(opts) do
        # Direct call to binary when input is specified
        {cmd, options}
      else
        # Use wrapper script when no input specified
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

  @doc """
  Validates if the provided arguments contain CLI options.

  This function delegates to the centralized Validation module.

  ## Parameters

    * `args` - Keyword list to validate

  ## Returns

    * `:ok` - Arguments are valid
    * `{:error, reason}` - Arguments are invalid

  """
  @spec validate_args(keyword()) :: :ok | {:error, term()}
  def validate_args(args) do
    Validation.validate_port_args(args)
  end

  # Private functions

  defp create_elixir_port(command, args) do
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

  defp get_default_bin_path do
    project_path = :code.priv_dir(:tailwind_port)
    Path.join([project_path, "bin"])
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

  defp has_input_option?(opts) do
    "-i" in opts || "--input" in opts
  end
end
