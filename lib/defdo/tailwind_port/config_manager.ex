defmodule Defdo.TailwindPort.ConfigManager do
  @moduledoc """
  Configuration management for TailwindPort.

  This module centralizes all configuration-related functionality including
  version management, URL construction, path resolution, and environment
  configuration. It provides a clean abstraction for accessing and managing
  TailwindPort configuration from various sources.

  ## Features

  - **Version Management**: Configurable Tailwind CSS version with fallback to latest
  - **URL Construction**: Dynamic URL building with placeholder replacement
  - **Path Resolution**: Intelligent binary path resolution for different environments
  - **Environment Configuration**: Application-level configuration management
  - **Default Values**: Sensible defaults for all configuration options

  ## Configuration Sources

  ### Application Configuration

  Configure in your `config.exs`:

      config :tailwind_port,
        version: "3.4.1",
        url: "https://example.com/tailwind/v$version/tailwindcss-$target",
        path: "/usr/local/bin/tailwindcss",
        cacerts_path: "/etc/ssl/certs/ca-certificates.crt"

  ### Environment Variables

  Some configuration can be overridden by environment variables:
  - Proxy settings (HTTP_PROXY, HTTPS_PROXY)
  - Certificate paths (via application config)

  ## URL Placeholders

  The download URL supports dynamic placeholders:
  - `$version` - Replaced with configured or latest version
  - `$target` - Replaced with platform-specific target identifier

  ## Path Resolution

  Binary paths are resolved in the following order:
  1. Explicitly configured `:path` option
  2. Mix project build path (if in Mix environment)
  3. Default `bin/tailwindcss` in current directory

  ## Usage

      # Get configured version
      version = ConfigManager.get_version()

      # Get binary installation path
      path = ConfigManager.get_binary_path()

      # Build download URL
      url = ConfigManager.build_download_url()

      # Custom URL with different base
      custom_url = ConfigManager.build_download_url("https://example.com/v$version/tailwindcss-$target")

  """

  alias Defdo.TailwindPort.BinaryManager

  @latest_version "3.4.1"

  @typedoc "Configuration value type"
  @type config_value :: String.t() | integer() | boolean() | nil

  @typedoc "URL template with placeholders"
  @type url_template :: String.t()

  @doc """
  Gets the configured Tailwind CSS version.

  Returns the version configured in application config, or falls back to
  the latest known version if not configured.

  ## Returns

    * `String.t()` - Version string (e.g., "3.4.1")

  ## Examples

      # With version configured
      config :tailwind_port, version: "3.3.0"
      
      ConfigManager.get_version()
      # => "3.3.0"

      # Without version configured
      ConfigManager.get_version()
      # => "3.4.1"  (latest)

  ## Configuration

  Set in `config.exs`:

      config :tailwind_port, version: "3.4.1"

  """
  @spec get_version() :: String.t()
  def get_version do
    case Application.get_env(:tailwind_port, :version, @latest_version) do
      nil -> @latest_version
      version when is_binary(version) -> version
      _ -> @latest_version
    end
  end

  @doc """
  Gets the default base URL for Tailwind CSS downloads.

  Returns the configured download URL template, or the default URL if not configured.
  The URL supports placeholders that are replaced during download URL construction.

  ## Returns

    * `String.t()` - URL template with placeholders

  ## Examples

      # With custom URL configured
      config :tailwind_port, url: "https://example.com/v$version/tailwindcss-$target"
      
      ConfigManager.get_base_url()
      # => "https://example.com/v$version/tailwindcss-$target"

      # With default configuration
      ConfigManager.get_base_url()
      # => "https://storage.defdo.de/tailwind_cli_daisyui/v$version/tailwindcss-$target"

  ## URL Placeholders

  - `$version` - Replaced with configured version
  - `$target` - Replaced with platform target (e.g., "linux-x64")

  """
  @spec get_base_url() :: url_template()
  def get_base_url do
    Application.get_env(
      :tailwind_port,
      :url,
      "https://storage.defdo.de/tailwind_cli_daisyui/v$version/tailwindcss-$target"
    )
  end

  @doc """
  Gets the binary installation path.

  Resolves the path where the Tailwind CSS binary should be installed.
  Uses configured path, Mix project path, or falls back to default location.

  ## Returns

    * `String.t()` - Absolute path for binary installation

  ## Examples

      # With explicit path configured
      config :tailwind_port, path: "/usr/local/bin/tailwindcss"
      
      ConfigManager.get_binary_path()
      # => "/usr/local/bin/tailwindcss"

      # In Mix project (automatic)
      ConfigManager.get_binary_path()
      # => "/path/to/project/_build/../bin/tailwindcss"

      # Default fallback
      ConfigManager.get_binary_path()
      # => "/current/directory/bin/tailwindcss"

  ## Path Resolution Priority

  1. **Configured path**: Explicit `:path` configuration
  2. **Mix project path**: Relative to Mix build directory
  3. **Default path**: `bin/tailwindcss` in current directory

  """
  @spec get_binary_path() :: String.t()
  def get_binary_path do
    name = "tailwindcss"

    Application.get_env(:tailwind_port, :path) ||
      if Code.ensure_loaded?(Mix.Project) do
        Path.join(Path.dirname(Mix.Project.build_path()), ["../bin/", name])
      else
        Path.expand("bin/#{name}")
      end
  end

  @doc """
  Builds a complete download URL from a base URL template.

  Takes a URL template with placeholders and replaces them with actual values
  to create a complete download URL for the current platform and version.

  ## Parameters

    * `base_url` - URL template with placeholders (default: configured base URL)

  ## Returns

    * `String.t()` - Complete download URL with placeholders replaced

  ## Examples

      # Using default base URL
      url = ConfigManager.build_download_url()
      # => "https://storage.defdo.de/tailwind_cli_daisyui/v3.4.1/tailwindcss-linux-x64"

      # Using custom base URL
      custom_url = ConfigManager.build_download_url("https://example.com/v$version/tailwindcss-$target")
      # => "https://example.com/v3.4.1/tailwindcss-linux-x64"

  ## Placeholder Replacement

  - `$version` → Current configured version (e.g., "3.4.1")
  - `$target` → Platform-specific target (e.g., "linux-x64", "macos-arm64")

  ## Platform Targets

  - Linux: "linux-x64", "linux-arm64", "linux-armv7"
  - macOS: "macos-x64", "macos-arm64"
  - Windows: "windows-x64.exe"
  - FreeBSD: "freebsd-x64", "freebsd-arm64"

  """
  @spec build_download_url(url_template()) :: String.t()
  def build_download_url(base_url \\ get_base_url()) do
    base_url
    |> String.replace("$version", get_version())
    |> String.replace("$target", get_target())
  end

  @doc """
  Gets application configuration value.

  Retrieves configuration values from the `:tailwind_port` application
  with optional default values.

  ## Parameters

    * `key` - Configuration key (atom)
    * `default` - Default value if key not found

  ## Returns

    * `config_value()` - Configuration value or default

  ## Examples

      # Get version with default
      version = ConfigManager.get_config(:version, "3.4.0")

      # Get path configuration
      path = ConfigManager.get_config(:path)
      # => nil (if not configured)

      # Get URL with default
      url = ConfigManager.get_config(:url, "https://default.example.com")

  """
  @spec get_config(atom(), config_value()) :: config_value()
  def get_config(key, default \\ nil) do
    Application.get_env(:tailwind_port, key, default)
  end

  @doc """
  Sets application configuration value.

  Updates configuration values for the `:tailwind_port` application.
  Useful for testing or runtime configuration changes.

  ## Parameters

    * `key` - Configuration key (atom)
    * `value` - Value to set

  ## Returns

    * `:ok` - Configuration updated successfully

  ## Examples

      # Set version
      ConfigManager.set_config(:version, "3.3.0")

      # Set custom path
      ConfigManager.set_config(:path, "/custom/bin/tailwindcss")

  ## Note

  Configuration changes only affect the current application instance
  and are not persisted across restarts.

  """
  @spec set_config(atom(), config_value()) :: :ok
  def set_config(key, value) do
    Application.put_env(:tailwind_port, key, value)
  end

  @doc """
  Gets the platform-specific target identifier.

  Returns the target identifier used in download URLs for the current platform.
  This delegates to BinaryManager for platform detection.

  ## Returns

    * `String.t()` - Platform target identifier

  ## Examples

      # On Linux x64
      ConfigManager.get_target()
      # => "linux-x64"

      # On macOS ARM64
      ConfigManager.get_target()
      # => "macos-arm64"

      # On Windows x64
      ConfigManager.get_target()
      # => "windows-x64.exe"

  """
  @spec get_target() :: String.t()
  def get_target do
    BinaryManager.get_target()
  end

  @doc """
  Gets the latest known Tailwind CSS version.

  Returns the latest version that was known at the time this module was created.
  This is used as a fallback when no version is configured.

  ## Returns

    * `String.t()` - Latest known version

  ## Examples

      ConfigManager.get_latest_version()
      # => "3.4.1"

  """
  @spec get_latest_version() :: String.t()
  def get_latest_version do
    @latest_version
  end

  @doc """
  Validates configuration completeness.

  Checks that all required configuration is present and valid.
  Returns a list of configuration issues or an empty list if valid.

  ## Returns

    * `[String.t()]` - List of configuration issues (empty if valid)

  ## Examples

      # Valid configuration
      ConfigManager.validate_config()
      # => []

      # Invalid configuration
      ConfigManager.validate_config()
      # => ["Invalid version format", "Binary path not accessible"]

  """
  @spec validate_config() :: [String.t()]
  def validate_config do
    issues = []

    # Validate version format
    issues =
      if valid_version?(get_version()), do: issues, else: ["Invalid version format" | issues]

    # Validate binary path accessibility
    binary_path = get_binary_path()

    issues =
      if valid_binary_path?(binary_path),
        do: issues,
        else: ["Binary path not accessible" | issues]

    # Validate URL format
    base_url = get_base_url()
    issues = if valid_url_template?(base_url), do: issues, else: ["Invalid URL template" | issues]

    Enum.reverse(issues)
  end

  # Private helper functions

  defp valid_version?(version) when is_binary(version) do
    Regex.match?(~r/^\d+\.\d+\.\d+/, version)
  end

  defp valid_version?(_), do: false

  defp valid_binary_path?(path) when is_binary(path) do
    dir = Path.dirname(path)
    File.exists?(dir) or File.mkdir_p(dir) == :ok
  end

  defp valid_binary_path?(_), do: false

  defp valid_url_template?(url) when is_binary(url) do
    String.contains?(url, "$version") and String.contains?(url, "$target")
  end

  defp valid_url_template?(_), do: false
end
