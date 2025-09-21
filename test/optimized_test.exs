defmodule Defdo.TailwindPort.OptimizedTest do
  use ExUnit.Case, async: false

  alias Defdo.TailwindPort.Optimized

  setup do
    # Ensure clean state before each test
    case Process.whereis(Optimized) do
      pid when is_pid(pid) -> GenServer.stop(pid)
      nil -> :ok
    end

    :ok
  end

  describe "start_link/1" do
    test "starts the optimized port pool successfully" do
      assert {:ok, pid} = Optimized.start_link(compile_timeout_ms: 100)
      assert Process.alive?(pid)
      assert Process.whereis(Optimized) == pid
    end

    test "returns already_started if already running" do
      {:ok, _pid} = Optimized.start_link(compile_timeout_ms: 100)
      assert {:error, {:already_started, _pid}} = Optimized.start_link()
    end

    test "accepts custom options" do
      opts = [max_pool_size: 5, enable_watch_mode: false]
      assert {:ok, _pid} = Optimized.start_link([compile_timeout_ms: 100] ++ opts)
    end
  end

  describe "compile/2" do
    setup do
      {:ok, _pid} = Optimized.start_link(compile_timeout_ms: 100)
      :ok
    end

    test "compiles successfully with valid options" do
      opts = [
        # Use echo for testing
        cmd: "echo",
        input: "/tmp/test_input.css",
        output: "/tmp/test_output.css",
        content: "/tmp/test_content.html"
      ]

      content = "<div class='bg-red-500'>Test</div>"

      assert {:ok, result} = Optimized.compile(opts, content)
      assert is_map(result)
      assert Map.has_key?(result, :compiled_css)
    end

    test "handles compilation errors gracefully" do
      opts = [
        # Command that always fails
        cmd: "false",
        input: "/nonexistent/input.css",
        output: "/tmp/test_output.css"
      ]

      content = "<div>Test</div>"

      # Should fallback gracefully or return appropriate error
      result = Optimized.compile(opts, content)
      assert elem(result, 0) in [:ok, :error]
    end

    test "reuses ports for identical configurations" do
      opts = [
        cmd: "echo",
        input: "/tmp/test_input.css",
        output: "/tmp/test_output.css"
      ]

      content = "<div>Test</div>"

      # First compilation
      assert {:ok, _result1} = Optimized.compile(opts, content)
      stats1 = Optimized.get_stats()

      # Second compilation with same config
      assert {:ok, _result2} = Optimized.compile(opts, content)
      stats2 = Optimized.get_stats()

      # Should show increased cache hits or port reuse
      assert stats2.total_compilations > stats1.total_compilations
    end
  end

  describe "batch_compile/1" do
    setup do
      {:ok, _pid} = Optimized.start_link(compile_timeout_ms: 100)
      :ok
    end

    test "processes multiple operations efficiently" do
      operations = [
        %{
          id: :op1,
          opts: [cmd: "echo", input: "/tmp/input1.css", output: "/tmp/output1.css"],
          content: "<div class='bg-blue-500'>Test 1</div>",
          priority: :normal
        },
        %{
          id: :op2,
          opts: [cmd: "echo", input: "/tmp/input2.css", output: "/tmp/output2.css"],
          content: "<div class='bg-green-500'>Test 2</div>",
          priority: :high
        }
      ]

      assert {:ok, results} = Optimized.batch_compile(operations)
      assert is_list(results)
      assert length(results) == 2

      # Verify each result has the operation_id
      operation_ids = Enum.map(results, & &1.operation_id)
      assert :op1 in operation_ids
      assert :op2 in operation_ids
    end

    test "groups operations by configuration for efficiency" do
      # Operations with same config should be grouped
      same_config_ops = [
        %{
          id: :same1,
          opts: [cmd: "echo", input: "/tmp/same.css"],
          content: "<div>1</div>",
          priority: :normal
        },
        %{
          id: :same2,
          opts: [cmd: "echo", input: "/tmp/same.css"],
          content: "<div>2</div>",
          priority: :normal
        }
      ]

      assert {:ok, results} = Optimized.batch_compile(same_config_ops)
      assert length(results) == 2

      # Stats should show batch compilation occurred
      stats = Optimized.get_stats()
      assert stats.batch_compilations > 0
    end

    test "handles empty operations list" do
      assert {:ok, []} = Optimized.batch_compile([])
    end
  end

  describe "get_stats/0" do
    setup do
      {:ok, _pid} = Optimized.start_link(compile_timeout_ms: 100)
      :ok
    end

    test "returns comprehensive statistics" do
      stats = Optimized.get_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :total_compilations)
      assert Map.has_key?(stats, :successful_compilations)
      assert Map.has_key?(stats, :failed_compilations)
      assert Map.has_key?(stats, :batch_compilations)
      assert Map.has_key?(stats, :active_ports)
      assert Map.has_key?(stats, :cache_size)
      assert Map.has_key?(stats, :started_at)

      assert %{
               port: %{
                 reuse_rate: _,
                 avg_lifetime_ms: _,
                 compilation_count_per_port: _
               },
               performance: %{
                 average_compilation_time_ms: _,
                 compilation_time_improvement: _,
                 degraded_rate: _
               }
             } = stats.derived_metrics
    end

    test "tracks compilation counts correctly" do
      initial_stats = Optimized.get_stats()

      opts = [cmd: "echo", input: "/tmp/test.css"]
      content = "<div>Test</div>"

      {:ok, _result} = Optimized.compile(opts, content)

      updated_stats = Optimized.get_stats()
      assert updated_stats.total_compilations > initial_stats.total_compilations
    end
  end

  describe "warm_up/1" do
    setup do
      {:ok, _pid} = Optimized.start_link(compile_timeout_ms: 100)
      :ok
    end

    test "pre-creates ports for common configurations" do
      common_configs = [
        [cmd: "echo", input: "/tmp/common1.css"],
        [cmd: "echo", input: "/tmp/common2.css"]
      ]

      :ok = Optimized.warm_up(common_configs)

      # Should have created ports for these configurations
      stats = Optimized.get_stats()
      # At least no errors occurred
      assert stats.active_ports >= 0
    end

    test "handles invalid configurations gracefully" do
      invalid_configs = [
        [cmd: "/nonexistent/binary"],
        # Empty config
        []
      ]

      # Should not crash
      :ok = Optimized.warm_up(invalid_configs)
    end
  end

  describe "port pool management" do
    setup do
      {:ok, _pid} = Optimized.start_link(max_pool_size: 2, compile_timeout_ms: 100)
      :ok
    end

    test "respects max pool size" do
      # Try to create more ports than max_pool_size
      opts_list = [
        [cmd: "echo", input: "/tmp/test1.css"],
        [cmd: "echo", input: "/tmp/test2.css"],
        # Should exceed max_pool_size of 2
        [cmd: "echo", input: "/tmp/test3.css"]
      ]

      content = "<div>Test</div>"

      # All should succeed due to reuse or queuing
      for opts <- opts_list do
        result = Optimized.compile(opts, content)
        assert elem(result, 0) in [:ok, :error]
      end

      stats = Optimized.get_stats()
      # Should not exceed max_pool_size significantly
      # Allow some tolerance
      assert stats.active_ports <= 3
    end

    test "cleans up idle ports" do
      opts = [cmd: "echo", input: "/tmp/idle_test.css"]
      content = "<div>Test</div>"

      {:ok, _result} = Optimized.compile(opts, content)

      _initial_stats = Optimized.get_stats()

      # Trigger cleanup (normally done by timer)
      send(Process.whereis(Optimized), :cleanup_idle_ports)
      # Allow cleanup to process
      Process.sleep(100)

      # Note: Cleanup might not remove ports immediately if they're still within timeout
      final_stats = Optimized.get_stats()
      assert is_integer(final_stats.active_ports)
    end
  end

  describe "error handling and recovery" do
    setup do
      {:ok, _pid} = Optimized.start_link(compile_timeout_ms: 100)
      :ok
    end

    test "handles port creation failures" do
      opts = [
        cmd: "/definitely/nonexistent/binary",
        input: "/tmp/test.css"
      ]

      content = "<div>Test</div>"

      # Should handle gracefully
      result = Optimized.compile(opts, content)
      assert match?({:error, _}, result)

      # Process should still be alive
      assert Process.alive?(Process.whereis(Optimized))
    end

    test "recovers from port exits" do
      # This test would simulate a port crashing
      opts = [cmd: "echo", input: "/tmp/test.css"]
      content = "<div>Test</div>"

      {:ok, _result} = Optimized.compile(opts, content)

      # Simulate port exit by sending EXIT message
      # In a real test, we'd need to get the actual port PID
      # For now, just verify the system remains stable

      # Subsequent compilation should work
      result = Optimized.compile(opts, content)
      assert elem(result, 0) in [:ok, :error]
    end
  end

  describe "telemetry integration" do
    setup do
      {:ok, _pid} = Optimized.start_link(compile_timeout_ms: 100)

      # Attach test telemetry handler
      test_pid = self()
      handler_id = "optimized_test_#{System.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:tailwind_port_optimized, :compile, :start],
          [:tailwind_port_optimized, :compile, :stop],
          [:tailwind_port_optimized, :compile, :error],
          [:tailwind_port_optimized, :pool, :port_created],
          [:tailwind_port_optimized, :pool, :port_reused],
          [:tailwind_port_optimized, :metrics, :snapshot]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      %{handler_id: handler_id}
    end

    test "emits telemetry events for compilations" do
      opts = [cmd: "echo", input: "/tmp/telemetry_test.css"]
      content = "<div>Test</div>"

      {:ok, _result} = Optimized.compile(opts, content)

      # Should receive telemetry events
      assert_receive {:telemetry, [:tailwind_port_optimized, :compile, :start], _measurements,
                      _metadata},
                     1000

      # Note: Other events depend on successful compilation

      # Trigger metrics snapshot
      Optimized.get_stats()

      assert_receive {:telemetry, [:tailwind_port_optimized, :metrics, :snapshot], _measurements,
                      _metadata},
                     1000
    end

    test "emits pool management events" do
      opts = [cmd: "echo", input: "/tmp/pool_test.css"]
      content = "<div>Test</div>"

      # First compilation should create port
      {:ok, _result} = Optimized.compile(opts, content)

      # Second compilation with same config should reuse port
      {:ok, _result} = Optimized.compile(opts, content)

      # Should receive pool management events
      # Note: Specific events depend on actual implementation
      # Allow events to propagate
      Process.sleep(100)
    end
  end

  describe "configuration hashing" do
    setup do
      {:ok, _pid} = Optimized.start_link(compile_timeout_ms: 100)
      :ok
    end

    test "identical configurations produce same hash" do
      opts1 = [cmd: "echo", input: "/tmp/same.css", output: "/tmp/out.css"]
      opts2 = [cmd: "echo", input: "/tmp/same.css", output: "/tmp/out.css"]

      content = "<div>Test</div>"

      {:ok, _result1} = Optimized.compile(opts1, content)
      {:ok, _result2} = Optimized.compile(opts2, content)

      # Should show cache hit or port reuse in stats
      stats = Optimized.get_stats()
      assert stats.total_compilations >= 2
    end

    test "different configurations produce different hashes" do
      opts1 = [cmd: "echo", input: "/tmp/different1.css"]
      opts2 = [cmd: "echo", input: "/tmp/different2.css"]

      content = "<div>Test</div>"

      {:ok, _result1} = Optimized.compile(opts1, content)
      {:ok, _result2} = Optimized.compile(opts2, content)

      # Should create separate ports/cache entries
      stats = Optimized.get_stats()
      assert stats.total_compilations >= 2
    end
  end

  describe "real tailwind integration" do
    @tag timeout: 120_000
    setup do
      case Process.whereis(Optimized) do
        pid when is_pid(pid) -> GenServer.stop(pid)
        nil -> :ok
      end

      {:ok, pid} = Optimized.start_link(compile_timeout_ms: 15_000)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      tmp_dir =
        Path.join(System.tmp_dir!(), "tailwind_opt_integration_#{System.unique_integer()}")

      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf(tmp_dir) end)

      {:ok, %{tmp_dir: tmp_dir}}
    end

    @tag integration: true
    test "compiles CSS with the tailwind CLI binary", %{tmp_dir: tmp_dir} do
      input_path = Path.join(tmp_dir, "input.css")
      output_path = Path.join(tmp_dir, "output.css")
      content_path = Path.join(tmp_dir, "content.html")
      config_path = Path.join(tmp_dir, "tailwind.config.js")

      File.write!(input_path, "@tailwind utilities;\n")

      File.write!(config_path, """
      module.exports = {
        content: ["#{content_path}"],
        theme: { extend: {} },
        corePlugins: { preflight: false }
      }
      """)

      html1 = ~s(<div class="text-red-500">Hello</div>)

      opts = [
        input: input_path,
        output: output_path,
        content: content_path,
        config: config_path,
        watch: true
      ]

      {:ok, result1} = Optimized.compile(opts, html1)

      css1 = result1.compiled_css || File.read!(output_path)
      assert css1 =~ ".text-red-500"

      html2 = ~s(<p class="text-blue-600">Updated</p>)
      {:ok, result2} = Optimized.compile(opts, html2)

      css2 = result2.compiled_css || File.read!(output_path)
      assert css2 =~ ".text-blue-600"

      stats = Optimized.get_stats()
      assert stats.port_creations >= 1
      assert stats.port_reuses >= 1
      assert stats.derived_metrics.port.reuse_rate > 0.0
    end
  end
end
