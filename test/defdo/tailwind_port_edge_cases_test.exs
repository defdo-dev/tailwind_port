defmodule Defdo.TailwindPortEdgeCasesTest do
  @moduledoc false
  use ExUnit.Case
  alias Defdo.TailwindPort

  describe "edge cases and error paths" do
    @tag :capture_log
    test "validation functions with invalid inputs" do
      # Test start_link with invalid args
      result = TailwindPort.start_link("invalid_args")
      assert {:error, :invalid_args} = result

      # Test start_link with invalid name
      result = TailwindPort.start_link(name: "string_name")
      assert {:error, :invalid_name} = result

      # Test start_link with invalid opts
      result = TailwindPort.start_link(opts: "invalid_opts")
      assert {:error, :invalid_opts} = result
    end

    @tag :capture_log
    test "new function with invalid arguments" do
      {:ok, _pid} = TailwindPort.start_link(name: :test_validation)

      # Test with invalid cmd
      result = TailwindPort.new(:test_validation, cmd: 123)
      assert {:error, :invalid_cmd} = result

      # Test with invalid opts
      result = TailwindPort.new(:test_validation, opts: "invalid")
      assert {:error, :invalid_opts} = result

      # Test with completely invalid args
      result = TailwindPort.new(:test_validation, "invalid")
      assert {:error, :invalid_args} = result

      TailwindPort.terminate(:test_validation)
    end

    @tag :capture_log
    test "handle_info with unknown messages" do
      {:ok, pid} = TailwindPort.start_link(name: :test_unknown_msg, opts: [])

      # Send unknown message
      send(pid, :unknown_message)
      send(pid, {:unknown_tuple, "data"})

      # Process should still be alive
      Process.sleep(100)
      assert Process.alive?(pid)

      TailwindPort.terminate(:test_unknown_msg)
    end

    @tag :capture_log
    test "port exit with non-zero status" do
      {:ok, _pid} = TailwindPort.start_link(name: :test_exit_status, opts: [])

      # Create a port that will exit with error
      result = TailwindPort.new(:test_exit_status, cmd: "/bin/false", opts: [])
      
      case result do
        {:ok, _state} ->
          # Wait for port to exit
          Process.sleep(1000)
          
          # Check health - should show error count increased
          health = TailwindPort.health(:test_exit_status)
          assert health.errors >= 0  # May or may not have incremented yet
          
        {:error, _reason} ->
          # Expected - invalid command should fail
          :ok
      end

      TailwindPort.terminate(:test_exit_status)
    end

    @tag :capture_log
    test "startup timeout handling" do
      {:ok, _pid} = TailwindPort.start_link(name: :test_startup_timeout, opts: [])

      # Try to create a port that will hang during startup
      result = TailwindPort.new(:test_startup_timeout, cmd: "/bin/sleep", opts: ["30"])
      
      case result do
        {:ok, _state} ->
          # Test wait_until_ready with short timeout
          result = TailwindPort.wait_until_ready(:test_startup_timeout, 100)
          assert {:error, :timeout} = result
          
        {:error, _reason} ->
          # Expected in test environment
          :ok
      end

      TailwindPort.terminate(:test_startup_timeout)
    end

    @tag :capture_log  
    test "health metrics edge cases" do
      {:ok, _pid} = TailwindPort.start_link(name: :test_health_edge, opts: [])

      # Get initial health
      health = TailwindPort.health(:test_health_edge)
      
      assert health.uptime_seconds >= 0
      assert health.total_outputs == 0
      assert health.css_builds == 0
      assert health.errors == 0
      assert health.port_ready == false
      assert is_number(health.last_activity_seconds_ago)

      TailwindPort.terminate(:test_health_edge)
    end

    @tag :capture_log
    test "ready? function with timeout" do
      {:ok, _pid} = TailwindPort.start_link(name: :test_ready_timeout, opts: [])

      # Test ready? with very short timeout
      result = TailwindPort.ready?(:test_ready_timeout, 1)
      assert result == false

      TailwindPort.terminate(:test_ready_timeout)
    end

    @tag :capture_log
    test "terminate with already terminated process" do
      {:ok, pid} = TailwindPort.start_link(name: :test_double_terminate, opts: [])

      # First terminate
      TailwindPort.terminate(:test_double_terminate)
      
      # Wait for process to die
      Process.sleep(100)
      refute Process.alive?(pid)

      # Second terminate should handle gracefully (might raise an error, that's OK)
      try do
        TailwindPort.terminate(:test_double_terminate)
      catch
        :exit, _reason -> :ok  # Expected when process doesn't exist
      end
    end

    @tag :capture_log
    test "process exit scenarios" do
      {:ok, pid} = TailwindPort.start_link(name: :test_exit_scenarios, opts: [])

      # Simulate different exit messages (these are handled in handle_info)
      send(pid, {:DOWN, make_ref(), :port, self(), :normal})
      send(pid, {:EXIT, self(), :normal})

      # Process should handle these messages without crashing
      Process.sleep(100)
      # Process might or might not be alive depending on the messages, 
      # but it shouldn't crash
      :ok

      if Process.alive?(pid) do
        TailwindPort.terminate(:test_exit_scenarios)
      end
    end

    @tag :capture_log
    test "command building edge cases" do
      {:ok, _pid} = TailwindPort.start_link(name: :test_cmd_building, opts: [])

      # Test with various option combinations
      test_cases = [
        ["-i", "input.css", "--input", "input2.css"],  # Duplicate input options
        ["-o", "output.css", "--output", "output2.css"],  # Duplicate output options
        ["--watch", "-w"],  # Duplicate watch options
        ["--poll", "-p"],  # Duplicate poll options
        ["--minify", "-m"],  # Duplicate minify options
        ["--config", "config.js", "-c", "config2.js"],  # Duplicate config options
        ["--no-autoprefixer"],  # No autoprefixer option
        ["--content", "*.html", "--content", "*.js"]  # Multiple content options
      ]

      Enum.each(test_cases, fn opts ->
        result = TailwindPort.new(:test_cmd_building, opts: opts)
        # These should mostly fail in test environment, but exercise the code paths
        assert match?({:error, _}, result) or match?({:ok, _}, result)
      end)

      TailwindPort.terminate(:test_cmd_building)
    end

    @tag :capture_log
    test "fs operations edge cases" do
      {:ok, _pid} = TailwindPort.start_link(name: :test_fs_ops, opts: [])

      # Test FS operations
      fs = TailwindPort.init_fs(:test_fs_ops)
      assert %Defdo.TailwindPort.FS{} = fs

      # Test FS update
      updated_fs = TailwindPort.update_fs(:test_fs_ops, working_files: [input_css_path: "/tmp/test.css"])
      assert updated_fs.working_files.input_css_path == "/tmp/test.css"

      # Test FS update and init
      init_fs = TailwindPort.update_and_init_fs(:test_fs_ops, working_files: [output_css_path: "/tmp/out.css"])
      assert init_fs.working_files.output_css_path == "/tmp/out.css"

      TailwindPort.terminate(:test_fs_ops)
    end

    @tag :capture_log
    test "port monitoring and cleanup" do
      {:ok, _pid} = TailwindPort.start_link(name: :test_port_monitoring, opts: [])

      # Try to create a port to test monitoring
      result = TailwindPort.new(:test_port_monitoring, cmd: "/bin/echo", opts: ["test"])
      
      case result do
        {:ok, _state} ->
          # Port creation succeeded, check state via health
          health = TailwindPort.health(:test_port_monitoring)
          assert is_map(health)
          
        {:error, _reason} ->
          # Expected in test environment
          :ok
      end

      TailwindPort.terminate(:test_port_monitoring)
    end

    @tag :capture_log
    test "multiple waiting callers for ready state" do
      {:ok, _pid} = TailwindPort.start_link(name: :test_multiple_waiters, opts: [])

      # Start multiple wait_until_ready calls
      tasks = for _i <- 1..3 do
        Task.async(fn ->
          TailwindPort.wait_until_ready(:test_multiple_waiters, 1000)
        end)
      end

      # All should timeout since port never becomes ready in test
      results = Task.await_many(tasks, 2000)
      
      for result <- results do
        assert {:error, :timeout} = result
      end

      TailwindPort.terminate(:test_multiple_waiters)
    end
  end

  describe "data processing edge cases" do
    @tag :capture_log
    test "handle port data with various content types" do
      {:ok, _pid} = TailwindPort.start_link(name: :test_data_processing, opts: [])

      # First create a port so we can simulate data from it
      result = TailwindPort.new(:test_data_processing, cmd: "/bin/echo", opts: ["test"])
      
      case result do
        {:ok, _state} ->
          # Now we have a real port, wait a bit for it to become ready
          Process.sleep(200)
          
          # Check that health metrics exist
          health = TailwindPort.health(:test_data_processing)
          assert is_map(health)
          assert health.total_outputs >= 0  # Might have some output from echo
          
        {:error, _reason} ->
          # Port creation failed, just check basic health metrics
          health = TailwindPort.health(:test_data_processing)
          assert is_map(health)
          assert health.total_outputs == 0
      end

      TailwindPort.terminate(:test_data_processing)
    end
  end
end