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

  describe "download functionality" do
    setup do
      # Create a temporary directory for testing
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "tailwind_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_dir)
      
      on_exit(fn ->
        File.rm_rf(test_dir)
      end)
      
      %{test_dir: test_dir}
    end

    @tag :capture_log
    test "download with invalid URL returns error", %{test_dir: test_dir} do
      test_file = Path.join(test_dir, "tailwindcss")
      
      # Test with invalid URL that will fail
      assert {:error, _reason} = TailwindDownload.download(test_file, "http://invalid-url-that-does-not-exist.example")
    end

    @tag :capture_log
    test "download fails with invalid URL", %{test_dir: test_dir} do
      nested_path = Path.join([test_dir, "nested", "path", "tailwindcss"])
      parent_dir = Path.dirname(nested_path)
      
      # Ensure the parent directory doesn't exist initially
      refute File.dir?(parent_dir)
      
      # This should fail to download due to invalid URL
      {:error, _reason} = TailwindDownload.download(nested_path, "http://invalid-url.example")
      
      # Directory should NOT be created since download fails before ensure_directory is called
      refute File.dir?(parent_dir)
    end

    @tag :capture_log
    test "download validates arguments", %{test_dir: _test_dir} do
      # Test invalid path argument
      assert {:error, :invalid_path} = TailwindDownload.download(123, "http://example.com")
      
      # Test invalid URL argument
      assert {:error, :invalid_url} = TailwindDownload.download("/tmp/test", 456)
      
      # Test empty path
      assert {:error, :empty_path} = TailwindDownload.download("", "http://example.com")
      
      # Test empty URL
      assert {:error, :empty_url} = TailwindDownload.download("/tmp/test", "")
      
      # Test nil path
      assert {:error, :invalid_path} = TailwindDownload.download(nil, "http://example.com")
      
      # Test nil URL
      assert {:error, :invalid_url} = TailwindDownload.download("/tmp/test", nil)
    end

    @tag :capture_log
    test "download with invalid URL" do
      _test_dir = System.tmp_dir!()
      binary_path = Path.join(System.tmp_dir!(), "test_tailwind")
      
      # Test with invalid URL
      result = TailwindDownload.download(binary_path, "not-a-valid-url")
      assert {:error, _} = result
    end

    @tag :capture_log
    test "download with unreachable URL" do
      binary_path = Path.join(System.tmp_dir!(), "test_tailwind_unreachable")
      
      # Test with unreachable URL
      result = TailwindDownload.download(binary_path, "http://nonexistent.invalid/file")
      assert {:error, _} = result
    end

    @tag :capture_log
    test "download handles malformed URLs", %{test_dir: test_dir} do
      test_file = Path.join(test_dir, "tailwindcss")
      
      # Test malformed URL
      result = TailwindDownload.download(test_file, "not-a-url")
      assert {:error, _} = result
    end
end

describe "TailwindDownload public functions" do
  test "configured_version returns configured version" do
    version = TailwindDownload.configured_version()
    assert is_binary(version)
  end

  test "default_base_url returns default base URL" do
    url = TailwindDownload.default_base_url()
    assert is_binary(url)
    assert String.starts_with?(url, "https://")
  end

  test "download with various error conditions" do
    binary_path = Path.join(System.tmp_dir!(), "test_error_conditions")
    
    # Test with malformed URL to trigger parse_url error path
    result = TailwindDownload.download(binary_path, "ftp://invalid-scheme.com/file")
    assert {:error, _} = result
    
    # Test with empty string URL
    result = TailwindDownload.download(binary_path, "")
    assert {:error, _} = result
  end
end

describe "TailwindDownload install edge cases" do
  setup do
    test_dir = System.tmp_dir!() |> Path.join("install_test_#{:rand.uniform(10000)}")
    File.mkdir_p!(test_dir)
    
    on_exit(fn ->
      if File.exists?(test_dir) do
        File.rm_rf!(test_dir)
      end
    end)
    
    %{test_dir: test_dir}
  end

  test "install with custom options", %{test_dir: test_dir} do
    binary_path = Path.join(test_dir, "custom_tailwind")
    
    # This will likely fail due to network/binary issues, but tests the code path
    result = TailwindDownload.install(binary_path, version: "3.0.0")
    # We expect this to fail in test environment, but it exercises the code
    assert match?({:error, _}, result)
  end

  test "install validates binary path", %{test_dir: _test_dir} do
    # Test with invalid binary path
    result = TailwindDownload.install("")
    assert {:error, _} = result
  end

  test "install with invalid base_url", %{test_dir: test_dir} do
    binary_path = Path.join(test_dir, "tailwind_invalid_url")
    
    # Test with invalid base URL
    result = TailwindDownload.install(binary_path, base_url: "not-a-valid-url")
    assert {:error, _} = result
  end

  test "install with malformed URL template", %{test_dir: test_dir} do
    binary_path = Path.join(test_dir, "tailwind_malformed")
    
    # Test with malformed URL template
    result = TailwindDownload.install(binary_path, base_url: "ftp://invalid.com/file")
    assert {:error, _} = result
  end
end

  describe "configuration" do
    test "configured_version respects application config" do
      # Test default version
      default_version = TailwindDownload.configured_version()
      assert is_binary(default_version)
      
      # Test with custom config
      original_version = Application.get_env(:tailwind_port, :version)
      
      try do
        Application.put_env(:tailwind_port, :version, "3.3.0")
        assert TailwindDownload.configured_version() == "3.3.0"
      after
        if original_version do
          Application.put_env(:tailwind_port, :version, original_version)
        else
          Application.delete_env(:tailwind_port, :version)
        end
      end
    end

    test "default_base_url respects application config" do
      # Test default URL
      default_url = TailwindDownload.default_base_url()
      assert is_binary(default_url)
      assert String.contains?(default_url, "$version")
      assert String.contains?(default_url, "$target")
      
      # Test with custom config
      original_url = Application.get_env(:tailwind_port, :url)
      custom_url = "https://custom.example.com/v$version/tailwindcss-$target"
      
      try do
        Application.put_env(:tailwind_port, :url, custom_url)
        assert TailwindDownload.default_base_url() == custom_url
      after
        if original_url do
          Application.put_env(:tailwind_port, :url, original_url)
        else
          Application.delete_env(:tailwind_port, :url)
        end
      end
    end
  end

  # Note: We don't test actual download functionality in unit tests
  # as it requires network access and would be slow/unreliable
end
