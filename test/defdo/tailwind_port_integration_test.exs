defmodule Defdo.TailwindPortIntegrationTest do
  @moduledoc false
  use ExUnit.Case
  alias Defdo.TailwindPort

  @tag :capture_log
  test "port synchronization and readiness" do
    name = :sync_test_port
    opts = ["-w", "--input", "./assets/css/app.css", "--content", "./priv/static/html/*.html"]

    assert {:ok, _pid} = TailwindPort.start_link(opts: opts, name: name)

    # Test readiness check
    refute TailwindPort.ready?(name, 100)  # Should not be ready immediately

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

  @tag :capture_log
  test "input validation" do
    # Test invalid name
    assert {:error, :invalid_name} = TailwindPort.start_link(name: "not_an_atom", opts: [])

    # Test invalid opts
    assert {:error, :invalid_opts} = TailwindPort.start_link(opts: "not_a_list")

    # Test invalid args
    assert {:error, :invalid_args} = TailwindPort.start_link("not_a_keyword_list")
  end

  @tag :capture_log
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

  @tag :capture_log
  test "port creation with retry" do
    name = :retry_test_port
    
    # Use invalid command to trigger retries
    invalid_cmd = "/nonexistent/command"
    
    assert {:ok, _pid} = TailwindPort.start_link(name: name, opts: [])
    
    # This should fail after retries
    assert {:error, _reason} = TailwindPort.new(name, cmd: invalid_cmd, opts: ["-h"])
    
    TailwindPort.terminate(name)
  end

  @tag :capture_log
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