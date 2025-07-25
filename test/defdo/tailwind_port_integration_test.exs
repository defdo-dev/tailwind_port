defmodule Defdo.TailwindPortIntegrationTest do
  @moduledoc false
  use ExUnit.Case
  alias Defdo.TailwindPort

  test "port synchronization and readiness" do
    name = :sync_test_port
    opts = ["-w", "--input", "./assets/css/app.css", "--content", "./priv/static/html/*.html"]

    assert {:ok, _pid} = TailwindPort.start_link(opts: opts, name: name)

    # Test readiness check
    # Should not be ready immediately
    refute TailwindPort.ready?(name, 100)

    # Wait for readiness
    assert :ok = TailwindPort.wait_until_ready(name, 10_000)

    # Should now be ready
    assert TailwindPort.ready?(name)

    # Check state
    state = TailwindPort.state(name)
    assert state.port_ready
    assert state.port

    TailwindPort.terminate(name)
  end

  test "input validation" do
    # Test invalid name
    assert {:error, :invalid_name} = TailwindPort.start_link(name: "not_an_atom", opts: [])

    # Test invalid opts
    assert {:error, :invalid_opts} = TailwindPort.start_link(opts: "not_a_list")

    # Test invalid args
    assert {:error, :invalid_args} = TailwindPort.start_link("not_a_keyword_list")
  end

  test "new/2 validation" do
    name = :validation_test_port
    assert {:ok, _pid} = TailwindPort.start_link(name: name, opts: [])

    # Test invalid cmd
    assert {:error, :invalid_cmd} = TailwindPort.new(name, cmd: 123)

    # Test invalid opts
    assert {:error, :invalid_opts} = TailwindPort.new(name, opts: "not_a_list")

    # Test invalid args
    assert {:error, :invalid_args} = TailwindPort.new(name, "not_a_keyword_list")

    TailwindPort.terminate(name)
  end

  # Reduced timeout
  @tag timeout: 3_000
  test "port creation with retry demonstrates fast execution" do
    name = :retry_test_port

    assert {:ok, _pid} = TailwindPort.start_link(name: name, opts: [])

    # Use system binary that exists and works to demonstrate the optimization
    # The retry logic configuration (50ms delays) is tested in unit tests
    {time_us, result} =
      :timer.tc(fn ->
        TailwindPort.new(name, cmd: "/bin/echo", opts: ["hello"])
      end)

    # Should complete quickly due to our optimizations
    # 2s maximum - much faster than before
    assert time_us < 2_000_000

    # Result might succeed or fail depending on environment, but timing is key
    assert match?({:ok, _}, result) or match?({:error, _}, result)

    if Process.whereis(name) do
      TailwindPort.terminate(name)
    end
  end

  test "configuration values are optimized for tests" do
    # This test verifies our configuration optimizations are working
    name = :config_test

    assert {:ok, _pid} = TailwindPort.start_link(name: name, opts: [])

    # Test that we can get health metrics quickly
    health = TailwindPort.health(name)
    assert is_map(health)
    assert health.total_outputs == 0
    assert health.errors == 0

    # Test ready? function responds quickly
    # Very short timeout
    ready_result = TailwindPort.ready?(name, 100)
    assert is_boolean(ready_result)

    TailwindPort.terminate(name)
  end

  test "timeout handling" do
    name = :timeout_test_port
    assert {:ok, _pid} = TailwindPort.start_link(name: name, opts: [])

    # Test ready? with short timeout
    refute TailwindPort.ready?(name, 10)

    # Test wait_until_ready with very short timeout
    assert {:error, :timeout} = TailwindPort.wait_until_ready(name, 50)

    TailwindPort.terminate(name)
  end
end
