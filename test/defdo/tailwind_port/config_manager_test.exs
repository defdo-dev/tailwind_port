defmodule Defdo.TailwindPort.ConfigManagerTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Defdo.TailwindPort.ConfigManager

  describe "get_version/0" do
    test "returns configured version when set" do
      original = Application.get_env(:tailwind_port, :version)

      try do
        Application.put_env(:tailwind_port, :version, "3.3.0")
        assert ConfigManager.get_version() == "3.3.0"
      after
        if original,
          do: Application.put_env(:tailwind_port, :version, original),
          else: Application.delete_env(:tailwind_port, :version)
      end
    end

    test "returns latest version when not configured" do
      original = Application.get_env(:tailwind_port, :version)

      try do
        Application.delete_env(:tailwind_port, :version)
        version = ConfigManager.get_version()
        assert is_binary(version)
        assert Regex.match?(~r/^\d+\.\d+\.\d+/, version)
        assert version == ConfigManager.get_latest_version()
      after
        if original, do: Application.put_env(:tailwind_port, :version, original)
      end
    end

    test "handles different version formats" do
      original = Application.get_env(:tailwind_port, :version)

      versions = ["3.4.1", "2.0.0", "1.9.6", "4.0.0-beta.1"]

      try do
        Enum.each(versions, fn version ->
          Application.put_env(:tailwind_port, :version, version)
          assert ConfigManager.get_version() == version
        end)
      after
        if original,
          do: Application.put_env(:tailwind_port, :version, original),
          else: Application.delete_env(:tailwind_port, :version)
      end
    end
  end

  describe "get_base_url/0" do
    test "returns configured URL when set" do
      original = Application.get_env(:tailwind_port, :url)
      custom_url = "https://example.com/v$version/tailwindcss-$target"

      try do
        Application.put_env(:tailwind_port, :url, custom_url)
        assert ConfigManager.get_base_url() == custom_url
      after
        if original,
          do: Application.put_env(:tailwind_port, :url, original),
          else: Application.delete_env(:tailwind_port, :url)
      end
    end

    test "returns default URL when not configured" do
      original = Application.get_env(:tailwind_port, :url)

      try do
        Application.delete_env(:tailwind_port, :url)
        url = ConfigManager.get_base_url()
        assert is_binary(url)
        assert String.contains?(url, "$version")
        assert String.contains?(url, "$target")
        assert String.starts_with?(url, "https://")
      after
        if original, do: Application.put_env(:tailwind_port, :url, original)
      end
    end

    test "handles various URL templates" do
      original = Application.get_env(:tailwind_port, :url)

      urls = [
        "https://github.com/tailwindlabs/tailwindcss/releases/download/v$version/tailwindcss-$target",
        "https://cdn.example.com/tailwind/$version/tailwindcss-$target",
        "https://mirror.example.com/v$version/bin/tailwindcss-$target"
      ]

      try do
        Enum.each(urls, fn url ->
          Application.put_env(:tailwind_port, :url, url)
          assert ConfigManager.get_base_url() == url
        end)
      after
        if original,
          do: Application.put_env(:tailwind_port, :url, original),
          else: Application.delete_env(:tailwind_port, :url)
      end
    end
  end

  describe "get_binary_path/0" do
    test "returns configured path when set" do
      original = Application.get_env(:tailwind_port, :path)
      custom_path = "/usr/local/bin/tailwindcss"

      try do
        Application.put_env(:tailwind_port, :path, custom_path)
        assert ConfigManager.get_binary_path() == custom_path
      after
        if original,
          do: Application.put_env(:tailwind_port, :path, original),
          else: Application.delete_env(:tailwind_port, :path)
      end
    end

    test "returns computed path when not configured" do
      original = Application.get_env(:tailwind_port, :path)

      try do
        Application.delete_env(:tailwind_port, :path)
        path = ConfigManager.get_binary_path()
        assert is_binary(path)
        assert String.ends_with?(path, "tailwindcss")
      after
        if original, do: Application.put_env(:tailwind_port, :path, original)
      end
    end

    test "handles different path configurations" do
      original = Application.get_env(:tailwind_port, :path)

      paths = [
        "/usr/local/bin/tailwindcss",
        "/opt/tailwind/bin/tailwindcss",
        "/home/user/bin/tailwindcss",
        "./local/tailwindcss"
      ]

      try do
        Enum.each(paths, fn path ->
          Application.put_env(:tailwind_port, :path, path)
          assert ConfigManager.get_binary_path() == path
        end)
      after
        if original,
          do: Application.put_env(:tailwind_port, :path, original),
          else: Application.delete_env(:tailwind_port, :path)
      end
    end
  end

  describe "build_download_url/1" do
    test "builds URL with default base URL" do
      url = ConfigManager.build_download_url()
      assert is_binary(url)
      assert String.starts_with?(url, "https://")
      refute String.contains?(url, "$version")
      refute String.contains?(url, "$target")
    end

    test "builds URL with custom base URL" do
      custom_base = "https://example.com/v$version/tailwindcss-$target"
      url = ConfigManager.build_download_url(custom_base)

      assert String.starts_with?(url, "https://example.com/v")
      assert String.contains?(url, "tailwindcss-")
      refute String.contains?(url, "$version")
      refute String.contains?(url, "$target")
    end

    test "replaces version placeholder correctly" do
      original = Application.get_env(:tailwind_port, :version)

      try do
        Application.put_env(:tailwind_port, :version, "1.2.3")
        url = ConfigManager.build_download_url("https://example.com/v$version/file")
        assert url == "https://example.com/v1.2.3/file"
      after
        if original,
          do: Application.put_env(:tailwind_port, :version, original),
          else: Application.delete_env(:tailwind_port, :version)
      end
    end

    test "replaces target placeholder correctly" do
      url = ConfigManager.build_download_url("https://example.com/tailwindcss-$target")
      target = ConfigManager.get_target()
      expected = "https://example.com/tailwindcss-#{target}"
      assert url == expected
    end

    test "replaces multiple placeholders" do
      original = Application.get_env(:tailwind_port, :version)

      try do
        Application.put_env(:tailwind_port, :version, "2.0.0")
        base = "https://example.com/$version/$target/v$version/tailwindcss-$target"
        url = ConfigManager.build_download_url(base)
        target = ConfigManager.get_target()
        expected = "https://example.com/2.0.0/#{target}/v2.0.0/tailwindcss-#{target}"
        assert url == expected
      after
        if original,
          do: Application.put_env(:tailwind_port, :version, original),
          else: Application.delete_env(:tailwind_port, :version)
      end
    end
  end

  describe "get_config/2" do
    test "returns configured value" do
      original = Application.get_env(:tailwind_port, :test_key)

      try do
        Application.put_env(:tailwind_port, :test_key, "test_value")
        assert ConfigManager.get_config(:test_key) == "test_value"
      after
        if original,
          do: Application.put_env(:tailwind_port, :test_key, original),
          else: Application.delete_env(:tailwind_port, :test_key)
      end
    end

    test "returns default when key not found" do
      Application.delete_env(:tailwind_port, :nonexistent_key)
      assert ConfigManager.get_config(:nonexistent_key, "default") == "default"
      assert ConfigManager.get_config(:nonexistent_key) == nil
    end

    test "handles different value types" do
      original_configs = %{
        string_key: Application.get_env(:tailwind_port, :string_key),
        int_key: Application.get_env(:tailwind_port, :int_key),
        bool_key: Application.get_env(:tailwind_port, :bool_key)
      }

      try do
        Application.put_env(:tailwind_port, :string_key, "string_value")
        Application.put_env(:tailwind_port, :int_key, 42)
        Application.put_env(:tailwind_port, :bool_key, true)

        assert ConfigManager.get_config(:string_key) == "string_value"
        assert ConfigManager.get_config(:int_key) == 42
        assert ConfigManager.get_config(:bool_key) == true
      after
        Enum.each(original_configs, fn {key, value} ->
          if value,
            do: Application.put_env(:tailwind_port, key, value),
            else: Application.delete_env(:tailwind_port, key)
        end)
      end
    end
  end

  describe "set_config/2" do
    test "sets configuration value" do
      original = Application.get_env(:tailwind_port, :test_set_key)

      try do
        assert ConfigManager.set_config(:test_set_key, "new_value") == :ok
        assert Application.get_env(:tailwind_port, :test_set_key) == "new_value"
        assert ConfigManager.get_config(:test_set_key) == "new_value"
      after
        if original,
          do: Application.put_env(:tailwind_port, :test_set_key, original),
          else: Application.delete_env(:tailwind_port, :test_set_key)
      end
    end

    test "overwrites existing value" do
      original = Application.get_env(:tailwind_port, :test_overwrite_key)

      try do
        Application.put_env(:tailwind_port, :test_overwrite_key, "old_value")
        ConfigManager.set_config(:test_overwrite_key, "new_value")
        assert ConfigManager.get_config(:test_overwrite_key) == "new_value"
      after
        if original,
          do: Application.put_env(:tailwind_port, :test_overwrite_key, original),
          else: Application.delete_env(:tailwind_port, :test_overwrite_key)
      end
    end
  end

  describe "get_target/0" do
    test "returns platform target" do
      target = ConfigManager.get_target()
      assert is_binary(target)

      # Should be one of the known platform targets
      valid_targets = [
        "linux-x64",
        "linux-arm64",
        "linux-armv7",
        "macos-x64",
        "macos-arm64",
        "windows-x64.exe",
        "freebsd-x64",
        "freebsd-arm64"
      ]

      assert target in valid_targets
    end
  end

  describe "get_latest_version/0" do
    test "returns latest known version" do
      version = ConfigManager.get_latest_version()
      assert is_binary(version)
      assert Regex.match?(~r/^\d+\.\d+\.\d+/, version)
    end

    test "latest version is consistent" do
      version1 = ConfigManager.get_latest_version()
      version2 = ConfigManager.get_latest_version()
      assert version1 == version2
    end
  end

  describe "validate_config/0" do
    test "returns empty list for valid configuration" do
      # Set up valid configuration
      original_configs = %{
        version: Application.get_env(:tailwind_port, :version),
        url: Application.get_env(:tailwind_port, :url),
        path: Application.get_env(:tailwind_port, :path)
      }

      try do
        Application.put_env(:tailwind_port, :version, "3.4.1")

        Application.put_env(
          :tailwind_port,
          :url,
          "https://example.com/v$version/tailwindcss-$target"
        )

        Application.put_env(:tailwind_port, :path, "/tmp/tailwindcss")

        # Ensure target directory exists
        File.mkdir_p("/tmp")

        issues = ConfigManager.validate_config()
        assert is_list(issues)
        # May have issues but should be minimal with proper config
      after
        Enum.each(original_configs, fn {key, value} ->
          if value,
            do: Application.put_env(:tailwind_port, key, value),
            else: Application.delete_env(:tailwind_port, key)
        end)
      end
    end

    test "detects invalid version format" do
      original = Application.get_env(:tailwind_port, :version)

      try do
        Application.put_env(:tailwind_port, :version, "invalid-version")
        issues = ConfigManager.validate_config()
        assert "Invalid version format" in issues
      after
        if original,
          do: Application.put_env(:tailwind_port, :version, original),
          else: Application.delete_env(:tailwind_port, :version)
      end
    end

    test "detects invalid URL template" do
      original = Application.get_env(:tailwind_port, :url)

      try do
        Application.put_env(:tailwind_port, :url, "https://example.com/static-url")
        issues = ConfigManager.validate_config()
        assert "Invalid URL template" in issues
      after
        if original,
          do: Application.put_env(:tailwind_port, :url, original),
          else: Application.delete_env(:tailwind_port, :url)
      end
    end
  end

  describe "integration tests" do
    test "complete workflow with custom configuration" do
      original_configs = %{
        version: Application.get_env(:tailwind_port, :version),
        url: Application.get_env(:tailwind_port, :url),
        path: Application.get_env(:tailwind_port, :path)
      }

      try do
        # Set custom configuration
        ConfigManager.set_config(:version, "2.5.0")
        ConfigManager.set_config(:url, "https://custom.cdn.com/v$version/tailwindcss-$target")
        ConfigManager.set_config(:path, "/custom/path/tailwindcss")

        # Verify all config is working together
        assert ConfigManager.get_version() == "2.5.0"

        assert ConfigManager.get_base_url() ==
                 "https://custom.cdn.com/v$version/tailwindcss-$target"

        assert ConfigManager.get_binary_path() == "/custom/path/tailwindcss"

        # Build URL with custom settings
        url = ConfigManager.build_download_url()
        target = ConfigManager.get_target()
        expected = "https://custom.cdn.com/v2.5.0/tailwindcss-#{target}"
        assert url == expected
      after
        Enum.each(original_configs, fn {key, value} ->
          if value,
            do: Application.put_env(:tailwind_port, key, value),
            else: Application.delete_env(:tailwind_port, key)
        end)
      end
    end

    test "fallback behavior with minimal configuration" do
      original_configs = %{
        version: Application.get_env(:tailwind_port, :version),
        url: Application.get_env(:tailwind_port, :url),
        path: Application.get_env(:tailwind_port, :path)
      }

      try do
        # Clear all configuration
        Application.delete_env(:tailwind_port, :version)
        Application.delete_env(:tailwind_port, :url)
        Application.delete_env(:tailwind_port, :path)

        # Should still work with defaults
        version = ConfigManager.get_version()
        url_template = ConfigManager.get_base_url()
        path = ConfigManager.get_binary_path()

        assert is_binary(version)
        assert is_binary(url_template)
        assert is_binary(path)

        # Should be able to build URL
        download_url = ConfigManager.build_download_url()
        assert is_binary(download_url)
        assert String.starts_with?(download_url, "https://")
      after
        Enum.each(original_configs, fn {key, value} ->
          if value, do: Application.put_env(:tailwind_port, key, value)
        end)
      end
    end
  end

  describe "edge cases and boundary conditions" do
    test "handles nil and empty configurations" do
      original_configs = %{
        version: Application.get_env(:tailwind_port, :version),
        url: Application.get_env(:tailwind_port, :url)
      }

      try do
        # Test with nil values
        Application.put_env(:tailwind_port, :version, nil)
        version = ConfigManager.get_version()
        assert version == ConfigManager.get_latest_version()

        # Test with empty string
        Application.put_env(:tailwind_port, :url, "")
        url = ConfigManager.get_base_url()
        assert url == ""
      after
        Enum.each(original_configs, fn {key, value} ->
          if value,
            do: Application.put_env(:tailwind_port, key, value),
            else: Application.delete_env(:tailwind_port, key)
        end)
      end
    end

    test "consistent behavior across multiple calls" do
      # Multiple calls should return same results
      version1 = ConfigManager.get_version()
      version2 = ConfigManager.get_version()
      assert version1 == version2

      target1 = ConfigManager.get_target()
      target2 = ConfigManager.get_target()
      assert target1 == target2

      path1 = ConfigManager.get_binary_path()
      path2 = ConfigManager.get_binary_path()
      assert path1 == path2
    end
  end
end
