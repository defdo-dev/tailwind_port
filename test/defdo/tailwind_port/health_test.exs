defmodule Defdo.TailwindPort.HealthTest do
  @moduledoc false
  use ExUnit.Case
  alias Defdo.TailwindPort.Health

  describe "create_initial_health/0" do
    test "creates health with initial values" do
      health = Health.create_initial_health()

      assert is_integer(health.created_at)
      assert is_integer(health.last_activity)
      assert health.total_outputs == 0
      assert health.css_builds == 0
      assert health.errors == 0
    end

    test "created_at and last_activity are close to current time" do
      before = System.system_time()
      health = Health.create_initial_health()
      after_time = System.system_time()

      assert health.created_at >= before
      assert health.created_at <= after_time
      assert health.last_activity >= before
      assert health.last_activity <= after_time
    end
  end

  describe "update_metrics/2" do
    setup do
      {:ok, health: Health.create_initial_health()}
    end

    test "increments total_outputs for any data", %{health: health} do
      updated = Health.update_metrics(health, "any output")
      assert updated.total_outputs == 1
    end

    test "updates last_activity timestamp", %{health: health} do
      original_time = health.last_activity
      # Ensure time difference
      Process.sleep(1)
      updated = Health.update_metrics(health, "output")
      assert updated.last_activity > original_time
    end

    test "increments css_builds for CSS-related output", %{health: health} do
      # Test various CSS-related patterns
      css_outputs = [
        "Done in 45ms",
        "Rebuilding...",
        "Built successfully",
        "CSS generated",
        "{ some: 'css' }",
        "}",
        "Watching for changes"
      ]

      Enum.each(css_outputs, fn output ->
        updated = Health.update_metrics(health, output)
        assert updated.css_builds == 1, "Failed for output: #{output}"
      end)
    end

    test "does not increment css_builds for non-CSS output", %{health: health} do
      non_css_outputs = [
        "Loading configuration",
        "Starting process",
        "Error occurred"
      ]

      Enum.each(non_css_outputs, fn output ->
        updated = Health.update_metrics(health, output)
        assert updated.css_builds == 0, "Incorrectly incremented for: #{output}"
      end)
    end

    test "handles multiple updates correctly", %{health: health} do
      health
      |> Health.update_metrics("First output")
      |> Health.update_metrics("Done in 30ms")
      |> Health.update_metrics("Third output")
      |> then(fn final_health ->
        assert final_health.total_outputs == 3
        # Only one CSS-related
        assert final_health.css_builds == 1
      end)
    end
  end

  describe "increment_errors/1" do
    test "increments error count" do
      health = Health.create_initial_health()
      updated = Health.increment_errors(health)
      assert updated.errors == 1

      updated2 = Health.increment_errors(updated)
      assert updated2.errors == 2
    end
  end

  describe "detect_readiness/1" do
    test "detects readiness from various indicators" do
      ready_patterns = [
        "Rebuilding...",
        "Done in 45ms",
        "Built successfully",
        "Watching for changes",
        "Ready to build",
        "Any non-empty output"
      ]

      Enum.each(ready_patterns, fn pattern ->
        assert Health.detect_readiness(pattern), "Failed to detect readiness for: #{pattern}"
      end)
    end

    test "returns false for empty string" do
      refute Health.detect_readiness("")
    end

    test "returns true for any non-empty string" do
      assert Health.detect_readiness("x")
      assert Health.detect_readiness("random output")
    end
  end

  describe "calculate_health_info/1" do
    test "calculates comprehensive health info" do
      health = Health.create_initial_health()
      port = Port.open({:spawn, "echo test"}, [:binary])

      state = %{
        health: health,
        port: port,
        port_ready: true
      }

      info = Health.calculate_health_info(state)

      assert is_float(info.uptime_seconds)
      assert info.uptime_seconds >= 0
      assert info.port_ready == true
      assert is_boolean(info.port_active)
      assert info.total_outputs == 0
      assert info.css_builds == 0
      assert info.errors == 0
      assert is_integer(info.last_activity)
      assert is_float(info.last_activity_seconds_ago)
      assert is_integer(info.created_at)

      Port.close(port)
    end

    test "handles state without health field" do
      state = %{port_ready: false}
      info = Health.calculate_health_info(state)

      assert is_map(info)
      assert is_float(info.uptime_seconds)
      assert info.port_ready == false
    end

    test "calculates uptime correctly" do
      # Create health with known timestamp
      # 5 seconds ago
      past_time = System.system_time() - 5_000_000_000

      health = %{
        created_at: past_time,
        last_activity: past_time,
        total_outputs: 0,
        css_builds: 0,
        errors: 0
      }

      state = %{health: health, port_ready: false}
      info = Health.calculate_health_info(state)

      assert info.uptime_seconds >= 5.0
      # Should be close to 5 seconds
      assert info.uptime_seconds < 6.0
    end

    test "detects active port correctly" do
      port = Port.open({:spawn, "echo test"}, [:binary])
      state = %{health: Health.create_initial_health(), port: port}

      info = Health.calculate_health_info(state)
      assert info.port_active == true

      Port.close(port)

      info_after_close = Health.calculate_health_info(state)
      assert info_after_close.port_active == false
    end
  end

  describe "mark_port_ready/2" do
    test "marks port ready when data indicates readiness" do
      state = %{
        port_ready: false,
        startup_timeout_ref: nil,
        waiting_callers: []
      }

      updated_state = Health.mark_port_ready(state, "Rebuilding...")
      assert updated_state.port_ready == true
      assert updated_state.waiting_callers == []
    end

    test "does not mark ready for non-ready data" do
      state = %{port_ready: false}
      # Using empty string which should not indicate readiness
      updated_state = Health.mark_port_ready(state, "")
      assert updated_state.port_ready == false
    end

    test "cancels startup timeout when marked ready" do
      timeout_ref = make_ref()

      state = %{
        port_ready: false,
        startup_timeout_ref: timeout_ref,
        waiting_callers: []
      }

      updated_state = Health.mark_port_ready(state, "Done in 30ms")
      assert updated_state.port_ready == true
      assert updated_state.startup_timeout_ref == nil
    end

    test "handles missing waiting_callers key" do
      state = %{port_ready: false}
      updated_state = Health.mark_port_ready(state, "Ready")
      assert updated_state.port_ready == true
      assert updated_state.waiting_callers == []
    end
  end

  describe "maybe_mark_port_ready/2" do
    test "skips processing when already ready" do
      state = %{port_ready: true, some_field: "original"}
      result = Health.maybe_mark_port_ready(state, "Rebuilding...")
      # Should return unchanged
      assert result == state
    end

    test "processes when port_ready is false" do
      state = %{port_ready: false, waiting_callers: []}
      result = Health.maybe_mark_port_ready(state, "Ready")
      assert result.port_ready == true
    end

    test "processes when port_ready key is missing" do
      state = %{waiting_callers: []}
      result = Health.maybe_mark_port_ready(state, "Ready")
      assert result.port_ready == true
    end
  end

  describe "normalize_health/1" do
    test "adds missing fields with defaults" do
      partial_health = %{total_outputs: 5}
      normalized = Health.normalize_health(partial_health)

      # Preserved
      assert normalized.total_outputs == 5
      # Added default
      assert normalized.css_builds == 0
      # Added default
      assert normalized.errors == 0
      assert is_integer(normalized.created_at)
      assert is_integer(normalized.last_activity)
    end

    test "preserves existing fields" do
      complete_health = Health.create_initial_health()
      normalized = Health.normalize_health(complete_health)
      assert normalized == complete_health
    end

    test "overwrites defaults with provided values" do
      custom_health = %{
        total_outputs: 10,
        css_builds: 5,
        errors: 2
      }

      normalized = Health.normalize_health(custom_health)
      assert normalized.total_outputs == 10
      assert normalized.css_builds == 5
      assert normalized.errors == 2
    end
  end

  describe "edge cases and error handling" do
    test "handles invalid input gracefully" do
      # These should not crash
      assert_raise FunctionClauseError, fn ->
        Health.update_metrics("not a map", "data")
      end

      assert_raise FunctionClauseError, fn ->
        # Non-binary data
        Health.update_metrics(%{}, 123)
      end
    end

    test "works with large numbers" do
      health = %{
        created_at: System.system_time(),
        last_activity: System.system_time(),
        total_outputs: 999_999,
        css_builds: 100_000,
        errors: 50_000
      }

      updated = Health.update_metrics(health, "test")
      assert updated.total_outputs == 1_000_000

      error_updated = Health.increment_errors(updated)
      assert error_updated.errors == 50_001
    end

    test "state without port field" do
      state = %{health: Health.create_initial_health()}
      info = Health.calculate_health_info(state)
      assert info.port_active == false
    end

    test "state with nil port" do
      state = %{
        health: Health.create_initial_health(),
        port: nil
      }

      info = Health.calculate_health_info(state)
      assert info.port_active == false
    end
  end
end
