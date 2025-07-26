defmodule Defdo.TailwindPort.ValidationTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Defdo.TailwindPort.Validation

  describe "validate_start_args/1" do
    test "accepts valid keyword list arguments" do
      valid_args = [
        [],
        [name: :my_port],
        [opts: ["-i", "input.css"]],
        [name: :test, opts: ["-w"]],
        [cmd: "/usr/bin/tailwindcss"]
      ]

      Enum.each(valid_args, fn args ->
        assert :ok = Validation.validate_start_args(args), "Failed for: #{inspect(args)}"
      end)
    end

    test "rejects invalid name type" do
      invalid_name_args = [
        [name: "string_name"],
        [name: 123],
        [name: %{}]
      ]

      Enum.each(invalid_name_args, fn args ->
        assert {:error, :invalid_name} = Validation.validate_start_args(args)
      end)

      # nil is acceptable (means no name specified)
      assert :ok = Validation.validate_start_args(name: nil)
    end

    test "rejects invalid opts type" do
      invalid_opts_args = [
        [opts: "string_opts"],
        [opts: 123],
        [opts: %{}]
      ]

      Enum.each(invalid_opts_args, fn args ->
        assert {:error, :invalid_opts} = Validation.validate_start_args(args)
      end)

      # nil is acceptable (means no opts specified)
      assert :ok = Validation.validate_start_args(opts: nil)
    end

    test "rejects non-list arguments" do
      invalid_args = [
        "string",
        123,
        %{},
        nil,
        :atom
      ]

      Enum.each(invalid_args, fn args ->
        assert {:error, :invalid_args} = Validation.validate_start_args(args)
      end)
    end

    test "accepts mixed valid arguments" do
      assert :ok = Validation.validate_start_args(name: :test, opts: ["-w"], other_key: "ignored")
    end
  end

  describe "validate_port_args/1" do
    test "accepts valid port arguments" do
      valid_args = [
        [],
        [cmd: "/usr/bin/tailwindcss"],
        [opts: ["-i", "input.css", "-o", "output.css"]],
        [cmd: "/bin/tailwind", opts: ["-w"]],
        # Other keys are ignored
        [timeout: 5000]
      ]

      Enum.each(valid_args, fn args ->
        assert :ok = Validation.validate_port_args(args), "Failed for: #{inspect(args)}"
      end)
    end

    test "rejects invalid cmd type" do
      invalid_cmd_args = [
        [cmd: 123],
        [cmd: nil],
        [cmd: %{}],
        [cmd: :atom]
      ]

      Enum.each(invalid_cmd_args, fn args ->
        assert {:error, :invalid_cmd} = Validation.validate_port_args(args)
      end)
    end

    test "rejects invalid opts type" do
      invalid_opts_args = [
        [opts: "string"],
        [opts: 123],
        [opts: %{}],
        [opts: nil]
      ]

      Enum.each(invalid_opts_args, fn args ->
        assert {:error, :invalid_opts} = Validation.validate_port_args(args)
      end)
    end

    test "rejects non-list arguments" do
      invalid_args = [
        "string",
        123,
        %{cmd: "/bin/tailwind"},
        nil
      ]

      Enum.each(invalid_args, fn args ->
        assert {:error, :invalid_args} = Validation.validate_port_args(args)
      end)
    end
  end

  describe "validate_download_args/2" do
    test "accepts valid download arguments" do
      valid_combinations = [
        {"/tmp/binary", "https://example.com"},
        {"/usr/local/bin/tailwindcss", "http://localhost:3000"},
        {"./relative/path", "https://github.com/user/repo"},
        {"/path/with spaces/binary", "https://example.com/path"}
      ]

      Enum.each(valid_combinations, fn {path, url} ->
        assert :ok = Validation.validate_download_args(path, url)
      end)
    end

    test "rejects invalid path arguments" do
      invalid_paths = [
        nil,
        123,
        %{},
        "",
        # Only whitespace
        "   ",
        :atom
      ]

      Enum.each(invalid_paths, fn path ->
        result = Validation.validate_download_args(path, "https://example.com")
        assert {:error, :invalid_path} = result, "Should reject path: #{inspect(path)}"
      end)
    end

    test "rejects invalid URL arguments" do
      invalid_urls = [
        nil,
        123,
        %{},
        :atom,
        ["list", "of", "strings"]
      ]

      Enum.each(invalid_urls, fn url ->
        result = Validation.validate_download_args("/tmp/binary", url)
        assert {:error, :invalid_url} = result, "Should reject URL: #{inspect(url)}"
      end)
    end

    test "rejects empty URL" do
      empty_urls = [
        "",
        # Only whitespace
        "   ",
        # Only whitespace characters
        "\t\n"
      ]

      Enum.each(empty_urls, fn url ->
        assert {:error, :empty_url} = Validation.validate_download_args("/tmp/binary", url)
      end)
    end
  end

  describe "validate_config/1" do
    setup do
      # Create temporary config files for testing
      test_dir = "/tmp/validation_test_#{:rand.uniform(10000)}"
      File.mkdir_p!(test_dir)

      valid_config = "#{test_dir}/valid.config.js"
      File.write!(valid_config, "module.exports = { content: ['./src/**/*.js'] }")

      empty_config = "#{test_dir}/empty.config.js"
      File.write!(empty_config, "")

      invalid_config = "#{test_dir}/invalid.config.js"
      File.write!(invalid_config, "module.exports = { content: [")

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok,
       valid_config: valid_config,
       empty_config: empty_config,
       invalid_config: invalid_config,
       test_dir: test_dir}
    end

    test "accepts valid configuration file", %{valid_config: valid_config} do
      assert :ok = Validation.validate_config(valid_config)
    end

    test "rejects non-existent configuration file" do
      assert {:error, :config_not_found} = Validation.validate_config("/nonexistent/config.js")
    end

    test "rejects empty configuration file", %{empty_config: empty_config} do
      assert {:error, :empty_config} = Validation.validate_config(empty_config)
    end

    test "rejects configuration with syntax errors", %{invalid_config: invalid_config} do
      assert {:error, :unclosed_brace} = Validation.validate_config(invalid_config)
    end

    test "rejects configuration without module.exports", %{test_dir: test_dir} do
      no_export_config = "#{test_dir}/no_export.config.js"
      File.write!(no_export_config, "const config = { content: ['./src/**/*.js'] }")

      assert {:error, :missing_export} = Validation.validate_config(no_export_config)
    end

    test "accepts configuration with export syntax", %{test_dir: test_dir} do
      export_config = "#{test_dir}/export.config.js"
      File.write!(export_config, "export default { content: ['./src/**/*.js'] }")

      assert :ok = Validation.validate_config(export_config)
    end
  end

  describe "validate_file_exists/1" do
    setup do
      test_file = "/tmp/test_file_#{:rand.uniform(10000)}"
      File.write!(test_file, "test content")

      on_exit(fn ->
        File.rm(test_file)
      end)

      {:ok, test_file: test_file}
    end

    test "accepts existing regular file", %{test_file: test_file} do
      assert :ok = Validation.validate_file_exists(test_file)
    end

    test "rejects non-existent file" do
      assert {:error, :config_not_found} = Validation.validate_file_exists("/nonexistent/file")
    end

    test "rejects directory as file" do
      assert {:error, :config_not_found} = Validation.validate_file_exists("/tmp")
    end
  end

  describe "validate_directory/1" do
    test "accepts existing directory" do
      assert :ok = Validation.validate_directory("/tmp")
    end

    test "accepts creatable directory path" do
      test_dir = "/tmp/validation_test_dir_#{:rand.uniform(10000)}"

      # Ensure it doesn't exist
      File.rm_rf!(test_dir)
      refute File.exists?(test_dir)

      # Should validate successfully
      assert :ok = Validation.validate_directory(test_dir)

      # Should not actually create the directory permanently
      refute File.exists?(test_dir)
    end

    test "rejects existing file as directory" do
      test_file = "/tmp/test_file_#{:rand.uniform(10000)}"
      File.write!(test_file, "content")

      assert {:error, :not_a_directory} = Validation.validate_directory(test_file)

      File.rm!(test_file)
    end
  end

  describe "validate_url/1" do
    test "accepts valid HTTP and HTTPS URLs" do
      valid_urls = [
        "http://example.com",
        "https://example.com",
        "https://github.com/user/repo",
        "http://localhost:3000",
        "https://api.example.com/v1/endpoint",
        "https://example.com:8080/path?query=value"
      ]

      Enum.each(valid_urls, fn url ->
        assert :ok = Validation.validate_url(url), "Should accept URL: #{url}"
      end)
    end

    test "rejects invalid URL formats" do
      invalid_urls = [
        "not-a-url",
        # Missing scheme
        "://example.com",
        # Missing host
        "http://",
        # Missing host
        "https://"
      ]

      Enum.each(invalid_urls, fn url ->
        assert {:error, :invalid_url_format} = Validation.validate_url(url)
      end)

      # Note: "example.com" without scheme is invalid for our use case
      assert {:error, :invalid_url_format} = Validation.validate_url("example.com")
    end

    test "rejects unsupported schemes" do
      unsupported_urls = [
        "ftp://example.com",
        "file:///path/to/file",
        "mailto:user@example.com",
        "ssh://user@host"
      ]

      Enum.each(unsupported_urls, fn url ->
        assert {:error, :unsupported_scheme} = Validation.validate_url(url)
      end)
    end
  end

  describe "validate_cli_options/1" do
    test "accepts valid CLI options" do
      valid_options = [
        [],
        ["-i", "input.css"],
        ["-o", "output.css", "-w"],
        ["--input", "./src/styles.css", "--output", "./dist/styles.css", "--watch"],
        ["-c", "tailwind.config.js", "--minify"]
      ]

      Enum.each(valid_options, fn opts ->
        assert :ok = Validation.validate_cli_options(opts), "Should accept: #{inspect(opts)}"
      end)
    end

    test "rejects non-list options" do
      invalid_options = [
        "string",
        123,
        %{},
        nil,
        :atom
      ]

      Enum.each(invalid_options, fn opts ->
        assert {:error, :invalid_options_format} = Validation.validate_cli_options(opts)
      end)
    end

    test "rejects list with non-string elements" do
      invalid_lists = [
        ["-i", 123],
        ["valid", nil],
        ["-w", %{}],
        [:atom, "string"]
      ]

      Enum.each(invalid_lists, fn opts ->
        assert {:error, :invalid_option_type} = Validation.validate_cli_options(opts)
      end)
    end
  end

  describe "validate_process_name/1" do
    test "accepts valid process names" do
      valid_names = [
        :atom_name,
        :my_process,
        {:global, :global_name},
        {:via, Registry, :via_name}
      ]

      Enum.each(valid_names, fn name ->
        assert :ok = Validation.validate_process_name(name), "Should accept: #{inspect(name)}"
      end)
    end

    test "rejects invalid process names" do
      invalid_names = [
        "string_name",
        123,
        nil,
        %{},
        {:global, "string"},
        {:via, "string", :name},
        {:invalid, :tuple, :format}
      ]

      Enum.each(invalid_names, fn name ->
        result = Validation.validate_process_name(name)

        assert {:error, :invalid_process_name} = result,
               "Should reject name: #{inspect(name)}, got: #{inspect(result)}"
      end)
    end
  end

  describe "edge cases and integration" do
    test "handles unicode and special characters in paths" do
      unicode_path = "/tmp/测试文件_#{:rand.uniform(1000)}"
      assert :ok = Validation.validate_download_args(unicode_path, "https://example.com")
    end

    test "handles very long valid inputs" do
      long_path = "/tmp/" <> String.duplicate("a", 1000)
      long_url = "https://example.com/" <> String.duplicate("b", 1000)

      assert :ok = Validation.validate_download_args(long_path, long_url)
    end

    test "validates complex CLI option combinations" do
      complex_opts = [
        "-i",
        "./assets/css/app.css",
        "-o",
        "./priv/static/css/app.css",
        "--content",
        "./lib/**/*.{ex,heex,js}",
        "--config",
        "./assets/tailwind.config.js",
        "--watch",
        "--minify",
        "--no-autoprefixer"
      ]

      assert :ok = Validation.validate_cli_options(complex_opts)
    end

    test "handles whitespace-only strings correctly" do
      whitespace_strings = ["   ", "\t", "\n", "\r\n", "\t\n  "]

      Enum.each(whitespace_strings, fn str ->
        assert {:error, :invalid_path} =
                 Validation.validate_download_args(str, "https://example.com")

        assert {:error, :empty_url} = Validation.validate_download_args("/tmp/file", str)
      end)
    end
  end
end
