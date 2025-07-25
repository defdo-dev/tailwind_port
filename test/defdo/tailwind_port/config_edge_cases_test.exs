defmodule Defdo.TailwindPort.ConfigEdgeCasesTest do
  @moduledoc false
  use ExUnit.Case
  alias Defdo.TailwindPort.Config

  describe "edge cases and error handling" do
    test "validate_config with malformed JSON" do
      config_path = "/tmp/malformed_config.js"
      
      File.write!(config_path, "module.exports = { invalid json }")
      
      result = Config.validate_config(config_path)
      assert {:error, _reason} = result
      
      File.rm!(config_path)
    end

    test "validate_config with empty file" do
      config_path = "/tmp/empty_config.js"
      
      File.write!(config_path, "")
      
      result = Config.validate_config(config_path)
      assert {:error, _reason} = result
      
      File.rm!(config_path)
    end

    test "validate_config with non-existent file" do
      result = Config.validate_config("/nonexistent/path")
      assert {:error, :config_not_found} = result
    end

    test "get_effective_config with various option combinations" do
      # Test with watch mode
      config = Config.get_effective_config(opts: ["-w", "--watch"])
      assert config.watch_mode == true

      # Test with minify
      config = Config.get_effective_config(opts: ["-m", "--minify"])
      assert config.minify == true

      # Test with config file  
      config = Config.get_effective_config(config: "./custom.config.js")
      assert config.config_path == "./custom.config.js"

      # Test with input file
      config = Config.get_effective_config(opts: ["-i", "./input.css"])
      assert config.input_path == "./input.css"

      # Test with output file
      config = Config.get_effective_config(opts: ["-o", "./output.css"])
      assert config.output_path == "./output.css"

      # Test with content paths
      config = Config.get_effective_config(opts: ["--content", "./src/*.js"])
      assert config.content_paths == ["./src/*.js"]
    end

    test "ensure_config creates directory if needed" do
      test_dir = "/tmp/test_config_dir_#{:rand.uniform(10000)}"
      config_path = "#{test_dir}/tailwind.config.js"
      
      # Ensure directory doesn't exist
      File.rm_rf!(test_dir)
      refute File.exists?(test_dir)
      
      result = Config.ensure_config(config_path)
      assert :ok = result
      assert File.exists?(config_path)
      
      # Cleanup
      File.rm_rf!(test_dir)
    end

    test "validate_config handles different scenarios" do
      # Test with a simple valid config that has content field
      config_path = "/tmp/simple_config.js"
      File.write!(config_path, "module.exports = { content: ['./src/**/*.js'] }")
      
      result = Config.validate_config(config_path)
      assert :ok = result
      
      File.rm!(config_path)
    end

    test "extract_options handles edge cases" do
      # Test with empty options
      config = Config.get_effective_config([])
      assert config.watch_mode == false
      assert config.minify == false

      # Test with duplicate options (first one wins)
      config = Config.get_effective_config(opts: ["-i", "first.css", "-i", "second.css"])
      assert config.input_path == "first.css"
    end
  end
end