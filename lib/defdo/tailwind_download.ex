defmodule Defdo.TailwindDownload do
  @moduledoc """
  Secure Tailwind CSS binary download and management.

  This module handles downloading, verifying, and installing Tailwind CSS binaries
  for different platforms. It includes security features like binary verification,
  proper error handling, and configurable download sources.

  ## Features

  - **Multi-platform Support**: Automatic platform detection and binary selection
  - **Security**: Binary signature verification and size validation
  - **Configurable**: Custom versions, URLs, and installation paths
  - **Reliable**: Comprehensive error handling and validation
  - **Proxy Support**: HTTP/HTTPS proxy support with authentication

  ## Configuration

  ### Version Configuration

  Configure a specific Tailwind CSS version in your `config.exs`:

      config :tailwind_port, version: "3.4.1"

  ### Custom Download URL

  Configure a custom download URL with placeholders:

      config :tailwind_port,
        url: "https://github.com/tailwindlabs/tailwindcss/releases/download/v$version/tailwindcss-$target"

  ### Custom Installation Path

      config :tailwind_port, path: "/usr/local/bin/tailwindcss"

  ### Certificate Configuration

      config :tailwind_port, cacerts_path: "/path/to/cacerts.pem"

  ## URL Placeholders

  The download URL supports dynamic placeholders:

  - `$version` - Replaced with the configured version
  - `$target` - Replaced with platform-specific target (e.g., "linux-x64", "macos-arm64")

  ## Supported Platforms

  - **Linux**: x64, ARM64, ARMv7
  - **macOS**: x64, ARM64 (Apple Silicon)
  - **Windows**: x64
  - **FreeBSD**: x64, ARM64

  ## Examples

      # Basic download with defaults
      case Defdo.TailwindDownload.download() do
        :ok -> IO.puts("Download successful!")
        {:error, reason} -> IO.puts("Download failed: \#{inspect(reason)}")
      end

      # Download to specific path
      :ok = Defdo.TailwindDownload.download("/custom/path/tailwindcss")

      # Install with config creation
      case Defdo.TailwindDownload.install() do
        :ok -> IO.puts("Installation complete!")
        {:error, reason} -> handle_install_error(reason)
      end

      # Check configured version
      version = Defdo.TailwindDownload.configured_version()
      IO.puts("Using Tailwind CSS v\#{version}")

  ## Error Handling

  All functions return `{:ok, result}` or `{:error, reason}` for proper error handling:

      case Defdo.TailwindDownload.download("/tmp/tailwindcss") do
        :ok ->
          :ok
        {:error, {:binary_too_small, size}} ->
          Logger.error("Downloaded binary too small: \#{size} bytes")
        {:error, :invalid_elf_signature} ->
          Logger.error("Invalid binary signature for Linux platform")
        {:error, {:download_failed, reason}} ->
          Logger.error("Network error: \#{inspect(reason)}")
      end

  """
  require Logger
  alias Defdo.TailwindPort.BinaryManager
  alias Defdo.TailwindPort.ConfigManager
  alias Defdo.TailwindPort.HttpClient
  alias Defdo.TailwindPort.ProjectSetup
  alias Defdo.TailwindPort.Telemetry
  alias Defdo.TailwindPort.Validation

  @doc """
  The default URL to install Tailwind from.
  """
  @spec default_base_url() :: String.t()
  def default_base_url do
    ConfigManager.get_base_url()
  end

  defp get_url(base_url) do
    ConfigManager.build_download_url(base_url)
  end

  defp bin_path do
    ConfigManager.get_binary_path()
  end

  @doc """
  Returns the configured tailwind version.

  if you want a specific version, you must configure the version in your `config.exs` file.

  Example:

      config :tailwind_port, version: "3.4.1"

  """
  @spec configured_version() :: String.t()
  def configured_version do
    ConfigManager.get_version()
  end

  @doc """
  Downloads and verifies a Tailwind CSS binary.

  This function downloads the Tailwind CSS binary for the current platform,
  performs security verification, and installs it at the specified path.
  It includes comprehensive error handling and security checks.

  ## Parameters

    * `path` - Installation path for the binary (default: auto-detected)
    * `base_url` - Base URL for download with `$version` and `$target` placeholders

  ## Returns

    * `:ok` - Download and installation successful
    * `{:error, reason}` - Download failed with specific error

  ## Examples

      # Download with defaults
      case Defdo.TailwindDownload.download() do
        :ok ->
          IO.puts("Tailwind CSS binary ready!")
        {:error, reason} ->
          Logger.error("Download failed: \#{inspect(reason)}")
      end

      # Download to custom path
      :ok = Defdo.TailwindDownload.download("/usr/local/bin/tailwindcss")

      # Custom URL and path
      custom_url = "https://example.com/tailwind/v$version/tailwindcss-$target"
      case Defdo.TailwindDownload.download("/tmp/tailwind", custom_url) do
        :ok -> IO.puts("Custom download successful")
        {:error, {:http_error, 404}} -> IO.puts("Custom URL not found")
        {:error, reason} -> IO.puts("Error: \#{inspect(reason)}")
      end

  ## Error Reasons

  ### Validation Errors
  - `:invalid_path` - Path parameter is not a string
  - `:invalid_url` - URL parameter is not a string
  - `:empty_path` - Path parameter is empty
  - `:empty_url` - URL parameter is empty

  ### Download Errors
  - `{:http_error, status_code}` - HTTP error (404, 403, etc.)
  - `{:request_failed, reason}` - Network request failed
  - `:invalid_url` - Malformed download URL

  ### Binary Verification Errors
  - `{:binary_too_small, size}` - Downloaded file too small (< 1MB)
  - `{:binary_too_large, size}` - Downloaded file too large (> 100MB)
  - `:invalid_pe_signature` - Invalid Windows PE signature
  - `:invalid_macho_signature` - Invalid macOS Mach-O signature
  - `:invalid_elf_signature` - Invalid Linux/FreeBSD ELF signature

  ### File System Errors
  - `{:mkdir_failed, reason}` - Failed to create directory
  - `{:write_failed, reason}` - Failed to write binary file
  - `{:chmod_failed, reason}` - Failed to make binary executable

  ## Security Features

  - **Size Validation**: Ensures downloaded binary is reasonably sized
  - **Signature Verification**: Validates platform-specific executable signatures
  - **HTTPS Verification**: Uses proper certificate validation
  - **Input Sanitization**: Validates all parameters before use

  """
  @spec download(String.t(), String.t()) :: :ok | {:error, term()}
  def download(path \\ bin_path(), base_url \\ default_base_url()) do
    start_time = System.monotonic_time()
    target = ConfigManager.get_target()

    # Emit download start event
    Telemetry.track_download(:start, %{}, %{
      path: path,
      base_url: base_url,
      target: target
    })

    result =
      with :ok <- Validation.validate_download_args(path, base_url),
           {:ok, url} <- build_download_url(base_url),
           {:ok, binary} <- fetch_binary(url),
           :ok <- verify_binary(binary),
           :ok <- ensure_directory(path),
           :ok <- write_binary(path, binary),
           :ok <- make_executable(path) do
        Logger.info("Successfully downloaded and verified Tailwind binary")
        :ok
      else
        {:error, reason} ->
          Logger.error("Download failed: #{inspect(reason)}")
          {:error, reason}
      end

    # Calculate duration and emit completion event
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    case result do
      :ok ->
        Telemetry.track_download(:complete, %{duration_ms: duration_ms}, %{
          path: path,
          target: target
        })

      {:error, reason} ->
        Telemetry.track_download(:error, %{duration_ms: duration_ms}, %{
          path: path,
          target: target,
          error_type: categorize_error(reason)
        })

        Telemetry.track_error(:download_failed, reason, %{
          path: path,
          target: target
        })
    end

    result
  end

  @doc """
  Downloads, installs, and configures Tailwind CSS for a project.

  This function performs a complete Tailwind CSS setup including binary download,
  verification, installation, and creation of default configuration files.
  It's designed for easy project setup and initialization.

  ## Parameters

    * `path` - Installation path for the binary (default: auto-detected)
    * `base_url` - Base URL for download with placeholders

  ## Returns

    * `:ok` - Installation and configuration successful
    * `{:error, reason}` - Installation failed with specific error

  ## What it does

  1. **Downloads binary** (if not already present)
  2. **Verifies binary** security and integrity
  3. **Creates directories** (`assets/css/` if needed)
  4. **Generates config** (`assets/tailwind.config.js` if missing)
  5. **Sets permissions** (makes binary executable)

  ## Examples

      # Complete project setup
      case Defdo.TailwindDownload.install() do
        :ok ->
          IO.puts("Tailwind CSS ready for your project!")
          IO.puts("Binary installed and config created")
        {:error, reason} ->
          Logger.error("Setup failed: \#{inspect(reason)}")
      end

      # Custom installation path
      :ok = Defdo.TailwindDownload.install("/opt/tailwindcss")

      # Verify installation
      case Defdo.TailwindDownload.install() do
        :ok ->
          # Verify the installation worked
          if File.exists?("assets/tailwind.config.js") do
            IO.puts("Config file created successfully")
          end
        error ->
          handle_installation_error(error)
      end

  ## Created Configuration

  When run, this function creates a default `assets/tailwind.config.js` with:

  - **Content paths** for Phoenix/LiveView projects
  - **Plugin configuration** for Phoenix-specific utilities
  - **Theme extensions** ready for customization

  Example generated config:

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
          // Phoenix-specific variants
        ]
      }

  ## Error Handling

      case Defdo.TailwindDownload.install() do
        :ok ->
          proceed_with_build()
        {:error, {:download_failed, reason}} ->
          Logger.error("Failed to download: \#{inspect(reason)}")
        {:error, {:config_write_failed, reason}} ->
          Logger.error("Failed to create config: \#{inspect(reason)}")
        {:error, {:assets_mkdir_failed, reason}} ->
          Logger.error("Failed to create assets dir: \#{inspect(reason)}")
      end

  ## Use Cases

  - **Project initialization**: Set up Tailwind in new projects
  - **CI/CD pipelines**: Ensure Tailwind is available in build environments
  - **Development setup**: One-command Tailwind installation
  - **Container builds**: Automated Tailwind setup in Docker images

  """
  @spec install(String.t(), String.t()) :: :ok | {:error, term()}
  def install(path \\ bin_path(), base_url \\ default_base_url()) do
    with :ok <- maybe_download_binary(path, base_url),
         :ok <- setup_default_config() do
      :ok
    else
      {:error, reason} ->
        Logger.error("Installation failed: \#{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_binary(url) do
    HttpClient.fetch_binary(url)
  end

  # New helper functions for improved error handling

  defp build_download_url(base_url) do
    url = get_url(base_url)
    {:ok, url}
  rescue
    error -> {:error, {:url_build_failed, error}}
  end

  defp ensure_directory(path) do
    case BinaryManager.ensure_directory(path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  defp write_binary(path, binary) do
    case BinaryManager.write_binary(path, binary) do
      :ok -> :ok
      {:error, reason} -> {:error, {:write_failed, reason}}
    end
  end

  defp make_executable(path) do
    case BinaryManager.make_executable(path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:chmod_failed, reason}}
    end
  end

  # Basic binary verification - checks size and basic signatures
  defp verify_binary(binary) when is_binary(binary) do
    BinaryManager.verify_binary(binary)
  end

  defp maybe_download_binary(path, base_url) do
    # Validate before checking file existence to catch invalid types early
    with :ok <- Validation.validate_download_args(path, base_url) do
      if File.exists?(path) do
        :ok
      else
        download(path, base_url)
      end
    end
  end

  defp setup_default_config do
    ProjectSetup.setup_project()
  end

  # Categorize errors for better telemetry analysis
  defp categorize_error({:http_error, _}), do: :http_error
  defp categorize_error({:request_failed, _}), do: :network_error
  defp categorize_error({:binary_too_small, _}), do: :validation_error
  defp categorize_error({:binary_too_large, _}), do: :validation_error
  defp categorize_error({:invalid_elf_signature}), do: :validation_error
  defp categorize_error({:invalid_pe_signature}), do: :validation_error
  defp categorize_error({:invalid_macho_signature}), do: :validation_error
  defp categorize_error({:mkdir_failed, _}), do: :filesystem_error
  defp categorize_error({:write_failed, _}), do: :filesystem_error
  defp categorize_error({:chmod_failed, _}), do: :filesystem_error
  defp categorize_error(:invalid_path), do: :validation_error
  defp categorize_error(:invalid_url), do: :validation_error
  defp categorize_error(:empty_path), do: :validation_error
  defp categorize_error(:empty_url), do: :validation_error
  defp categorize_error(_), do: :unknown_error
end
