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
  @latest_version "3.4.1"

  # Latest known version at the time of publishing.
  defp latest_version, do: @latest_version

  @doc """
  The default URL to install Tailwind from.
  """
  @spec default_base_url() :: String.t()
  def default_base_url do
    Application.get_env(
      :tailwind_port,
      :url,
      "https://storage.defdo.de/tailwind_cli_daisyui/v$version/tailwindcss-$target"
    )
  end

  defp get_url(base_url) do
    base_url
    |> String.replace("$version", configured_version())
    |> String.replace("$target", target())
  end

  defp bin_path do
    name = "tailwindcss"

    Application.get_env(:tailwind_port, :path) ||
      if Code.ensure_loaded?(Mix.Project) do
        Path.join(Path.dirname(Mix.Project.build_path()), ["../bin/", name])
      else
        Path.expand("bin/#{name}")
      end
  end

  @doc """
  Returns the configured tailwind version.

  if you want a specific version, you must configure the version in your `config.exs` file.

  Example:

      config :tailwind_port, version: "3.4.1"

  """
  @spec configured_version() :: String.t()
  def configured_version do
    Application.get_env(:tailwind_port, :version, latest_version())
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
    with :ok <- validate_download_args(path, base_url),
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

  # Available targets:
  #  tailwindcss-freebsd-arm64
  #  tailwindcss-freebsd-x64
  #  tailwindcss-linux-arm64
  #  tailwindcss-linux-x64
  #  tailwindcss-linux-armv7
  #  tailwindcss-macos-arm64
  #  tailwindcss-macos-x64
  #  tailwindcss-windows-x64.exe
  defp target do
    arch_str = :erlang.system_info(:system_architecture)
    [arch | _] = arch_str |> List.to_string() |> String.split("-")

    case {:os.type(), arch, :erlang.system_info(:wordsize) * 8} do
      {{:win32, _}, _arch, 64} -> "windows-x64.exe"
      {{:unix, :darwin}, arch, 64} when arch in ~w(arm aarch64) -> "macos-arm64"
      {{:unix, :darwin}, "x86_64", 64} -> "macos-x64"
      {{:unix, :freebsd}, "aarch64", 64} -> "freebsd-arm64"
      {{:unix, :freebsd}, "amd64", 64} -> "freebsd-x64"
      {{:unix, :linux}, "aarch64", 64} -> "linux-arm64"
      {{:unix, :linux}, "arm", 32} -> "linux-armv7"
      {{:unix, :linux}, "armv7" <> _, 32} -> "linux-armv7"
      {{:unix, _osname}, arch, 64} when arch in ~w(x86_64 amd64) -> "linux-x64"
      {_os, _arch, _wordsize} -> raise "tailwind is not available for architecture: #{arch_str}"
    end
  end

  defp fetch_binary(url) do
    with {:ok, parsed_url} <- parse_url(url),
         :ok <- ensure_http_apps(),
         :ok <- setup_proxy(parsed_url.scheme),
         {:ok, response} <- make_http_request(url) do
      {:ok, response}
    end
  end

  defp parse_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> {:ok, URI.parse(url)}
      _ -> {:error, :invalid_url}
    end
  end

  defp ensure_http_apps do
    with {:ok, _} <- Application.ensure_all_started(:inets),
         {:ok, _} <- Application.ensure_all_started(:ssl) do
      :ok
    else
      {:error, reason} -> {:error, {:app_start_failed, reason}}
    end
  end

  defp setup_proxy(scheme) do
    if proxy = proxy_for_scheme(scheme) do
      case URI.parse(proxy) do
        %URI{host: host, port: port} when is_binary(host) and is_integer(port) ->
          Logger.debug("Using #{String.upcase(scheme)}_PROXY: #{proxy}")
          set_option = if "https" == scheme, do: :https_proxy, else: :proxy
          :httpc.set_options([{set_option, {{String.to_charlist(host), port}, []}}])
          :ok

        _ ->
          {:error, :invalid_proxy_url}
      end
    else
      :ok
    end
  end

  defp make_http_request(url) do
    url_charlist = String.to_charlist(url)
    Logger.debug("Downloading tailwind from #{url}")

    # https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/inets
    cacertfile = cacertfile() |> String.to_charlist()
    scheme = URI.parse(url).scheme

    http_options =
      [
        ssl: [
          verify: :verify_peer,
          cacertfile: cacertfile,
          depth: 2,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ],
          versions: protocol_versions()
        ]
      ]
      |> maybe_add_proxy_auth(scheme)

    options = [body_format: :binary]

    case :httpc.request(:get, {url_charlist, []}, http_options, options) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        {:ok, body}

      {:ok, {{_, status_code, _}, _headers, _body}} ->
        {:error, {:http_error, status_code}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp proxy_for_scheme("http") do
    System.get_env("HTTP_PROXY") || System.get_env("http_proxy")
  end

  defp proxy_for_scheme("https") do
    System.get_env("HTTPS_PROXY") || System.get_env("https_proxy")
  end

  defp maybe_add_proxy_auth(http_options, scheme) do
    case proxy_auth(scheme) do
      nil -> http_options
      auth -> [{:proxy_auth, auth} | http_options]
    end
  end

  defp proxy_auth(scheme) do
    with proxy when is_binary(proxy) <- proxy_for_scheme(scheme),
         %{userinfo: userinfo} when is_binary(userinfo) <- URI.parse(proxy),
         [username, password] <- String.split(userinfo, ":") do
      {String.to_charlist(username), String.to_charlist(password)}
    else
      _ -> nil
    end
  end

  defp cacertfile() do
    Application.get_env(:tailwind_port, :cacerts_path) || CAStore.file_path()
  end

  defp protocol_versions do
    if otp_version() < 25, do: [:"tlsv1.2"], else: [:"tlsv1.2", :"tlsv1.3"]
  end

  defp otp_version do
    :erlang.system_info(:otp_release) |> List.to_integer()
  end

  # New helper functions for improved error handling
  defp validate_download_args(path, base_url) do
    cond do
      not is_binary(path) -> {:error, :invalid_path}
      not is_binary(base_url) -> {:error, :invalid_url}
      String.trim(path) == "" -> {:error, :empty_path}
      String.trim(base_url) == "" -> {:error, :empty_url}
      true -> :ok
    end
  end

  defp build_download_url(base_url) do
    try do
      url = get_url(base_url)
      {:ok, url}
    rescue
      error -> {:error, {:url_build_failed, error}}
    end
  end

  defp ensure_directory(path) do
    dir = Path.dirname(path)

    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  defp write_binary(path, binary) do
    case File.write(path, binary, [:binary]) do
      :ok -> :ok
      {:error, reason} -> {:error, {:write_failed, reason}}
    end
  end

  defp make_executable(path) do
    case File.chmod(path, 0o755) do
      :ok -> :ok
      {:error, reason} -> {:error, {:chmod_failed, reason}}
    end
  end

  # Basic binary verification - checks size and basic signatures
  defp verify_binary(binary) when is_binary(binary) do
    with :ok <- check_binary_size(binary),
         :ok <- check_binary_signature(binary) do
      :ok
    end
  end

  defp check_binary_size(binary) do
    size = byte_size(binary)
    # Tailwind binary should be reasonably sized (between 1MB and 100MB)
    cond do
      size < 1_000_000 -> {:error, {:binary_too_small, size}}
      size > 100_000_000 -> {:error, {:binary_too_large, size}}
      true -> :ok
    end
  end

  defp check_binary_signature(binary) do
    # Check for common executable signatures based on target platform
    case target() do
      "windows" <> _ -> check_pe_signature(binary)
      "macos" <> _ -> check_macho_signature(binary)
      "linux" <> _ -> check_elf_signature(binary)
      "freebsd" <> _ -> check_elf_signature(binary)
      # Unknown platform, skip signature check
      _ -> :ok
    end
  end

  # Check for PE (Windows) signature
  defp check_pe_signature(<<"MZ", _::binary>>), do: :ok
  defp check_pe_signature(_), do: {:error, :invalid_pe_signature}

  # Check for Mach-O (macOS) signature
  # 32-bit
  defp check_macho_signature(<<0xFE, 0xED, 0xFA, 0xCE, _::binary>>), do: :ok
  # 64-bit
  defp check_macho_signature(<<0xFE, 0xED, 0xFA, 0xCF, _::binary>>), do: :ok
  # 32-bit (reversed)
  defp check_macho_signature(<<0xCE, 0xFA, 0xED, 0xFE, _::binary>>), do: :ok
  # 64-bit (reversed)
  defp check_macho_signature(<<0xCF, 0xFA, 0xED, 0xFE, _::binary>>), do: :ok
  defp check_macho_signature(_), do: {:error, :invalid_macho_signature}

  # Check for ELF (Linux/FreeBSD) signature
  defp check_elf_signature(<<0x7F, "ELF", _::binary>>), do: :ok
  defp check_elf_signature(_), do: {:error, :invalid_elf_signature}

  defp maybe_download_binary(path, base_url) do
    # Validate before checking file existence to catch invalid types early
    with :ok <- validate_download_args(path, base_url) do
      if File.exists?(path) do
        :ok
      else
        download(path, base_url)
      end
    end
  end

  defp setup_default_config do
    tailwind_config_path = Path.expand("assets/tailwind.config.js")

    with :ok <- ensure_assets_directory(),
         :ok <- maybe_create_config(tailwind_config_path) do
      :ok
    end
  end

  defp ensure_assets_directory do
    case File.mkdir_p("assets/css") do
      :ok -> :ok
      {:error, reason} -> {:error, {:assets_mkdir_failed, reason}}
    end
  end

  defp maybe_create_config(config_path) do
    if File.exists?(config_path) do
      :ok
    else
      config_content = """
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

      case File.write(config_path, config_content) do
        :ok -> :ok
        {:error, reason} -> {:error, {:config_write_failed, reason}}
      end
    end
  end
end
