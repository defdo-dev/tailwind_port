defmodule Defdo.TailwindPortHealthTest do
  @moduledoc false
  use ExUnit.Case
  alias Defdo.TailwindPort.Standalone

  test "health metrics are tracked" do
    name = :health_test_port

    assert {:ok, _pid} = Standalone.start_link(name: name, opts: [])

    # Get initial health
    health = Standalone.health(name)

    assert is_map(health)
    assert is_number(health.created_at)
    assert is_number(health.last_activity)
    assert health.total_outputs == 0
    assert health.css_builds == 0
    assert health.errors == 0
    assert is_number(health.uptime_seconds)
    assert health.uptime_seconds >= 0

    Standalone.terminate(name)
  end

  test "health metrics update from readiness output" do
    name = :health_activity_test

    # This test exercises health/readiness tracking, not end-to-end Tailwind compilation.
    # Use a deterministic command that emits a readiness-like line immediately.
    assert {:ok, _pid} =
             Standalone.start_link(name: name, cmd: echo_command!(), opts: ["Done in 45ms"])

    # Wait for some activity
    :ok = Standalone.wait_until_ready(name, 5000)

    # Check health after activity
    health = Standalone.health(name)

    # Should have some activity now
    assert health.port_ready == true
    # Note: exact metrics depend on Tailwind output, so we just check they exist
    assert is_number(health.total_outputs)
    assert is_number(health.css_builds)

    Standalone.terminate(name)
  end

  test "error output does not mark the port as ready" do
    name = :health_error_output_test
    script_path = failing_script_path!()

    on_exit(fn ->
      File.rm(script_path)

      case Process.whereis(name) do
        nil -> :ok
        _pid -> Standalone.terminate(name)
      end
    end)

    assert {:ok, _pid} =
             Standalone.start_link(name: name, cmd: script_path, opts: ["-i", "/tmp/ignored.css"])

    assert :ok = wait_for(fn -> Standalone.state(name).exit_status == 1 end)

    refute Standalone.ready?(name, 100)

    health = Standalone.health(name)
    refute health.port_ready
    assert health.errors > 0
    assert Standalone.state(name).exit_status == 1
  end

  defp echo_command! do
    System.find_executable("echo") || raise "echo executable not found"
  end

  defp failing_script_path! do
    path =
      Path.join(
        System.tmp_dir!(),
        "tailwind_port_fail_#{System.unique_integer([:positive])}.sh"
      )

    File.write!(
      path,
      """
      #!/bin/sh
      echo "Error: failed to compile" >&2
      exit 1
      """
    )

    File.chmod!(path, 0o755)
    path
  end

  # 2s, not 500ms: this waits for an OS process to start and exit, and the
  # suite now runs real CLI stubs elsewhere, so the box can be busy enough for
  # a 500ms budget to expire before the exit is reaped. The assertion is about
  # the eventual exit status, never about how quickly it arrives.
  defp wait_for(fun, attempts \\ 80)

  defp wait_for(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(25)
      wait_for(fun, attempts - 1)
    end
  end

  defp wait_for(_fun, 0), do: {:error, :timeout}
end
