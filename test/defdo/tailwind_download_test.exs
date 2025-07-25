defmodule Defdo.TailwindDownloadTest do
  @moduledoc false
  use ExUnit.Case
  alias Defdo.TailwindDownload

  @tag :capture_log
  test "configured_version/0 returns version" do
    version = TailwindDownload.configured_version()
    assert is_binary(version)
    assert String.match?(version, ~r/^\d+\.\d+\.\d+/)
  end

  @tag :capture_log
  test "default_base_url/0 returns url" do
    url = TailwindDownload.default_base_url()
    assert is_binary(url)
    assert String.contains?(url, "$version")
    assert String.contains?(url, "$target")
  end

  @tag :capture_log
  test "download validation with invalid arguments" do
    # Test invalid path
    assert {:error, :invalid_path} = TailwindDownload.download(123, "http://example.com")
    assert {:error, :empty_path} = TailwindDownload.download("", "http://example.com")

    # Test invalid URL
    assert {:error, :invalid_url} = TailwindDownload.download("/tmp/test", 123)
    assert {:error, :empty_url} = TailwindDownload.download("/tmp/test", "")
  end

  @tag :capture_log  
  test "install validation with invalid arguments" do
    # Test with invalid arguments
    assert {:error, :invalid_path} = TailwindDownload.install(123, "http://example.com")
    assert {:error, :invalid_url} = TailwindDownload.install("/tmp/test", 123)
  end

  # Note: We don't test actual download functionality in unit tests
  # as it requires network access and would be slow/unreliable
end