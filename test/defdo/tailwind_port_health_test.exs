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

  test "health metrics update with port activity" do
    name = :health_activity_test
    opts = ["-i", "./assets/css/app.css", "--content", "./priv/static/html/*.html", "-m"]

    assert {:ok, _pid} = Standalone.start_link(name: name, opts: opts)

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
end
