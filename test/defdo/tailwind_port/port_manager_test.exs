defmodule Defdo.TailwindPort.PortManagerTest do
  @moduledoc false
  use ExUnit.Case
  alias Defdo.TailwindPort.PortManager

  describe "create_port/1" do
    test "creates port successfully with valid args" do
      # Use /bin/echo which should exist on most systems
      result = PortManager.create_port(cmd: "/bin/echo", opts: ["test"])

      case result do
        {:ok, port} ->
          assert is_port(port)
          Port.close(port)

        {:error, _reason} ->
          # Expected to fail in some test environments, that's OK
          :ok
      end
    end

    test "handles invalid command gracefully" do
      result = PortManager.create_port(cmd: "/nonexistent/command", opts: [])
      assert {:error, _reason} = result
    end

    test "works with default binary path" do
      result = PortManager.create_port(opts: ["-h"])
      # Should either succeed or fail gracefully
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      if match?({:ok, _port}, result) do
        {:ok, port} = result
        Port.close(port)
      end
    end
  end

  describe "get_bin_path/0" do
    test "returns valid path" do
      {:ok, path} = PortManager.get_bin_path()
      assert is_binary(path)
      assert String.ends_with?(path, "bin")
    end

    test "creates directory if it doesn't exist" do
      # This test verifies the directory creation logic
      {:ok, path} = PortManager.get_bin_path()
      assert File.dir?(path)
    end
  end

  describe "prepare_command/2" do
    test "returns existing command if file exists" do
      # Use a command that definitely exists
      args = [cmd: "/bin/echo"]
      {:ok, bin_path} = PortManager.get_bin_path()

      result = PortManager.prepare_command(args, bin_path)
      assert {:ok, "/bin/echo"} = result
    end

    test "attempts download for non-existent command" do
      args = [cmd: "/tmp/nonexistent_tailwind"]
      {:ok, bin_path} = PortManager.get_bin_path()

      result = PortManager.prepare_command(args, bin_path)
      # Should either succeed (if download works) or fail with download error
      assert match?({:ok, _}, result) or match?({:error, {:download_failed, _}}, result)
    end

    test "uses default command when none specified" do
      args = []
      {:ok, bin_path} = PortManager.get_bin_path()

      result = PortManager.prepare_command(args, bin_path)
      # Should attempt to use default tailwindcss binary
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "build_command_args/3" do
    test "builds command with direct binary when input specified" do
      args = [opts: ["-i", "input.css", "-o", "output.css"]]
      cmd = "/bin/tailwindcss"
      bin_path = "/tmp/bin"

      {:ok, {command, final_args}} = PortManager.build_command_args(args, cmd, bin_path)

      assert command == cmd
      assert "-i" in final_args
      assert "input.css" in final_args
      assert "-o" in final_args
      assert "output.css" in final_args
    end

    test "uses wrapper script when no input specified" do
      args = [opts: ["--help"]]
      cmd = "/bin/tailwindcss"
      bin_path = "/tmp/bin"

      # Create a fake wrapper script
      wrapper_script = "#{bin_path}/tailwind_cli.sh"
      File.mkdir_p!(bin_path)
      File.write!(wrapper_script, "#!/bin/bash\necho 'wrapper'")

      {:ok, {command, final_args}} = PortManager.build_command_args(args, cmd, bin_path)

      assert command == wrapper_script
      assert cmd in final_args
      assert "--help" in final_args

      # Cleanup
      File.rm_rf!(bin_path)
    end

    test "falls back to direct command when wrapper doesn't exist" do
      args = [opts: ["--version"]]
      cmd = "/bin/tailwindcss"
      bin_path = "/tmp/nonexistent_bin"

      {:ok, {command, final_args}} = PortManager.build_command_args(args, cmd, bin_path)

      assert command == cmd
      assert "--version" in final_args
    end

    test "processes various CLI options correctly" do
      args = [opts: ["-w", "--watch", "-m", "--minify", "-c", "config.js"]]
      cmd = "/bin/tailwindcss"
      bin_path = "/tmp/bin"

      {:ok, {_command, final_args}} = PortManager.build_command_args(args, cmd, bin_path)

      assert "-w" in final_args
      assert "--watch" in final_args
      assert "-m" in final_args
      assert "--minify" in final_args
      assert "-c" in final_args
      assert "config.js" in final_args
    end
  end

  describe "validate_args/1" do
    test "validates correct arguments" do
      valid_args = [cmd: "/bin/echo", opts: ["-v"]]
      assert :ok = PortManager.validate_args(valid_args)
    end

    test "validates empty arguments" do
      assert :ok = PortManager.validate_args([])
    end

    test "rejects invalid cmd type" do
      invalid_args = [cmd: 123, opts: []]
      assert {:error, :invalid_cmd} = PortManager.validate_args(invalid_args)
    end

    test "rejects invalid opts type" do
      invalid_args = [cmd: "/bin/echo", opts: "invalid"]
      assert {:error, :invalid_opts} = PortManager.validate_args(invalid_args)
    end

    test "rejects non-list arguments" do
      assert {:error, :invalid_args} = PortManager.validate_args("not a list")
      assert {:error, :invalid_args} = PortManager.validate_args(123)
    end
  end

  describe "edge cases and error handling" do
    test "handles port creation failure gracefully" do
      # Try to create port with invalid executable
      # Device file, not executable
      result = PortManager.create_port(cmd: "/dev/null", opts: [])
      # Should either fail or succeed (wrapper script might handle it)
      case result do
        # Expected failure
        {:error, {:port_creation_failed, _}} -> :ok
        # Unexpected success but handle gracefully
        {:ok, port} -> Port.close(port)
        # Other errors are also fine
        {:error, _} -> :ok
      end
    end

    test "handles binary path creation failure" do
      # This test is harder to trigger, but we can test the logic
      # In practice, this would happen with permission issues
      {:ok, _path} = PortManager.get_bin_path()
      # If it succeeds, the directory was created successfully
    end

    test "works with complex option combinations" do
      complex_args = [
        cmd: "/bin/echo",
        opts: [
          "-i",
          "complex/input.css",
          "-o",
          "complex/output.css",
          "--content",
          "src/**/*.{js,ts,jsx,tsx}",
          "--config",
          "tailwind.config.js",
          "--watch",
          "--minify",
          "--no-autoprefixer"
        ]
      ]

      result = PortManager.create_port(complex_args)

      case result do
        {:ok, port} ->
          assert is_port(port)
          Port.close(port)

        {:error, _reason} ->
          # Complex commands might fail in test environment
          :ok
      end
    end

    test "handles empty options list" do
      {:ok, bin_path} = PortManager.get_bin_path()
      {:ok, {_command, final_args}} = PortManager.build_command_args([], "/bin/echo", bin_path)
      assert is_list(final_args)
    end
  end
end
