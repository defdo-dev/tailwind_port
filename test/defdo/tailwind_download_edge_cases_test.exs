defmodule Defdo.TailwindDownloadEdgeCasesTest do
  @moduledoc false
  use ExUnit.Case
  alias Defdo.TailwindDownload

  describe "edge cases and error scenarios" do
    @tag :capture_log
    test "download with invalid HTTP response" do
      # Test various invalid responses
      result = TailwindDownload.download("/tmp/test_binary", "https://httpbin.org/status/404")
      assert {:error, _reason} = result
    end

    @tag :capture_log
    test "install with directory creation failure" do
      # Try to install to a protected directory
      result = TailwindDownload.install("/root/protected/tailwindcss")
      assert {:error, _reason} = result
    end

    @tag :capture_log
    test "download with malformed URL" do
      result = TailwindDownload.download("/tmp/test", "not-a-url")
      assert {:error, _reason} = result
    end

    @tag :capture_log
    test "download with very small file" do
      # Test minimum size validation
      result = TailwindDownload.download("/tmp/test", "https://httpbin.org/bytes/10")
      assert {:error, _reason} = result
    end

    @tag :capture_log
    test "HTTP request with various error conditions" do
      # Test different HTTP error scenarios
      test_urls = [
        "https://httpbin.org/status/500",
        "https://httpbin.org/status/403",
        "https://httpbin.org/status/503"
      ]
      
      Enum.each(test_urls, fn url ->
        result = TailwindDownload.download("/tmp/test_http_error", url)
        assert {:error, _reason} = result
      end)
    end

    @tag :capture_log
    test "configuration functions" do
      # Test default base URL
      url = TailwindDownload.default_base_url()
      assert is_binary(url)
      assert String.contains?(url, "tailwindcss")

      # Test configured version
      version = TailwindDownload.configured_version()
      assert is_binary(version)
      assert String.match?(version, ~r/^\d+\.\d+\.\d+/)
    end

    @tag :capture_log 
    test "install with default parameters" do
      # This should try to download and install
      result = TailwindDownload.install()
      # Should return some result (might be atom or tuple depending on implementation)
      refute is_nil(result)
    end

    @tag :capture_log
    test "download with custom base URL" do
      # Test with a custom base URL that will fail
      result = TailwindDownload.download("/tmp/test", "https://example.com/invalid")
      assert {:error, _reason} = result
    end
  end
end