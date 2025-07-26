defmodule Defdo.TailwindPort.ProjectSetupTest do
  @moduledoc false
  # Not async due to file system operations
  use ExUnit.Case, async: false
  alias Defdo.TailwindPort.ProjectSetup

  @test_dir "/tmp/tailwind_port_test_#{:rand.uniform(10000)}"
  @assets_dir Path.join(@test_dir, "assets")
  @css_dir Path.join(@test_dir, "assets/css")
  @config_path Path.join(@test_dir, "assets/tailwind.config.js")

  setup do
    # Ensure clean test environment
    File.rm_rf(@test_dir)
    File.mkdir_p(@test_dir)

    # Change to test directory
    original_cwd = File.cwd!()
    File.cd(@test_dir)

    on_exit(fn ->
      File.cd(original_cwd)
      File.rm_rf(@test_dir)
    end)

    :ok
  end

  describe "setup_project/0" do
    test "creates complete project setup" do
      assert :ok = ProjectSetup.setup_project()

      # Verify directories exist
      assert File.dir?(@assets_dir)
      assert File.dir?(@css_dir)

      # Verify config file exists and has content
      assert File.exists?(@config_path)
      {:ok, content} = File.read(@config_path)
      assert String.contains?(content, "module.exports")
      assert String.contains?(content, "tailwindcss/plugin")
    end

    test "is idempotent - can run multiple times safely" do
      assert :ok = ProjectSetup.setup_project()
      assert :ok = ProjectSetup.setup_project()
      assert :ok = ProjectSetup.setup_project()

      # Should still have correct setup
      assert File.dir?(@css_dir)
      assert File.exists?(@config_path)
    end

    test "preserves existing config file" do
      # Create custom config first
      File.mkdir_p(@assets_dir)
      custom_content = "// Custom config\nmodule.exports = {}"
      File.write(@config_path, custom_content)

      assert :ok = ProjectSetup.setup_project()

      # Should preserve custom content
      {:ok, content} = File.read(@config_path)
      assert content == custom_content
    end
  end

  describe "ensure_assets_directory/0" do
    test "creates assets and css directories" do
      assert :ok = ProjectSetup.ensure_assets_directory()

      assert File.dir?(@assets_dir)
      assert File.dir?(@css_dir)
    end

    test "succeeds when directories already exist" do
      File.mkdir_p(@css_dir)

      assert :ok = ProjectSetup.ensure_assets_directory()
      assert File.dir?(@css_dir)
    end

    test "handles permission errors gracefully" do
      # Create a directory we can't write to (simulate permission error)
      # This test might not work on all systems or when running as root in CI, so we'll make it conditional
      if :os.type() == {:unix, :linux} and System.get_env("CI") != "true" do
        File.mkdir_p("readonly_parent")
        # Read-only
        File.chmod("readonly_parent", 0o444)

        File.cd("readonly_parent")

        result = ProjectSetup.ensure_assets_directory()
        assert {:error, {:assets_mkdir_failed, _reason}} = result

        File.cd(@test_dir)
        # Restore permissions
        File.chmod("readonly_parent", 0o755)
        File.rm_rf("readonly_parent")
      else
        # On other systems or in CI, just test the success case
        assert :ok = ProjectSetup.ensure_assets_directory()
      end
    end
  end

  describe "create_tailwind_config/1" do
    test "creates config with default path" do
      File.mkdir_p(@assets_dir)

      assert :ok = ProjectSetup.create_tailwind_config()

      assert File.exists?(@config_path)
      {:ok, content} = File.read(@config_path)
      assert String.contains?(content, "module.exports")
      assert String.contains?(content, "content:")
      assert String.contains?(content, "plugins:")
    end

    test "creates config with custom path" do
      custom_path = "custom/path/tailwind.config.js"
      custom_full_path = Path.join(@test_dir, custom_path)

      assert :ok = ProjectSetup.create_tailwind_config(custom_path)

      assert File.exists?(custom_full_path)
      {:ok, content} = File.read(custom_full_path)
      assert String.contains?(content, "module.exports")
    end

    test "preserves existing config file" do
      File.mkdir_p(@assets_dir)
      existing_content = "// Existing config"
      File.write(@config_path, existing_content)

      assert :ok = ProjectSetup.create_tailwind_config()

      {:ok, content} = File.read(@config_path)
      assert content == existing_content
    end

    test "validates config path" do
      assert {:error, {:invalid_config_path, _}} = ProjectSetup.create_tailwind_config("")
      assert {:error, {:invalid_config_path, _}} = ProjectSetup.create_tailwind_config("   ")

      assert {:error, {:invalid_config_path, _}} =
               ProjectSetup.create_tailwind_config("config.txt")
    end

    test "creates directory structure when needed" do
      nested_path = "deep/nested/structure/tailwind.config.js"

      assert :ok = ProjectSetup.create_tailwind_config(nested_path)

      nested_full_path = Path.join(@test_dir, nested_path)
      assert File.exists?(nested_full_path)
      assert File.dir?(Path.dirname(nested_full_path))
    end
  end

  describe "get_default_config_content/0" do
    test "returns valid JavaScript configuration" do
      content = ProjectSetup.get_default_config_content()

      assert is_binary(content)
      assert String.contains?(content, "module.exports")
      assert String.contains?(content, "content:")
      assert String.contains?(content, "theme:")
      assert String.contains?(content, "plugins:")
    end

    test "includes Phoenix-specific configurations" do
      content = ProjectSetup.get_default_config_content()

      # Phoenix file patterns
      assert String.contains?(content, "'../lib/*_web.ex'")
      assert String.contains?(content, "'../lib/*_web/**/*.*ex'")

      # Phoenix-specific variants
      assert String.contains?(content, "phx-no-feedback")
      assert String.contains?(content, "phx-click-loading")
      assert String.contains?(content, "phx-submit-loading")
      assert String.contains?(content, "phx-change-loading")

      # Form plugin
      assert String.contains?(content, "@tailwindcss/forms")
    end

    test "content is consistent across calls" do
      content1 = ProjectSetup.get_default_config_content()
      content2 = ProjectSetup.get_default_config_content()

      assert content1 == content2
    end
  end

  describe "project_setup_complete?/0" do
    test "returns false when nothing is set up" do
      refute ProjectSetup.project_setup_complete?()
    end

    test "returns false when only assets directory exists" do
      File.mkdir_p(@css_dir)

      refute ProjectSetup.project_setup_complete?()
    end

    test "returns false when only config exists" do
      File.mkdir_p(@assets_dir)
      File.write(@config_path, "module.exports = {}")

      refute ProjectSetup.project_setup_complete?()
    end

    test "returns false when config is empty" do
      File.mkdir_p(@css_dir)
      File.write(@config_path, "")

      refute ProjectSetup.project_setup_complete?()
    end

    test "returns true when setup is complete" do
      File.mkdir_p(@css_dir)
      File.write(@config_path, "module.exports = {}")

      assert ProjectSetup.project_setup_complete?()
    end

    test "returns true after setup_project" do
      ProjectSetup.setup_project()

      assert ProjectSetup.project_setup_complete?()
    end
  end

  describe "cleanup_project/1" do
    test "removes all project files by default" do
      # Set up project first
      ProjectSetup.setup_project()
      assert ProjectSetup.project_setup_complete?()

      # Clean up
      assert :ok = ProjectSetup.cleanup_project()

      # Verify cleanup
      refute File.exists?(@config_path)
      refute File.dir?(@css_dir)
    end

    test "keeps assets when keep_assets option is true" do
      # Set up project and add some content
      ProjectSetup.setup_project()
      test_css_file = Path.join(@css_dir, "test.css")
      File.write(test_css_file, "/* test */")

      # Clean up with keep_assets
      assert :ok = ProjectSetup.cleanup_project(keep_assets: true)

      # Config should be removed, assets should remain
      refute File.exists?(@config_path)
      assert File.dir?(@css_dir)
      assert File.exists?(test_css_file)
    end

    test "handles cleanup when files don't exist" do
      # Try to clean up non-existent project
      assert :ok = ProjectSetup.cleanup_project()
      assert :ok = ProjectSetup.cleanup_project(keep_assets: true)
    end
  end

  describe "integration and workflow tests" do
    test "complete setup and verification workflow" do
      # Initial state
      refute ProjectSetup.project_setup_complete?()

      # Setup
      assert :ok = ProjectSetup.setup_project()

      # Verify
      assert ProjectSetup.project_setup_complete?()
      assert File.dir?(@css_dir)
      assert File.exists?(@config_path)

      # Config should be valid
      {:ok, content} = File.read(@config_path)
      assert String.contains?(content, "module.exports")
    end

    test "handles mixed setup states" do
      # Partial setup - only directory
      File.mkdir_p(@assets_dir)
      refute ProjectSetup.project_setup_complete?()

      # Complete setup
      assert :ok = ProjectSetup.setup_project()
      assert ProjectSetup.project_setup_complete?()

      # Partial cleanup - remove config only
      File.rm(@config_path)
      refute ProjectSetup.project_setup_complete?()

      # Re-setup should work
      assert :ok = ProjectSetup.setup_project()
      assert ProjectSetup.project_setup_complete?()
    end

    test "preserves user customizations" do
      # Initial setup
      ProjectSetup.setup_project()

      # User customizes config
      custom_config = """
      // User's custom configuration
      module.exports = {
        content: ['./src/**/*.html'],
        theme: {
          colors: {
            primary: '#1234567'
          }
        }
      }
      """

      File.write(@config_path, custom_config)

      # Re-running setup should preserve customizations
      assert :ok = ProjectSetup.setup_project()

      {:ok, content} = File.read(@config_path)
      assert content == custom_config
    end
  end

  describe "error handling and edge cases" do
    test "handles filesystem errors gracefully" do
      # Test with invalid directory name (contains null character)
      invalid_path = "invalid\0path/tailwind.config.js"

      result = ProjectSetup.create_tailwind_config(invalid_path)
      assert {:error, {:config_write_failed, _}} = result
    end

    test "validates config file extensions" do
      invalid_extensions = [
        "config.json",
        "config.yaml",
        "config.txt",
        "config",
        "config."
      ]

      Enum.each(invalid_extensions, fn path ->
        assert {:error, {:invalid_config_path, _}} = ProjectSetup.create_tailwind_config(path)
      end)
    end

    test "handles whitespace in paths" do
      assert {:error, {:invalid_config_path, _}} = ProjectSetup.create_tailwind_config("  ")
      assert {:error, {:invalid_config_path, _}} = ProjectSetup.create_tailwind_config("\t\n")
    end
  end

  describe "configuration content validation" do
    test "generated config is valid JavaScript syntax" do
      content = ProjectSetup.get_default_config_content()

      # Basic syntax checks
      assert String.contains?(content, "module.exports = {")
      assert String.ends_with?(String.trim(content), "}")

      # Should not have obvious syntax errors
      refute String.contains?(content, "undefined")
      refute String.contains?(content, "null")

      # Should have proper structure
      assert Regex.match?(~r/content:\s*\[/, content)
      assert Regex.match?(~r/theme:\s*\{/, content)
      assert Regex.match?(~r/plugins:\s*\[/, content)
    end

    test "includes all expected Phoenix variants" do
      content = ProjectSetup.get_default_config_content()

      phoenix_variants = [
        "phx-no-feedback",
        "phx-click-loading",
        "phx-submit-loading",
        "phx-change-loading"
      ]

      Enum.each(phoenix_variants, fn variant ->
        assert String.contains?(content, variant)
      end)
    end
  end
end
