defmodule Defdo.TailwindPort.ConfigTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Defdo.TailwindPort.Config

  @valid_config_content """
  module.exports = {
    content: ["./lib/**/*.ex"],
    theme: { extend: {} },
    plugins: []
  }
  """

  @invalid_config_content """
  this is not a valid config
  """

  setup do
    # Create a temporary directory for tests
    tmp_dir = System.tmp_dir()
    test_dir = Path.join([tmp_dir, "tailwind_port_test_#{:rand.uniform(1_000_000)}"])
    File.mkdir_p!(test_dir)

    on_exit(fn ->
      File.rm_rf(test_dir)
    end)

    %{test_dir: test_dir}
  end

  test "validate_config with valid config", %{test_dir: test_dir} do
    config_path = Path.join(test_dir, "valid.config.js")
    File.write!(config_path, @valid_config_content)

    assert :ok = Config.validate_config(config_path)
  end

  test "validate_config with invalid config", %{test_dir: test_dir} do
    config_path = Path.join(test_dir, "invalid.config.js")
    File.write!(config_path, @invalid_config_content)

    assert {:error, :invalid_config} = Config.validate_config(config_path)
  end

  test "validate_config with non-existent config" do
    assert {:error, :config_not_found} = Config.validate_config("/non/existent/config.js")
  end

  test "ensure_config creates default config if not exists", %{test_dir: test_dir} do
    config_path = Path.join(test_dir, "new.config.js")

    refute File.exists?(config_path)
    assert :ok = Config.ensure_config(config_path)
    assert File.exists?(config_path)

    content = File.read!(config_path)
    assert String.contains?(content, "module.exports")
    assert String.contains?(content, "content:")
  end

  test "ensure_config validates existing config file", %{test_dir: test_dir} do
    config_path = Path.join(test_dir, "existing.config.js")
    File.write!(config_path, @valid_config_content)

    # This should validate the existing file
    assert :ok = Config.ensure_config(config_path)
    assert File.exists?(config_path)
  end

  test "get_effective_config with default arguments" do
    # Test with no arguments (line 39)
    config = Config.get_effective_config()

    assert is_map(config)
    assert config.timeout == 5000
    assert config.retry_count == 3
    assert config.watch_mode == false
    assert config.minify == false
  end

  test "get_effective_config returns defaults" do
    config = Config.get_effective_config([])

    assert is_map(config)
    assert config.timeout == 5000
    assert config.retry_count == 3
    assert config.watch_mode == false
    assert config.minify == false
  end

  test "get_effective_config parses options" do
    opts = [
      opts: ["-i", "input.css", "-o", "output.css", "--content", "*.html,*.js", "-w", "-m"],
      timeout: 10000,
      retry_count: 5
    ]

    config = Config.get_effective_config(opts)

    assert config.timeout == 10000
    assert config.retry_count == 5
    assert config.watch_mode == true
    assert config.minify == true
    assert config.content_paths == ["*.html", "*.js"]
  end
end
