defmodule Defdo.TailwindPort.TelemetryTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Defdo.TailwindPort.Telemetry

  setup do
    # Capture telemetry events during tests
    telemetry_ref = make_ref()

    events = [
      [:tailwind_port, :compile, :start],
      [:tailwind_port, :compile, :complete],
      [:tailwind_port, :compile, :error],
      [:tailwind_port, :download, :start],
      [:tailwind_port, :download, :complete],
      [:tailwind_port, :download, :error],
      [:tailwind_port, :performance, :compilation],
      [:tailwind_port, :performance, :memory],
      [:tailwind_port, :performance, :cpu],
      [:tailwind_port, :error, :compilation_failed],
      [:tailwind_port, :health, :healthy],
      [:tailwind_port, :health, :degraded],
      [:tailwind_port, :counter, :css_builds],
      [:tailwind_port, :counter, :errors],
      [:tailwind_port, :counter, :test_counter],
      [:tailwind_port, :counter, :test],
      [:tailwind_port, :error, :test],
      [:tailwind_port, :error, :port_exit],
      [:tailwind_port, :histogram, :compile_duration],
      [:tailwind_port, :gauge, :active_processes],
      [:tailwind_port, :span, :compile]
    ]

    :telemetry.attach_many(telemetry_ref, events, &capture_event/4, self())

    on_exit(fn ->
      :telemetry.detach(telemetry_ref)
    end)

    :ok
  end

  describe "span_compilation/3" do
    test "emits start and complete events for successful compilation" do
      result =
        Telemetry.span_compilation(
          fn ->
            # Simulate work
            Process.sleep(10)
            {:ok, "compiled css"}
          end,
          %{project_id: "test_project"}
        )

      assert {:ok, {:ok, "compiled css"}} = result

      # Should receive start event
      assert_receive {[:tailwind_port, :compile, :start], %{system_time: _}, metadata}
      assert metadata.project_id == "test_project"

      # Should receive complete event
      assert_receive {[:tailwind_port, :compile, :complete], measurements, metadata}
      assert measurements.duration_ms >= 10
      assert metadata.project_id == "test_project"
    end

    test "emits error event when compilation fails" do
      error = RuntimeError.exception("compilation failed")

      result =
        Telemetry.span_compilation(
          fn ->
            raise error
          end,
          %{project_id: "failing_project"}
        )

      assert {:error, ^error} = result

      # Should receive start event
      assert_receive {[:tailwind_port, :compile, :start], _, _}

      # Should receive error event
      assert_receive {[:tailwind_port, :compile, :error], measurements, metadata}
      assert measurements.error_count == 1
      assert measurements.duration_ms >= 0
      assert metadata.project_id == "failing_project"
      assert metadata.error != nil

      # Should also receive error tracking event
      assert_receive {[:tailwind_port, :error, :compilation_failed], _, _}
    end

    test "includes custom metadata in events" do
      metadata = %{
        project_id: "proj_123",
        user_id: "user_456",
        css_input_size: 2048
      }

      Telemetry.span_compilation(fn -> :ok end, metadata)

      assert_receive {[:tailwind_port, :compile, :start], _, received_metadata}
      assert received_metadata.project_id == "proj_123"
      assert received_metadata.user_id == "user_456"
      assert received_metadata.css_input_size == 2048
    end

    test "measures execution time accurately" do
      sleep_time = 50

      Telemetry.span_compilation(fn ->
        Process.sleep(sleep_time)
        :ok
      end)

      assert_receive {[:tailwind_port, :compile, :complete], measurements, _}
      # Allow some tolerance for timing
      assert measurements.duration_ms >= sleep_time - 5
      assert measurements.duration_ms <= sleep_time + 20
    end
  end

  describe "track_compilation_performance/2" do
    test "emits performance event with duration" do
      Telemetry.track_compilation_performance(1250, %{
        input_size: 2048,
        output_size: 15360,
        project_id: "perf_test"
      })

      assert_receive {[:tailwind_port, :performance, :compilation], measurements, metadata}
      assert measurements.duration_ms == 1250
      assert measurements.compile_count == 1
      assert measurements.input_size == 2048
      assert measurements.output_size == 15360
      assert metadata.project_id == "perf_test"
    end

    test "only includes numeric measurements" do
      Telemetry.track_compilation_performance(1000, %{
        # Should be included
        input_size: 1024,
        # Should be ignored
        invalid_size: "large",
        # Should be included
        classes_count: 42
      })

      assert_receive {[:tailwind_port, :performance, :compilation], measurements, _}
      assert measurements.input_size == 1024
      assert measurements.classes_count == 42
      refute Map.has_key?(measurements, :invalid_size)
    end
  end

  describe "track_download/3" do
    test "tracks download events with different types" do
      # Start event
      Telemetry.track_download(:start, %{}, %{url: "https://example.com", target: "linux-x64"})
      assert_receive {[:tailwind_port, :download, :start], %{}, metadata}
      assert metadata.url == "https://example.com"

      # Complete event
      Telemetry.track_download(:complete, %{duration_ms: 2500, bytes_downloaded: 15_000_000}, %{
        url: "https://example.com"
      })

      assert_receive {[:tailwind_port, :download, :complete], measurements, _}
      assert measurements.duration_ms == 2500
      assert measurements.bytes_downloaded == 15_000_000

      # Error event
      Telemetry.track_download(:error, %{duration_ms: 1200}, %{error_type: :timeout})
      assert_receive {[:tailwind_port, :download, :error], measurements, metadata}
      assert measurements.duration_ms == 1200
      assert metadata.error_type == :timeout
    end
  end

  describe "track_resource_usage/3" do
    test "tracks different resource types" do
      # Memory usage
      Telemetry.track_resource_usage(:memory, 256, %{process_count: 5})
      assert_receive {[:tailwind_port, :performance, :memory], measurements, metadata}
      assert measurements.memory == 256
      assert metadata.process_count == 5

      # CPU usage
      Telemetry.track_resource_usage(:cpu, 75.5, %{load_average: 2.1})
      assert_receive {[:tailwind_port, :performance, :cpu], measurements, metadata}
      assert measurements.cpu == 75.5
      assert metadata.load_average == 2.1
    end
  end

  describe "track_error/3" do
    test "tracks different error types" do
      error = %RuntimeError{message: "test error"}

      Telemetry.track_error(:compilation_failed, error, %{project_id: "error_test"})

      assert_receive {[:tailwind_port, :error, :compilation_failed], measurements, metadata}
      assert measurements.error_count == 1
      assert metadata.error_type == :compilation_failed
      assert metadata.project_id == "error_test"
      assert String.contains?(metadata.error_details, "test error")
    end

    test "formats different error types correctly" do
      # Exception
      exception = %RuntimeError{message: "runtime error"}
      Telemetry.track_error(:test, exception, %{})
      assert_receive {_, _, metadata}
      assert String.contains?(metadata.error_details, "runtime error")

      # Atom
      Telemetry.track_error(:test, :timeout, %{})
      assert_receive {_, _, metadata}
      assert metadata.error_details == "timeout"

      # String
      Telemetry.track_error(:test, "custom error", %{})
      assert_receive {_, _, metadata}
      assert metadata.error_details == "custom error"

      # Other
      Telemetry.track_error(:test, {:complex, :error}, %{})
      assert_receive {_, _, metadata}
      assert metadata.error_details == "{:complex, :error}"
    end
  end

  describe "track_health/3" do
    test "tracks health status changes" do
      # Healthy status
      Telemetry.track_health(:healthy, %{response_time_ms: 45}, %{check_type: :periodic})
      assert_receive {[:tailwind_port, :health, :healthy], measurements, metadata}
      assert measurements.response_time_ms == 45
      assert metadata.check_type == :periodic

      # Degraded status
      Telemetry.track_health(:degraded, %{error_rate: 0.05}, %{reason: :high_load})
      assert_receive {[:tailwind_port, :health, :degraded], measurements, metadata}
      assert measurements.error_rate == 0.05
      assert metadata.reason == :high_load
    end
  end

  describe "convenience metric functions" do
    test "increment_counter/3" do
      Telemetry.increment_counter(:css_builds, %{tenant: "acme"}, 3)
      assert_receive {[:tailwind_port, :counter, :css_builds], measurements, metadata}
      assert measurements.css_builds == 3
      assert metadata.tenant == "acme"

      # Default increment
      Telemetry.increment_counter(:errors)
      assert_receive {[:tailwind_port, :counter, :errors], measurements, _}
      assert measurements.errors == 1
    end

    test "record_histogram/3" do
      Telemetry.record_histogram(:compile_duration, 1500, %{size: "large"})
      assert_receive {[:tailwind_port, :histogram, :compile_duration], measurements, metadata}
      assert measurements.compile_duration == 1500
      assert metadata.size == "large"
    end

    test "record_gauge/3" do
      Telemetry.record_gauge(:active_processes, 8, %{type: :compilation})
      assert_receive {[:tailwind_port, :gauge, :active_processes], measurements, metadata}
      assert measurements.active_processes == 8
      assert metadata.type == :compilation
    end
  end

  describe "configuration" do
    test "get_config/0 returns default configuration" do
      config = Telemetry.get_config()
      assert config[:enabled] == true
      assert config[:sample_rate] == 1.0
      assert is_map(config[:default_tags])
    end

    test "enabled?/0 respects configuration" do
      original = Application.get_env(:tailwind_port, :telemetry)

      try do
        Application.put_env(:tailwind_port, :telemetry, enabled: true)
        assert Telemetry.enabled?() == true

        Application.put_env(:tailwind_port, :telemetry, enabled: false)
        assert Telemetry.enabled?() == false
      after
        if original do
          Application.put_env(:tailwind_port, :telemetry, original)
        else
          Application.delete_env(:tailwind_port, :telemetry)
        end
      end
    end

    test "events are not emitted when telemetry is disabled" do
      original = Application.get_env(:tailwind_port, :telemetry)

      try do
        Application.put_env(:tailwind_port, :telemetry, enabled: false)

        Telemetry.increment_counter(:test_counter)

        # Should not receive any events
        refute_receive {[:tailwind_port, :counter, :test_counter], _, _}, 100
      after
        if original do
          Application.put_env(:tailwind_port, :telemetry, original)
        else
          Application.delete_env(:tailwind_port, :telemetry)
        end
      end
    end
  end

  describe "metadata enrichment" do
    test "enriches metadata with default values" do
      Telemetry.increment_counter(:test, %{custom: "value"})

      assert_receive {_, _, metadata}
      assert metadata.custom == "value"
      assert is_integer(metadata.timestamp)
      assert metadata.node == Node.self()
      assert is_pid(metadata.pid)
    end

    test "respects default_tags configuration" do
      original = Application.get_env(:tailwind_port, :telemetry)

      try do
        Application.put_env(:tailwind_port, :telemetry,
          enabled: true,
          default_tags: %{service: "test_service", environment: "test"}
        )

        Telemetry.increment_counter(:test)

        assert_receive {_, _, metadata}
        assert metadata.service == "test_service"
        assert metadata.environment == "test"
      after
        if original do
          Application.put_env(:tailwind_port, :telemetry, original)
        else
          Application.delete_env(:tailwind_port, :telemetry)
        end
      end
    end
  end

  # Helper function to capture telemetry events
  defp capture_event(event_name, measurements, metadata, test_pid) do
    send(test_pid, {event_name, measurements, metadata})
  end
end
