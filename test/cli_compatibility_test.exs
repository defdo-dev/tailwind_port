defmodule Defdo.TailwindPort.CliCompatibilityTest do
  use ExUnit.Case, async: true
  alias Defdo.TailwindPort.CliCompatibility

  describe "detect_version/0" do
    test "detects current version from ConfigManager" do
      # Test with actual configuration
      version = CliCompatibility.detect_version()
      assert version in [:v3, :v4]
    end
  end

  describe "filter_args_for_version/2" do
    test "removes v3-only options for v4" do
      args = [
        input: "input.css",
        output: "output.css",
        content: ["*.html"],
        config: "tailwind.config.js",
        postcss: true,
        poll: true,
        minify: true
      ]

      result = CliCompatibility.filter_args_for_version(args, :v4)

      assert result == [
               input: "input.css",
               output: "output.css",
               minify: true
             ]
    end

    test "removes v4-only options for v3" do
      args = [
        input: "input.css",
        output: "output.css",
        optimize: true,
        cwd: "/app",
        map: true,
        minify: true
      ]

      result = CliCompatibility.filter_args_for_version(args, :v3)

      assert result == [
               input: "input.css",
               output: "output.css",
               minify: true
             ]
    end

    test "keeps compatible options for both versions" do
      args = [
        input: "input.css",
        output: "output.css",
        minify: true,
        watch: true
      ]

      v4_result = CliCompatibility.filter_args_for_version(args, :v4)
      v3_result = CliCompatibility.filter_args_for_version(args, :v3)

      assert v4_result == args
      assert v3_result == args
    end

    test "handles empty options list" do
      assert CliCompatibility.filter_args_for_version([], :v3) == []
      assert CliCompatibility.filter_args_for_version([], :v4) == []
    end

    test "handles nil values in options" do
      args = [
        input: "input.css",
        content: nil,
        config: "config.js"
      ]

      # Should still filter out the key even if value is nil
      result = CliCompatibility.filter_args_for_version(args, :v4)
      assert result == [input: "input.css"]
    end
  end

  describe "option_supported?/2" do
    test "identifies v3-only options" do
      assert CliCompatibility.option_supported?(:content, :v3) == true
      assert CliCompatibility.option_supported?(:config, :v3) == true
      assert CliCompatibility.option_supported?(:postcss, :v3) == true
      assert CliCompatibility.option_supported?(:poll, :v3) == true

      assert CliCompatibility.option_supported?(:content, :v4) == false
      assert CliCompatibility.option_supported?(:config, :v4) == false
      assert CliCompatibility.option_supported?(:postcss, :v4) == false
      assert CliCompatibility.option_supported?(:poll, :v4) == false
    end

    test "identifies v4-only options" do
      assert CliCompatibility.option_supported?(:optimize, :v4) == true
      assert CliCompatibility.option_supported?(:cwd, :v4) == true
      assert CliCompatibility.option_supported?(:map, :v4) == true

      assert CliCompatibility.option_supported?(:optimize, :v3) == false
      assert CliCompatibility.option_supported?(:cwd, :v3) == false
      assert CliCompatibility.option_supported?(:map, :v3) == false
    end

    test "identifies compatible options" do
      compatible_options = [:input, :output, :minify, :watch]

      Enum.each(compatible_options, fn option ->
        assert CliCompatibility.option_supported?(option, :v3) == true
        assert CliCompatibility.option_supported?(option, :v4) == true
      end)
    end

    test "returns false for unknown options" do
      assert CliCompatibility.option_supported?(:unknown_option, :v3) == false
      assert CliCompatibility.option_supported?(:unknown_option, :v4) == false
    end
  end

  describe "supported_options/1" do
    test "returns all v3 options" do
      v3_options = CliCompatibility.supported_options(:v3)

      assert :input in v3_options
      assert :output in v3_options
      assert :minify in v3_options
      assert :watch in v3_options
      assert :content in v3_options
      assert :config in v3_options
      assert :postcss in v3_options
      assert :poll in v3_options
      assert :no_autoprefixer in v3_options
    end

    test "returns all v4 options" do
      v4_options = CliCompatibility.supported_options(:v4)

      assert :input in v4_options
      assert :output in v4_options
      assert :minify in v4_options
      assert :watch in v4_options
      assert :optimize in v4_options
      assert :cwd in v4_options
      assert :map in v4_options
    end

    test "does not include v3-only options in v4" do
      v4_options = CliCompatibility.supported_options(:v4)

      refute :content in v4_options
      refute :config in v4_options
      refute :postcss in v4_options
      refute :poll in v4_options
      refute :no_autoprefixer in v4_options
    end

    test "does not include v4-only options in v3" do
      v3_options = CliCompatibility.supported_options(:v3)

      refute :optimize in v3_options
      refute :cwd in v3_options
      refute :map in v3_options
    end
  end

  describe "removed_in_v4/1" do
    test "identifies options removed in v4" do
      args = [
        input: "input.css",
        content: ["*.html"],
        config: "tailwind.config.js",
        postcss: true,
        poll: true,
        minify: true
      ]

      removed = CliCompatibility.removed_in_v4(args)

      assert removed == [
               content: ["*.html"],
               config: "tailwind.config.js",
               postcss: true,
               poll: true
             ]
    end

    test "returns empty list when no v3-only options" do
      args = [
        input: "input.css",
        output: "output.css",
        minify: true
      ]

      assert CliCompatibility.removed_in_v4(args) == []
    end

    test "handles empty list" do
      assert CliCompatibility.removed_in_v4([]) == []
    end
  end

  describe "new_in_v4/0" do
    test "returns new v4 options" do
      new = CliCompatibility.new_in_v4()

      assert Keyword.has_key?(new, :optimize)
      assert Keyword.has_key?(new, :cwd)
      assert Keyword.has_key?(new, :map)
    end
  end

  describe "filter_args_for_current_version/1" do
    test "filters based on detected version" do
      args = [
        input: "input.css",
        content: ["*.html"],
        optimize: true,
        minify: true
      ]

      result = CliCompatibility.filter_args_for_current_version(args)

      # The result should be filtered based on the actual detected version
      # We just verify that filtering is happening
      assert is_list(result)
      assert Keyword.has_key?(result, :input)
      assert Keyword.has_key?(result, :minify)
    end
  end

  describe "integration scenarios" do
    test "typical v3 configuration" do
      v3_config = [
        input: "assets/css/app.css",
        output: "priv/static/assets/app.css",
        content: ["**/*.heex", "**/*.eex"],
        config: "config/tailwind.config.js",
        postcss: "./postcss.config.js",
        minify: true
      ]

      v4_filtered = CliCompatibility.filter_args_for_version(v3_config, :v4)

      # Should only keep v4-compatible options
      assert v4_filtered == [
               input: "assets/css/app.css",
               output: "priv/static/assets/app.css",
               minify: true
             ]
    end

    test "typical v4 configuration" do
      v4_config = [
        input: "assets/css/app.css",
        output: "priv/static/assets/app.css",
        optimize: true,
        cwd: "./assets",
        map: true,
        minify: true
      ]

      v3_filtered = CliCompatibility.filter_args_for_version(v4_config, :v3)

      # Should only keep v3-compatible options
      assert v3_filtered == [
               input: "assets/css/app.css",
               output: "priv/static/assets/app.css",
               minify: true
             ]
    end
  end
end
