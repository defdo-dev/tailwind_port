defmodule Defdo.TailwindPort.ProjectSetup do
  @moduledoc """
  Project setup and initialization utilities for TailwindPort.

  This module handles the setup and initialization of Tailwind CSS projects,
  including directory creation, configuration file generation, and asset 
  organization. It provides utilities for both new project setup and 
  maintenance of existing projects.

  ## Features

  - **Asset Directory Management**: Creates and manages asset directory structure
  - **Configuration Generation**: Creates default Tailwind config files
  - **Phoenix Integration**: Generates Phoenix-specific configurations
  - **Error Handling**: Comprehensive error reporting for setup operations
  - **Idempotent Operations**: Safe to run multiple times without side effects

  ## Project Structure

  The module sets up the following directory structure:

      assets/
      ├── css/                 # CSS source files
      └── tailwind.config.js   # Tailwind configuration

  ## Configuration Features

  The generated Tailwind configuration includes:
  - **Content paths** for Phoenix projects (LiveView, templates)
  - **Phoenix-specific variants** for interactive states
  - **Form plugins** for better form styling
  - **Theme extensions** ready for customization

  ## Usage

      # Complete project setup
      case ProjectSetup.setup_project() do
        :ok -> IO.puts("Project initialized successfully")
        {:error, _error} -> Logger.error("Setup failed")
      end

      # Setup specific components
      :ok = ProjectSetup.ensure_assets_directory()
      :ok = ProjectSetup.create_tailwind_config()

  ## Error Handling

  All functions return `{:ok, result}` or `{:error, reason}` tuples:

      case ProjectSetup.setup_project() do
        :ok ->
          IO.puts("Ready to use Tailwind CSS!")
        {:error, {:assets_mkdir_failed, _error}} ->
          Logger.error("Failed to create assets directory")
        {:error, {:config_write_failed, _error}} ->
          Logger.error("Failed to write config file")
      end

  """

  require Logger

  @typedoc "Project setup error reasons"
  @type setup_error ::
          {:assets_mkdir_failed, term()}
          | {:config_write_failed, term()}
          | {:invalid_config_path, String.t()}

  @doc """
  Performs complete project setup for Tailwind CSS.

  This function sets up everything needed for a Tailwind CSS project including
  asset directories and configuration files. It's designed to be idempotent
  and safe to run multiple times.

  ## Returns

    * `:ok` - Project setup completed successfully
    * `{:error, setup_error()}` - Setup failed with specific reason

  ## Examples

      # Basic project setup
      case ProjectSetup.setup_project() do
        :ok ->
          IO.puts("Project ready for Tailwind CSS development!")
        {:error, _error} ->
          Logger.error("Setup failed")
      end

  ## What it does

  1. **Creates asset directories** (`assets/css/`)
  2. **Generates Tailwind config** (`assets/tailwind.config.js`)
  3. **Sets up Phoenix integration** (LiveView-specific configurations)

  """
  @spec setup_project() :: :ok | {:error, setup_error()}
  def setup_project do
    with :ok <- ensure_assets_directory(),
         :ok <- create_tailwind_config() do
      Logger.info("Tailwind CSS project setup completed successfully")
      :ok
    end
  end

  @doc """
  Ensures the assets directory structure exists.

  Creates the necessary directories for Tailwind CSS assets including
  the main assets directory and CSS subdirectory.

  ## Returns

    * `:ok` - Directories created or already exist
    * `{:error, {:assets_mkdir_failed, reason}}` - Directory creation failed

  ## Examples

      # Ensure assets directory exists
      case ProjectSetup.ensure_assets_directory() do
        :ok ->
          IO.puts("Assets directory ready")
        {:error, {:assets_mkdir_failed, _error}} ->
          Logger.error("Failed to create directory")
      end

  ## Directories Created

  - `assets/` - Main assets directory
  - `assets/css/` - CSS source files directory

  """
  @spec ensure_assets_directory() :: :ok | {:error, {:assets_mkdir_failed, term()}}
  def ensure_assets_directory do
    case File.mkdir_p("assets/css") do
      :ok -> :ok
      {:error, reason} -> {:error, {:assets_mkdir_failed, reason}}
    end
  end

  @doc """
  Creates a Tailwind CSS configuration file.

  Generates a default Tailwind configuration file optimized for Phoenix
  projects. The configuration includes content paths, theme extensions,
  and Phoenix-specific plugins.

  ## Parameters

    * `config_path` - Path for the config file (default: "assets/tailwind.config.js")

  ## Returns

    * `:ok` - Configuration file created or already exists
    * `{:error, setup_error()}` - Configuration creation failed

  ## Examples

      # Create default config
      :ok = ProjectSetup.create_tailwind_config()

      # Create config at custom path
      case ProjectSetup.create_tailwind_config("./custom/tailwind.config.js") do
        :ok ->
          IO.puts("Custom config created")
        {:error, _error} ->
          Logger.error("Config creation failed")
      end

  ## Generated Configuration

  The configuration includes:
  - **Content paths** for Phoenix templates and LiveView files
  - **Form plugins** for better form styling
  - **Phoenix variants** for interactive states (loading, feedback)
  - **Theme extensions** placeholder for customization

  """
  @spec create_tailwind_config(String.t()) :: :ok | {:error, setup_error()}
  def create_tailwind_config(config_path \\ "assets/tailwind.config.js") do
    expanded_path = Path.expand(config_path)

    with :ok <- validate_config_path(expanded_path) do
      maybe_create_config_file(expanded_path)
    end
  end

  @doc """
  Gets the default Tailwind CSS configuration content.

  Returns the template configuration content that will be written to
  the configuration file. This is useful for previewing or customizing
  the configuration before writing.

  ## Returns

    * `String.t()` - Configuration file content

  ## Examples

      # Preview configuration
      content = ProjectSetup.get_default_config_content()
      IO.puts("Config preview:")
      IO.puts(content)

      # Custom config creation
      custom_content = ProjectSetup.get_default_config_content()
      |> String.replace("'./js/**/*.js'", "'./frontend/**/*.js'")
      
      File.write("custom.config.js", custom_content)

  """
  @spec get_default_config_content() :: String.t()
  def get_default_config_content do
    """
    // See the Tailwind configuration guide for advanced usage
    // https://tailwindcss.com/docs/configuration
    let plugin = require('tailwindcss/plugin')
    module.exports = {
      content: [
        './js/**/*.js',
        '../lib/*_web.ex',
        '../lib/*_web/**/*.*ex'
      ],
      theme: {
        extend: {},
      },
      plugins: [
        require('@tailwindcss/forms'),
        plugin(({addVariant}) => addVariant('phx-no-feedback', ['&.phx-no-feedback', '.phx-no-feedback &'])),
        plugin(({addVariant}) => addVariant('phx-click-loading', ['&.phx-click-loading', '.phx-click-loading &'])),
        plugin(({addVariant}) => addVariant('phx-submit-loading', ['&.phx-submit-loading', '.phx-submit-loading &'])),
        plugin(({addVariant}) => addVariant('phx-change-loading', ['&.phx-change-loading', '.phx-change-loading &']))
      ]
    }
    """
  end

  @doc """
  Checks if project setup is complete.

  Validates that all required directories and configuration files exist
  for a properly set up Tailwind CSS project.

  ## Returns

    * `true` - Project is properly set up
    * `false` - Project setup is incomplete

  ## Examples

      # Check project status
      if ProjectSetup.project_setup_complete?() do
        IO.puts("Project is ready for development")
      else
        IO.puts("Run ProjectSetup.setup_project() to initialize")
      end

  ## Validation Checks

  - `assets/css/` directory exists
  - `assets/tailwind.config.js` file exists
  - Configuration file is readable

  """
  @spec project_setup_complete?() :: boolean()
  def project_setup_complete? do
    assets_exist? = File.dir?("assets/css")
    config_exists? = File.exists?("assets/tailwind.config.js")

    config_readable? =
      case File.read("assets/tailwind.config.js") do
        {:ok, content} when byte_size(content) > 0 -> true
        _ -> false
      end

    assets_exist? and config_exists? and config_readable?
  end

  @doc """
  Cleans up project setup (for testing or reset).

  Removes all files and directories created by the setup process.
  Use with caution as this will delete asset directories and configurations.

  ## Parameters

    * `opts` - Options for cleanup behavior
      - `:keep_assets` - Keep asset directories, only remove config (default: false)

  ## Returns

    * `:ok` - Cleanup completed
    * `{:error, term()}` - Cleanup failed

  ## Examples

      # Complete cleanup
      :ok = ProjectSetup.cleanup_project()

      # Keep assets, only remove config
      :ok = ProjectSetup.cleanup_project(keep_assets: true)

  ## Warning

  This function will permanently delete:
  - `assets/tailwind.config.js` (always)
  - `assets/css/` directory (unless `:keep_assets` is true)
  - `assets/` directory (unless `:keep_assets` is true and directory is empty)

  """
  @spec cleanup_project(keyword()) :: :ok | {:error, term()}
  def cleanup_project(opts \\ []) do
    keep_assets = Keyword.get(opts, :keep_assets, false)

    # Always remove config file
    File.rm("assets/tailwind.config.js")

    unless keep_assets do
      File.rm_rf("assets/css")
      # Remove assets directory if empty
      case File.ls("assets") do
        {:ok, []} -> File.rmdir("assets")
        _ -> :ok
      end
    end

    :ok
  end

  # Private helper functions

  defp validate_config_path(path) when is_binary(path) do
    cond do
      String.trim(path) == "" ->
        {:error, {:invalid_config_path, "Config path cannot be empty"}}

      not String.ends_with?(path, ".js") ->
        {:error, {:invalid_config_path, "Config file must have .js extension"}}

      true ->
        :ok
    end
  end

  defp maybe_create_config_file(config_path) do
    if File.exists?(config_path) do
      Logger.debug("Tailwind config already exists at #{config_path}")
      :ok
    else
      Logger.info("Creating Tailwind config at #{config_path}")

      # Ensure directory exists
      config_dir = Path.dirname(config_path)

      with :ok <- File.mkdir_p(config_dir),
           :ok <- write_config_content(config_path) do
        :ok
      else
        {:error, reason} -> {:error, {:config_write_failed, reason}}
      end
    end
  end

  defp write_config_content(config_path) do
    config_content = get_default_config_content()

    case File.write(config_path, config_content) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
