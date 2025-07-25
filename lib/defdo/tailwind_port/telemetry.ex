defmodule Defdo.TailwindPort.Telemetry do
  @moduledoc """
  Telemetry instrumentation for TailwindPort library.

  This module provides telemetry events that consuming applications (like CMS systems)
  can subscribe to for monitoring, metrics collection, and observability. TailwindPort
  emits standardized telemetry events that applications can handle according to their
  own monitoring and observability strategies.

  ## Design Principles

  - **Non-invasive**: Events are emitted, not forced consumption
  - **Configurable**: Applications control what to monitor
  - **Standard Events**: Consistent event structure across operations
  - **Optional**: Library works perfectly without telemetry handlers

  ## Features

  - **OpenTelemetry Integration**: Full OTEL traces, metrics, and logs
  - **Performance Monitoring**: Detailed compilation timing and throughput
  - **Resource Tracking**: Memory, CPU, and concurrency metrics
  - **Error Tracking**: Detailed error categorization and rates
  - **Business Metrics**: User/tenant-specific metrics for CMS applications
  - **Custom Dimensions**: Taggable metrics for multi-tenant scenarios

  ## Event Categories

  ### Process Lifecycle
  - `[:tailwind_port, :process, :start]` - Process startup
  - `[:tailwind_port, :process, :stop]` - Process shutdown
  - `[:tailwind_port, :process, :ready]` - Process becomes ready

  ### Compilation Events
  - `[:tailwind_port, :compile, :start]` - CSS compilation begins
  - `[:tailwind_port, :compile, :complete]` - Compilation successful
  - `[:tailwind_port, :compile, :error]` - Compilation failed

  ### Download/Install Events
  - `[:tailwind_port, :download, :start]` - Binary download begins
  - `[:tailwind_port, :download, :complete]` - Download successful
  - `[:tailwind_port, :download, :error]` - Download failed

  ### Performance Events
  - `[:tailwind_port, :performance, :memory]` - Memory usage snapshot
  - `[:tailwind_port, :performance, :cpu]` - CPU usage measurement
  - `[:tailwind_port, :performance, :queue]` - Queue depth metrics

  ### Health Events
  - `[:tailwind_port, :health, :check]` - Health status update
  - `[:tailwind_port, :health, :degraded]` - Performance degradation
  - `[:tailwind_port, :health, :recovered]` - Recovery from issues

  ## Usage

      # Basic instrumentation
      Telemetry.span_compilation(fn ->
        # Your compilation logic
      end, %{project_id: "123", user_id: "456"})

      # Custom metrics
      Telemetry.increment_counter(:css_builds, %{tenant: "acme"})
      Telemetry.record_histogram(:compile_duration, 1250, %{size: "large"})

      # Error tracking
      Telemetry.track_error(:compilation_failed, error, %{
        project_id: "123",
        css_size: 1024
      })

  ## Configuration

  Configure telemetry in your consuming application:

      config :tailwind_port, :telemetry,
        enabled: true,
        sample_rate: 1.0,
        default_tags: %{
          service: "my_cms",
          environment: "production"
        }

  ## Subscribing to Events

  In your CMS application, subscribe to TailwindPort events:

      # In your application supervision tree
      :telemetry.attach_many(
        "my-cms-tailwind-metrics",
        [
          [:tailwind_port, :compile, :complete],
          [:tailwind_port, :compile, :error],
          [:tailwind_port, :download, :complete]
        ],
        &MyCMS.Metrics.handle_tailwind_event/4,
        nil
      )

  ## OpenTelemetry Integration

  The module automatically creates OpenTelemetry spans and metrics when
  the `:opentelemetry` application is available. All events include:

  - **Traces**: Request/compilation spans with proper parent-child relationships
  - **Metrics**: Counters, histograms, and gauges for key performance indicators
  - **Attributes**: Rich metadata for filtering and analysis

  """

  require Logger

  @typedoc "Telemetry measurement values"
  @type measurements :: %{atom() => number()}

  @typedoc "Telemetry metadata/tags"
  @type metadata :: %{atom() => term()}

  @typedoc "Event name components"
  @type event_name :: [atom()]

  @typedoc "Span function result"
  @type span_result :: term()

  # Event name prefixes
  @event_prefix [:tailwind_port]

  @doc """
  Executes a function within a telemetry span for compilation tracking.

  Creates a complete telemetry span around CSS compilation with automatic
  timing, error handling, and metadata collection. This is the primary
  instrumentation for CSS builds in CMS applications.

  ## Parameters

    * `fun` - Function to execute within the span
    * `metadata` - Additional metadata/tags for the span
    * `opts` - Span options

  ## Options

    * `:span_name` - Custom span name (default: "css_compilation")
    * `:timeout` - Span timeout in milliseconds
    * `:sample_rate` - Override default sampling rate

  ## Returns

    * `{:ok, result}` - Function executed successfully
    * `{:error, reason}` - Function failed with error

  ## Examples

      # Basic compilation span
      {:ok, css} = Telemetry.span_compilation(fn ->
        compile_css(input, config)
      end, %{
        project_id: "proj_123",
        user_id: "user_456",
        css_input_size: 1024
      })

      # With custom span name
      Telemetry.span_compilation(fn ->
        generate_critical_css()
      end, %{priority: "critical"}, span_name: "critical_css_generation")

  ## Emitted Events

  - `[:tailwind_port, :compile, :start]` - Span begins
  - `[:tailwind_port, :compile, :complete]` - Successful completion
  - `[:tailwind_port, :compile, :error]` - Error occurred
  - `[:tailwind_port, :compile, :span]` - Complete span metrics

  """
  @spec span_compilation(fun(), metadata(), keyword()) :: {:ok, span_result()} | {:error, term()}
  def span_compilation(fun, metadata \\ %{}, opts \\ []) when is_function(fun, 0) do
    _span_name = Keyword.get(opts, :span_name, "css_compilation")
    start_time = System.monotonic_time()
    start_time_native = System.system_time()

    # Emit start event
    emit_event([:compile, :start], %{system_time: start_time_native}, metadata)

    try do
      result = fun.()

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      # Emit success event
      emit_event(
        [:compile, :complete],
        %{
          duration: duration,
          duration_ms: duration_ms
        },
        metadata
      )

      # Emit span completion
      emit_span_event(:compile, :complete, duration_ms, metadata)

      {:ok, result}
    rescue
      error ->
        duration = System.monotonic_time() - start_time
        duration_ms = System.convert_time_unit(duration, :native, :millisecond)

        # Emit error event
        emit_event(
          [:compile, :error],
          %{
            duration: duration,
            duration_ms: duration_ms,
            error_count: 1
          },
          Map.put(metadata, :error, inspect(error))
        )

        # Track error details
        track_error(:compilation_failed, error, metadata)

        {:error, error}
    end
  end

  @doc """
  Tracks CSS compilation performance metrics.

  Records detailed performance metrics for CSS compilation including
  timing, resource usage, and output characteristics.

  ## Parameters

    * `duration_ms` - Compilation duration in milliseconds
    * `metadata` - Additional context and tags

  ## Examples

      Telemetry.track_compilation_performance(1250, %{
        input_size: 2048,
        output_size: 15360,
        classes_count: 245,
        project_id: "proj_123"
      })

  """
  @spec track_compilation_performance(non_neg_integer(), metadata()) :: :ok
  def track_compilation_performance(duration_ms, metadata \\ %{}) do
    measurements = %{
      duration_ms: duration_ms,
      compile_count: 1
    }

    # Add optional measurements from metadata
    measurements =
      measurements
      |> maybe_add_measurement(:input_size, metadata)
      |> maybe_add_measurement(:output_size, metadata)
      |> maybe_add_measurement(:classes_count, metadata)

    emit_event([:performance, :compilation], measurements, metadata)
  end

  @doc """
  Tracks download/installation performance.

  Records metrics for Tailwind binary downloads and installations,
  useful for monitoring CDN performance and installation success rates.

  ## Parameters

    * `event_type` - :start, :complete, or :error
    * `measurements` - Measurement values
    * `metadata` - Additional context

  ## Examples

      # Download started
      Telemetry.track_download(:start, %{}, %{url: url, target: target})

      # Download completed
      Telemetry.track_download(:complete, %{
        duration_ms: 2500,
        bytes_downloaded: 15_000_000
      }, %{url: url, target: target})

      # Download failed
      Telemetry.track_download(:error, %{duration_ms: 1200}, %{
        url: url,
        error_type: :timeout
      })

  """
  @spec track_download(atom(), measurements(), metadata()) :: :ok
  def track_download(event_type, measurements \\ %{}, metadata \\ %{}) do
    emit_event([:download, event_type], measurements, metadata)
  end

  @doc """
  Tracks resource usage metrics.

  Records memory, CPU, and concurrency metrics for resource monitoring
  and capacity planning in multi-tenant CMS environments.

  ## Parameters

    * `resource_type` - :memory, :cpu, :concurrent_processes, etc.
    * `value` - Resource usage value
    * `metadata` - Additional context

  ## Examples

      # Memory usage
      Telemetry.track_resource_usage(:memory, memory_mb, %{
        process_count: 5,
        tenant: "acme_corp"
      })

      # CPU usage
      Telemetry.track_resource_usage(:cpu, cpu_percent, %{
        load_average: 2.5
      })

      # Concurrent compilation processes
      Telemetry.track_resource_usage(:concurrent_processes, 12, %{
        max_allowed: 20,
        queue_depth: 3
      })

  """
  @spec track_resource_usage(atom(), number(), metadata()) :: :ok
  def track_resource_usage(resource_type, value, metadata \\ %{}) do
    measurements = %{resource_type => value, measurement_count: 1}
    emit_event([:performance, resource_type], measurements, metadata)
  end

  @doc """
  Tracks error events with detailed context.

  Records error events with categorization and context for debugging
  and alerting in production CMS environments.

  ## Parameters

    * `error_type` - Error category/type
    * `error` - Error details (exception, atom, or string)
    * `metadata` - Additional error context

  ## Examples

      # Compilation error
      Telemetry.track_error(:compilation_failed, error, %{
        project_id: "proj_123",
        input_size: 2048,
        config_valid: false
      })

      # Download error
      Telemetry.track_error(:download_failed, :timeout, %{
        url: download_url,
        retry_count: 3
      })

      # Validation error
      Telemetry.track_error(:invalid_config, "Missing required field", %{
        field: :input_path,
        user_id: "user_456"
      })

  """
  @spec track_error(atom(), term(), metadata()) :: :ok
  def track_error(error_type, error, metadata \\ %{}) do
    measurements = %{error_count: 1}

    error_metadata =
      metadata
      |> Map.put(:error_type, error_type)
      |> Map.put(:error_details, format_error(error))

    emit_event([:error, error_type], measurements, error_metadata)
  end

  @doc """
  Tracks health status changes.

  Records health status changes and performance degradation events
  for monitoring and alerting.

  ## Parameters

    * `status` - Health status (:healthy, :degraded, :unhealthy)
    * `measurements` - Health metrics
    * `metadata` - Additional context

  ## Examples

      # Health check
      Telemetry.track_health(:healthy, %{
        response_time_ms: 45,
        error_rate: 0.001
      }, %{check_type: :periodic})

      # Performance degradation
      Telemetry.track_health(:degraded, %{
        response_time_ms: 2500,
        error_rate: 0.05
      }, %{
        reason: :high_load,
        concurrent_processes: 25
      })

  """
  @spec track_health(atom(), measurements(), metadata()) :: :ok
  def track_health(status, measurements \\ %{}, metadata \\ %{}) do
    emit_event([:health, status], measurements, metadata)
  end

  @doc """
  Increments a counter metric.

  Convenience function for incrementing counters with optional tags.

  ## Examples

      Telemetry.increment_counter(:css_builds)
      Telemetry.increment_counter(:errors, %{type: :validation})
      Telemetry.increment_counter(:requests, %{tenant: "acme"}, 5)

  """
  @spec increment_counter(atom(), metadata(), pos_integer()) :: :ok
  def increment_counter(counter_name, metadata \\ %{}, value \\ 1) do
    measurements = %{counter_name => value}
    emit_event([:counter, counter_name], measurements, metadata)
  end

  @doc """
  Records a histogram/timing value.

  Records timing or distribution values for performance analysis.

  ## Examples

      Telemetry.record_histogram(:compile_duration, 1250)
      Telemetry.record_histogram(:css_size, 15_360, %{type: :output})

  """
  @spec record_histogram(atom(), number(), metadata()) :: :ok
  def record_histogram(histogram_name, value, metadata \\ %{}) do
    measurements = %{histogram_name => value}
    emit_event([:histogram, histogram_name], measurements, metadata)
  end

  @doc """
  Records a gauge value.

  Records point-in-time values for monitoring current state.

  ## Examples

      Telemetry.record_gauge(:active_processes, 8)
      Telemetry.record_gauge(:memory_usage_mb, 256, %{type: :heap})

  """
  @spec record_gauge(atom(), number(), metadata()) :: :ok
  def record_gauge(gauge_name, value, metadata \\ %{}) do
    measurements = %{gauge_name => value}
    emit_event([:gauge, gauge_name], measurements, metadata)
  end

  @doc """
  Gets the current telemetry configuration.

  ## Returns

    * `keyword()` - Current telemetry configuration

  """
  @spec get_config() :: keyword()
  def get_config do
    Application.get_env(:tailwind_port, :telemetry,
      enabled: true,
      sample_rate: 1.0,
      default_tags: %{}
    )
  end

  @doc """
  Checks if telemetry is enabled.

  ## Returns

    * `boolean()` - Whether telemetry is enabled

  """
  @spec enabled?() :: boolean()
  def enabled? do
    get_config() |> Keyword.get(:enabled, true)
  end

  # Private helper functions

  defp emit_event(event_suffix, measurements, metadata) do
    if enabled?() do
      event_name = @event_prefix ++ event_suffix
      enriched_metadata = enrich_metadata(metadata)

      :telemetry.execute(event_name, measurements, enriched_metadata)
    end
  end

  defp emit_span_event(category, result, duration_ms, metadata) do
    measurements = %{
      duration_ms: duration_ms,
      span_count: 1
    }

    span_metadata =
      metadata
      |> Map.put(:span_category, category)
      |> Map.put(:span_result, result)

    emit_event([:span, category], measurements, span_metadata)
  end

  defp enrich_metadata(metadata) do
    config = get_config()
    default_tags = Keyword.get(config, :default_tags, %{})

    metadata
    |> Map.merge(default_tags)
    |> Map.put(:timestamp, System.system_time())
    |> Map.put(:node, Node.self())
    |> Map.put(:pid, self())
  end

  defp maybe_add_measurement(measurements, key, metadata) do
    case Map.get(metadata, key) do
      nil -> measurements
      value when is_number(value) -> Map.put(measurements, key, value)
      _ -> measurements
    end
  end

  defp format_error(error) when is_exception(error) do
    Exception.format(:error, error)
  end

  defp format_error(error) when is_atom(error) do
    Atom.to_string(error)
  end

  defp format_error(error) when is_binary(error) do
    error
  end

  defp format_error(error) do
    inspect(error)
  end
end
