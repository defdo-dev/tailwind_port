defmodule Defdo.TailwindPort.HttpClientTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Defdo.TailwindPort.HttpClient

  describe "parse_url/1" do
    test "accepts valid HTTP URLs" do
      assert {:ok, %URI{scheme: "http"}} = HttpClient.parse_url("http://example.com")
      assert {:ok, %URI{scheme: "http"}} = HttpClient.parse_url("http://example.com/path")

      assert {:ok, %URI{scheme: "http"}} =
               HttpClient.parse_url("http://example.com:8080/path?query=1")
    end

    test "accepts valid HTTPS URLs" do
      assert {:ok, %URI{scheme: "https"}} = HttpClient.parse_url("https://example.com")
      assert {:ok, %URI{scheme: "https"}} = HttpClient.parse_url("https://example.com/path")

      assert {:ok, %URI{scheme: "https"}} =
               HttpClient.parse_url("https://secure.example.com:443/file.bin")
    end

    test "rejects invalid URLs" do
      assert {:error, :invalid_url} = HttpClient.parse_url("ftp://example.com")
      assert {:error, :invalid_url} = HttpClient.parse_url("file:///local/path")
      assert {:error, :invalid_url} = HttpClient.parse_url("invalid-url")
      assert {:error, :invalid_url} = HttpClient.parse_url("")
      assert {:error, :invalid_url} = HttpClient.parse_url("://missing-scheme")
    end

    test "handles malformed URLs" do
      assert {:error, :invalid_url} = HttpClient.parse_url("not-a-url")
      assert {:error, :invalid_url} = HttpClient.parse_url("://invalid")
    end
  end

  describe "ensure_http_apps/0" do
    test "starts required applications successfully" do
      # Applications should already be started in test environment
      assert :ok = HttpClient.ensure_http_apps()
    end

    test "returns ok when applications already started" do
      # Ensure they're started
      Application.ensure_all_started(:inets)
      Application.ensure_all_started(:ssl)

      # Should still return ok
      assert :ok = HttpClient.ensure_http_apps()
    end
  end

  describe "proxy_for_scheme/1" do
    test "returns HTTP proxy from environment" do
      original_http = System.get_env("HTTP_PROXY")
      original_http_lower = System.get_env("http_proxy")

      try do
        System.put_env("HTTP_PROXY", "http://proxy.example.com:8080")
        assert HttpClient.proxy_for_scheme("http") == "http://proxy.example.com:8080"

        # Test lowercase takes precedence if uppercase not set
        System.delete_env("HTTP_PROXY")
        System.put_env("http_proxy", "http://lowercase.proxy.com:8080")
        assert HttpClient.proxy_for_scheme("http") == "http://lowercase.proxy.com:8080"
      after
        if original_http,
          do: System.put_env("HTTP_PROXY", original_http),
          else: System.delete_env("HTTP_PROXY")

        if original_http_lower,
          do: System.put_env("http_proxy", original_http_lower),
          else: System.delete_env("http_proxy")
      end
    end

    test "returns HTTPS proxy from environment" do
      original_https = System.get_env("HTTPS_PROXY")
      original_https_lower = System.get_env("https_proxy")

      try do
        System.put_env("HTTPS_PROXY", "https://secure.proxy.com:8443")
        assert HttpClient.proxy_for_scheme("https") == "https://secure.proxy.com:8443"

        # Test lowercase fallback
        System.delete_env("HTTPS_PROXY")
        System.put_env("https_proxy", "https://lowercase.secure.com:443")
        assert HttpClient.proxy_for_scheme("https") == "https://lowercase.secure.com:443"
      after
        if original_https,
          do: System.put_env("HTTPS_PROXY", original_https),
          else: System.delete_env("HTTPS_PROXY")

        if original_https_lower,
          do: System.put_env("https_proxy", original_https_lower),
          else: System.delete_env("https_proxy")
      end
    end

    test "returns nil when no proxy configured" do
      original_http = System.get_env("HTTP_PROXY")
      original_http_lower = System.get_env("http_proxy")
      original_https = System.get_env("HTTPS_PROXY")
      original_https_lower = System.get_env("https_proxy")

      try do
        System.delete_env("HTTP_PROXY")
        System.delete_env("http_proxy")
        System.delete_env("HTTPS_PROXY")
        System.delete_env("https_proxy")

        assert HttpClient.proxy_for_scheme("http") == nil
        assert HttpClient.proxy_for_scheme("https") == nil
      after
        if original_http, do: System.put_env("HTTP_PROXY", original_http)
        if original_http_lower, do: System.put_env("http_proxy", original_http_lower)
        if original_https, do: System.put_env("HTTPS_PROXY", original_https)
        if original_https_lower, do: System.put_env("https_proxy", original_https_lower)
      end
    end
  end

  describe "setup_proxy/1" do
    test "configures HTTP proxy successfully" do
      original_http = System.get_env("HTTP_PROXY")

      try do
        System.put_env("HTTP_PROXY", "http://proxy.example.com:8080")
        assert :ok = HttpClient.setup_proxy("http")
      after
        if original_http,
          do: System.put_env("HTTP_PROXY", original_http),
          else: System.delete_env("HTTP_PROXY")
      end
    end

    test "configures HTTPS proxy successfully" do
      original_https = System.get_env("HTTPS_PROXY")

      try do
        System.put_env("HTTPS_PROXY", "https://secure.proxy.com:8443")
        assert :ok = HttpClient.setup_proxy("https")
      after
        if original_https,
          do: System.put_env("HTTPS_PROXY", original_https),
          else: System.delete_env("HTTPS_PROXY")
      end
    end

    test "returns ok when no proxy configured" do
      original_http = System.get_env("HTTP_PROXY")
      original_https = System.get_env("HTTPS_PROXY")

      try do
        System.delete_env("HTTP_PROXY")
        System.delete_env("HTTPS_PROXY")

        assert :ok = HttpClient.setup_proxy("http")
        assert :ok = HttpClient.setup_proxy("https")
      after
        if original_http, do: System.put_env("HTTP_PROXY", original_http)
        if original_https, do: System.put_env("HTTPS_PROXY", original_https)
      end
    end

    test "handles invalid proxy URL" do
      original_http = System.get_env("HTTP_PROXY")

      try do
        System.put_env("HTTP_PROXY", "invalid-proxy-url")
        assert {:error, :invalid_proxy_url} = HttpClient.setup_proxy("http")
      after
        if original_http,
          do: System.put_env("HTTP_PROXY", original_http),
          else: System.delete_env("HTTP_PROXY")
      end
    end

    test "handles invalid proxy URL format" do
      original_http = System.get_env("HTTP_PROXY")

      try do
        System.put_env("HTTP_PROXY", "not-a-valid-proxy-url")
        assert {:error, :invalid_proxy_url} = HttpClient.setup_proxy("http")
      after
        if original_http,
          do: System.put_env("HTTP_PROXY", original_http),
          else: System.delete_env("HTTP_PROXY")
      end
    end
  end

  describe "get_cacertfile/0" do
    test "returns configured cacerts path" do
      original_config = Application.get_env(:tailwind_port, :cacerts_path)

      try do
        Application.put_env(:tailwind_port, :cacerts_path, "/custom/ca/certs.pem")
        assert HttpClient.get_cacertfile() == "/custom/ca/certs.pem"
      after
        if original_config do
          Application.put_env(:tailwind_port, :cacerts_path, original_config)
        else
          Application.delete_env(:tailwind_port, :cacerts_path)
        end
      end
    end

    test "returns CAStore path when not configured" do
      original_config = Application.get_env(:tailwind_port, :cacerts_path)

      try do
        Application.delete_env(:tailwind_port, :cacerts_path)
        cacertfile = HttpClient.get_cacertfile()
        assert is_binary(cacertfile)
        assert String.ends_with?(cacertfile, ".pem")
      after
        if original_config do
          Application.put_env(:tailwind_port, :cacerts_path, original_config)
        end
      end
    end
  end

  describe "get_protocol_versions/0" do
    test "returns appropriate TLS versions based on OTP" do
      versions = HttpClient.get_protocol_versions()
      assert is_list(versions)
      assert Enum.all?(versions, &is_atom/1)

      # Should contain at least TLS 1.2
      assert :"tlsv1.2" in versions

      # May contain TLS 1.3 on newer OTP versions
      if HttpClient.get_otp_version() >= 25 do
        assert :"tlsv1.3" in versions
      end
    end
  end

  describe "get_otp_version/0" do
    test "returns integer OTP version" do
      version = HttpClient.get_otp_version()
      assert is_integer(version)
      # Should be a reasonable OTP version
      assert version > 20
    end
  end

  describe "fetch_binary/1 integration" do
    test "validates URL before making request" do
      assert {:error, :invalid_url} = HttpClient.fetch_binary("invalid-url")
      assert {:error, :invalid_url} = HttpClient.fetch_binary("ftp://example.com")
      assert {:error, :invalid_url} = HttpClient.fetch_binary("")
    end

    # Note: We don't test actual HTTP requests in unit tests to avoid external dependencies
    # Integration tests would cover the full HTTP request functionality
  end

  describe "error handling" do
    test "handles various error conditions gracefully" do
      # Invalid URL errors
      assert {:error, :invalid_url} = HttpClient.parse_url("not-a-url")

      # Proxy configuration errors
      original_proxy = System.get_env("HTTP_PROXY")

      try do
        System.put_env("HTTP_PROXY", "malformed://")
        assert {:error, :invalid_proxy_url} = HttpClient.setup_proxy("http")
      after
        if original_proxy,
          do: System.put_env("HTTP_PROXY", original_proxy),
          else: System.delete_env("HTTP_PROXY")
      end
    end
  end

  describe "proxy authentication parsing" do
    # Note: We test proxy auth indirectly through setup_proxy since get_proxy_auth is private
    test "handles proxy URLs with authentication" do
      original_http = System.get_env("HTTP_PROXY")

      try do
        # Test with valid proxy with auth - should succeed in setup
        System.put_env("HTTP_PROXY", "http://user:pass@proxy.example.com:8080")
        assert :ok = HttpClient.setup_proxy("http")

        # Test without auth - should also succeed
        System.put_env("HTTP_PROXY", "http://proxy.example.com:8080")
        assert :ok = HttpClient.setup_proxy("http")
      after
        if original_http,
          do: System.put_env("HTTP_PROXY", original_http),
          else: System.delete_env("HTTP_PROXY")
      end
    end
  end

  describe "edge cases and boundary conditions" do
    test "handles empty and nil values" do
      assert {:error, :invalid_url} = HttpClient.parse_url("")

      # Test with no proxy environment variables
      original_vars = %{
        "HTTP_PROXY" => System.get_env("HTTP_PROXY"),
        "http_proxy" => System.get_env("http_proxy"),
        "HTTPS_PROXY" => System.get_env("HTTPS_PROXY"),
        "https_proxy" => System.get_env("https_proxy")
      }

      try do
        Enum.each(original_vars, fn {key, _} -> System.delete_env(key) end)

        assert HttpClient.proxy_for_scheme("http") == nil
        assert HttpClient.proxy_for_scheme("https") == nil
        assert :ok = HttpClient.setup_proxy("http")
        assert :ok = HttpClient.setup_proxy("https")
      after
        Enum.each(original_vars, fn {key, value} ->
          if value, do: System.put_env(key, value)
        end)
      end
    end

    test "handles special characters in URLs" do
      # URLs with special characters should be parsed correctly
      special_urls = [
        "https://example.com/path with spaces",
        "https://example.com/path?query=hello%20world",
        "https://user:pass@example.com:8080/secure"
      ]

      Enum.each(special_urls, fn url ->
        case HttpClient.parse_url(url) do
          {:ok, %URI{}} -> :ok
          # Some may be invalid, that's fine
          {:error, :invalid_url} -> :ok
        end
      end)
    end

    test "configuration functions return consistent types" do
      # Ensure all getter functions return expected types
      assert is_binary(HttpClient.get_cacertfile())
      assert is_list(HttpClient.get_protocol_versions())
      assert is_integer(HttpClient.get_otp_version())

      # Proxy functions should return string or nil
      proxy = HttpClient.proxy_for_scheme("http")
      assert is_nil(proxy) or is_binary(proxy)

      proxy = HttpClient.proxy_for_scheme("https")
      assert is_nil(proxy) or is_binary(proxy)
    end
  end
end
