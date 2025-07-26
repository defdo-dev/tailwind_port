defmodule Defdo.TailwindPort.HttpClient do
  @moduledoc """
  HTTP client functionality for secure binary downloads.

  This module provides a secure, configurable HTTP client designed specifically
  for downloading Tailwind CSS binaries. It includes comprehensive security
  features, proxy support, and proper error handling.

  ## Features

  - **Security**: HTTPS with certificate verification and hostname validation
  - **Proxy Support**: HTTP/HTTPS proxy support with authentication
  - **Error Handling**: Comprehensive error reporting with specific failure reasons
  - **Configuration**: Configurable TLS versions and certificate sources
  - **Validation**: URL validation and scheme verification

  ## Security Features

  - **Certificate Verification**: Full certificate chain validation
  - **Hostname Verification**: Proper hostname checking against certificates
  - **TLS Version Control**: Support for TLS 1.2 and 1.3 based on OTP version
  - **Proxy Authentication**: Secure proxy authentication when required

  ## Configuration

  ### Certificate Configuration

      config :tailwind_port, cacerts_path: "/path/to/cacerts.pem"

  ### Proxy Configuration

  The client automatically detects proxy settings from environment variables:

  - `HTTP_PROXY` or `http_proxy` - HTTP proxy URL
  - `HTTPS_PROXY` or `https_proxy` - HTTPS proxy URL

  Proxy URLs support authentication: `http://user:pass@proxy.example.com:8080`

  ## Usage

      # Download binary from URL
      case HttpClient.fetch_binary("https://example.com/tailwindcss") do
        {:ok, binary} -> process_binary(binary)
        {:error, reason} -> handle_error(reason)
      end

      # With proxy support
      System.put_env("HTTPS_PROXY", "https://proxy.example.com:8080")
      {:ok, binary} = HttpClient.fetch_binary("https://example.com/file")

  ## Error Handling

  All functions return detailed error information:

      case HttpClient.fetch_binary(url) do
        {:ok, binary} ->
          :ok
        {:error, :invalid_url} ->
          Logger.error("URL format is invalid")
        {:error, {:http_error, 404}} ->
          Logger.error("File not found")
        {:error, {:request_failed, :timeout}} ->
          Logger.error("Network request timed out")
      end

  """

  require Logger

  @typedoc "HTTP response binary data"
  @type binary_data :: binary()

  @typedoc "HTTP error reasons"
  @type error_reason ::
          :invalid_url
          | {:app_start_failed, term()}
          | :invalid_proxy_url
          | {:http_error, non_neg_integer()}
          | {:request_failed, term()}

  @doc """
  Fetches binary data from the specified URL.

  This function downloads binary data from a URL with full security validation,
  proxy support, and comprehensive error handling. It's designed for downloading
  executable binaries securely.

  ## Parameters

    * `url` - URL to download from (must be HTTP or HTTPS)

  ## Returns

    * `{:ok, binary()}` - Download successful with binary data
    * `{:error, error_reason()}` - Download failed with specific error

  ## Examples

      # Basic download
      case HttpClient.fetch_binary("https://example.com/file.bin") do
        {:ok, data} ->
          IO.puts("Downloaded successfully")
        {:error, error} ->
          Logger.error("Download failed")
      end

      # Handle specific errors
      case HttpClient.fetch_binary(url) do
        {:ok, data} ->
          process_data(data)
        {:error, {:http_error, 404}} ->
          Logger.error("File not found at URL")
        {:error, :invalid_url} ->
          Logger.error("Invalid URL format")
        {:error, {:request_failed, :timeout}} ->
          Logger.error("Download timed out")
      end

  ## Security Features

  - HTTPS certificate verification with full chain validation
  - Hostname verification against certificate
  - TLS 1.2/1.3 support based on OTP version
  - Proxy authentication support

  ## Proxy Support

  Automatically detects and uses proxy settings from environment:
  - HTTP_PROXY/http_proxy for HTTP URLs
  - HTTPS_PROXY/https_proxy for HTTPS URLs
  - Supports proxy authentication via URL credentials

  """
  @spec fetch_binary(String.t()) :: {:ok, binary_data()} | {:error, error_reason()}
  def fetch_binary(url) when is_binary(url) do
    with {:ok, parsed_url} <- parse_url(url),
         :ok <- ensure_http_apps(),
         :ok <- setup_proxy(parsed_url.scheme),
         {:ok, response} <- make_http_request(url) do
      {:ok, response}
    end
  end

  @doc """
  Parses and validates a URL for HTTP requests.

  ## Parameters

    * `url` - URL string to parse and validate

  ## Returns

    * `{:ok, URI.t()}` - Valid HTTP/HTTPS URL
    * `{:error, :invalid_url}` - Invalid or unsupported URL

  """
  @spec parse_url(String.t()) :: {:ok, URI.t()} | {:error, :invalid_url}
  def parse_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> {:ok, URI.parse(url)}
      _ -> {:error, :invalid_url}
    end
  end

  @doc """
  Ensures required HTTP applications are started.

  ## Returns

    * `:ok` - Applications started successfully
    * `{:error, {:app_start_failed, reason}}` - Failed to start applications

  """
  @spec ensure_http_apps() :: :ok | {:error, {:app_start_failed, term()}}
  def ensure_http_apps do
    with {:ok, _} <- Application.ensure_all_started(:inets),
         {:ok, _} <- Application.ensure_all_started(:ssl) do
      :ok
    else
      {:error, reason} -> {:error, {:app_start_failed, reason}}
    end
  end

  @doc """
  Sets up proxy configuration for the specified scheme.

  ## Parameters

    * `scheme` - URL scheme ("http" or "https")

  ## Returns

    * `:ok` - Proxy configured successfully or no proxy needed
    * `{:error, :invalid_proxy_url}` - Proxy URL is malformed

  """
  @spec setup_proxy(String.t()) :: :ok | {:error, :invalid_proxy_url}
  def setup_proxy(scheme) do
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

  @doc """
  Makes an HTTP request with full security configuration.

  ## Parameters

    * `url` - URL to request

  ## Returns

    * `{:ok, binary()}` - Request successful with response body
    * `{:error, error_reason()}` - Request failed

  """
  @spec make_http_request(String.t()) :: {:ok, binary_data()} | {:error, error_reason()}
  def make_http_request(url) do
    url_charlist = String.to_charlist(url)
    Logger.debug("Downloading binary from #{url}")

    # https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/inets
    cacertfile = get_cacertfile() |> String.to_charlist()
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
          versions: get_protocol_versions()
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

  @doc """
  Gets the proxy URL for the specified scheme.

  ## Parameters

    * `scheme` - URL scheme ("http" or "https")

  ## Returns

    * `String.t() | nil` - Proxy URL or nil if no proxy configured

  """
  @spec proxy_for_scheme(String.t()) :: String.t() | nil
  def proxy_for_scheme("http") do
    System.get_env("HTTP_PROXY") || System.get_env("http_proxy")
  end

  def proxy_for_scheme("https") do
    System.get_env("HTTPS_PROXY") || System.get_env("https_proxy")
  end

  @doc """
  Gets the path to the CA certificate file.

  ## Returns

    * `String.t()` - Path to CA certificate file

  """
  @spec get_cacertfile() :: String.t()
  def get_cacertfile do
    Application.get_env(:tailwind_port, :cacerts_path) || CAStore.file_path()
  end

  @doc """
  Gets supported TLS protocol versions based on OTP version.

  ## Returns

    * `[atom()]` - List of supported TLS versions

  """
  @spec get_protocol_versions() :: [atom()]
  def get_protocol_versions do
    if get_otp_version() < 25, do: [:"tlsv1.2"], else: [:"tlsv1.2", :"tlsv1.3"]
  end

  @doc """
  Gets the current OTP version.

  ## Returns

    * `integer()` - OTP version number

  """
  @spec get_otp_version() :: integer()
  def get_otp_version do
    :erlang.system_info(:otp_release) |> List.to_integer()
  end

  # Private helper functions

  defp maybe_add_proxy_auth(http_options, scheme) do
    case get_proxy_auth(scheme) do
      nil -> http_options
      auth -> [{:proxy_auth, auth} | http_options]
    end
  end

  defp get_proxy_auth(scheme) do
    with proxy when is_binary(proxy) <- proxy_for_scheme(scheme),
         %{userinfo: userinfo} when is_binary(userinfo) <- URI.parse(proxy),
         [username, password] <- String.split(userinfo, ":") do
      {String.to_charlist(username), String.to_charlist(password)}
    else
      _ -> nil
    end
  end
end
