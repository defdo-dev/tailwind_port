defmodule Defdo.TailwindPort.PoolTelemetry do
  @moduledoc """
  Comprehensive telemetry system for TailwindPort.Pool.

  This module provides advanced observability features including:
  - Real-time performance metrics
  - Pool efficiency analysis
  - Compilation pattern insights
  - Resource utilization tracking
  - Alert generation for anomalies

  ## Events Emitted

  ### Compilation Events
  - `[:tailwind_port_pool, :compile, :start]` - Compilation started
  - `[:tailwind_port_pool, :compile, :stop]` - Compilation completed successfully
  - `[:tailwind_port_pool, :compile, :error]` - Compilation failed

  ### Pool Management Events
  - `[:tailwind_port_pool, :pool, :port_created]` - New port created
  - `[:tailwind_port_pool, :pool, :port_reused]` - Existing port reused
  - `[:tailwind_port_pool, :pool, :port_terminated]` - Port terminated
  - `[:tailwind_port_pool, :pool, :exhausted]` - Pool reached capacity limit

  ### Maintenance Events
  - `[:tailwind_port_pool, :maintenance, :cleanup_completed]` - Cleanup cycle completed

  ### KPI Snapshot
  - `[:tailwind_port_pool, :metrics, :snapshot]` – Derived KPIs emitted by
    `Defdo.TailwindPort.Pool.get_stats/0`. Hook into this event via
    `Defdo.TailwindPort.Metrics` to export gauges to Prometheus, StatsD, or
    other telemetry reporters.

  ## Usage

      # Attach comprehensive monitoring
      TailwindPort.PoolTelemetry.attach_default_handlers()

      # Attach custom handlers
      TailwindPort.PoolTelemetry.attach_handler(:my_monitor, &MyModule.handle_event/4)

      # Get current metrics
      metrics = TailwindPort.PoolTelemetry.get_current_metrics()

      # Generate performance report
      TailwindPort.PoolTelemetry.generate_report()
  """

  require Logger

  @events [
    [:tailwind_port_pool, :compile, :start],
    [:tailwind_port_pool, :compile, :stop],
    [:tailwind_port_pool, :compile, :error],
    [:tailwind_port_pool, :pool, :port_created],
    [:tailwind_port_pool, :pool, :port_reused],
    [:tailwind_port_pool, :pool, :port_terminated],
    [:tailwind_port_pool, :pool, :exhausted],
    [:tailwind_port_pool, :maintenance, :cleanup_completed],
    [:tailwind_port_pool, :metrics, :snapshot]
  ]

  @doc """
  Attach default telemetry handlers for monitoring and logging.
  """
  @spec attach_default_handlers() :: :ok | {:error, term()}
  def attach_default_handlers do
    handler_config = %{
      log_level: :info,
      metrics_enabled: true,
      alert_thresholds: %{
        error_rate: 0.1,
        # Increased from 5000ms to 15_000ms (15 seconds)
        avg_compilation_time: 15_000,
        pool_utilization: 0.9
      }
    }

    attach_handler(
      "tailwind_pool_default_monitor",
      &__MODULE__.handle_default_event/4,
      handler_config
    )
  end

  @doc """
  Attach a custom telemetry handler.
  """
  @spec attach_handler(String.t(), function(), any()) :: :ok | {:error, term()}
  def attach_handler(handler_id, handler_fun, config \\ nil) do
    :telemetry.attach_many(
      handler_id,
      @events,
      handler_fun,
      config
    )
  end

  @doc """
  Detach a telemetry handler.
  """
  @spec detach_handler(String.t()) :: :ok | {:error, term()}
  def detach_handler(handler_id) do
    :telemetry.detach(handler_id)
  end

  @doc """
  Get current performance metrics aggregated from telemetry events.
  """
  @spec get_current_metrics() :: map()
  def get_current_metrics do
    case :persistent_term.get(:optimized_telemetry_metrics, nil) do
      nil -> init_metrics()
      metrics -> metrics
    end
  end

  @doc """
  Generate a comprehensive performance report.
  """
  @spec generate_report() :: String.t()
  def generate_report do
    metrics = get_current_metrics()

    """
    🚀 TailwindPort Pool Performance Report
    ==========================================

    ## Compilation Statistics
    - Total Compilations: #{metrics.total_compilations}
    - Success Rate: #{calculate_success_rate(metrics)}%
    - Average Duration: #{format_duration(metrics.avg_compilation_time)}
    - Error Rate: #{calculate_error_rate(metrics)}%

    ## Pool Efficiency
    - Cache Hit Rate: #{calculate_cache_hit_rate(metrics)}%
    - Port Reuse Rate: #{calculate_port_reuse_rate(metrics)}%
    - Pool Utilization: #{calculate_pool_utilization(metrics)}%
    - Peak Pool Size: #{metrics.peak_pool_size}

    ## Resource Management
    - Total Ports Created: #{metrics.ports_created}
    - Total Ports Terminated: #{metrics.ports_terminated}
    - Avg Port Lifetime: #{format_duration(metrics.avg_port_lifetime)}
    - Pool Exhaustions: #{metrics.pool_exhaustions}

    ## Performance Insights
    #{generate_insights(metrics)}

    ## Recommendations
    #{generate_recommendations(metrics)}

    Generated at: #{DateTime.utc_now() |> DateTime.to_string()}
    """
  end

  @doc """
  Reset telemetry metrics.
  """
  @spec reset_metrics() :: :ok
  def reset_metrics do
    :persistent_term.put(:optimized_telemetry_metrics, init_metrics())
    :ok
  end

  ## Private Implementation

  @doc """
  Handle default telemetry events for monitoring and alerting.
  This function is used as the default telemetry handler.
  """
  def handle_default_event(event, measurements, metadata, config) do
    # Update metrics
    update_metrics(event, measurements, metadata)

    # Log events based on configuration
    if config.log_level do
      log_event(event, measurements, metadata, config.log_level)
    end

    # Check for alerts
    if config.metrics_enabled do
      check_alerts(event, measurements, metadata, config.alert_thresholds)
    end
  end

  defp update_metrics([:tailwind_port_pool, :compile, :start], measurements, metadata) do
    update_counter(:total_compilations)
    update_gauge(:last_compilation_start, measurements.system_time)
    track_config_variation(metadata.config_hash)
  end

  defp update_metrics([:tailwind_port_pool, :compile, :stop], measurements, metadata) do
    update_counter(:successful_compilations)
    update_timing(:compilation_time, measurements.duration)

    if metadata.port_reused do
      update_counter(:port_reuses)
    end
  end

  defp update_metrics([:tailwind_port_pool, :compile, :error], measurements, _metadata) do
    update_counter(:failed_compilations)
    update_counter(:total_errors)
    update_timing(:error_compilation_time, measurements.duration)
  end

  defp update_metrics([:tailwind_port_pool, :pool, :port_created], measurements, _metadata) do
    update_counter(:ports_created)
    update_timing(:port_creation_time, measurements.creation_duration)
    update_gauge(:current_pool_size, measurements.pool_size)
    update_max(:peak_pool_size, measurements.pool_size)
  end

  defp update_metrics([:tailwind_port_pool, :pool, :port_reused], measurements, _metadata) do
    update_counter(:port_reuses)
    update_timing(:port_age, measurements.port_age_ms)
  end

  defp update_metrics(
         [:tailwind_port_pool, :pool, :port_terminated],
         measurements,
         _metadata
       ) do
    update_counter(:ports_terminated)
    update_timing(:port_lifetime, measurements.port_lifetime)
  end

  defp update_metrics([:tailwind_port_pool, :pool, :exhausted], measurements, _metadata) do
    update_counter(:pool_exhaustions)
    update_gauge(:pool_utilization, measurements.pool_size / measurements.max_size)
  end

  defp update_metrics(
         [:tailwind_port_pool, :maintenance, :cleanup_completed],
         measurements,
         _metadata
       ) do
    update_counter(:cleanup_cycles)
    update_timing(:cleanup_duration, measurements.cleanup_duration)
    update_gauge(:current_pool_size, measurements.active_ports)
  end

  defp update_metrics([:tailwind_port_pool, :metrics, :snapshot], measurements, _metadata) do
    update_gauge(:reuse_rate, measurements.reuse_rate)
    update_gauge(:avg_port_lifetime_ms, measurements.avg_port_lifetime_ms)
    update_gauge(:average_compilation_time_ms, measurements.average_compilation_time_ms)
    update_gauge(:degraded_rate, measurements.degraded_rate)
    update_gauge(:compilation_time_improvement, measurements.compilation_time_improvement || 0.0)
  end

  defp update_metrics(_, _, _), do: :ok

  defp log_event([:tailwind_port_pool, :compile, :start], _measurements, metadata, level) do
    Logger.log(level, "🚀 Pool compilation started", %{
      operation_id: metadata.operation_id,
      config_hash: metadata.config_hash,
      priority: metadata.priority,
      content_size: metadata.content_size
    })
  end

  defp log_event([:tailwind_port_pool, :compile, :stop], measurements, metadata, level) do
    Logger.log(level, "✅ Pool compilation completed", %{
      operation_id: metadata.operation_id,
      duration_ms: div(measurements.duration, 1000),
      port_reused: metadata.port_reused,
      cache_hits: measurements.cache_hits
    })
  end

  defp log_event([:tailwind_port_pool, :compile, :error], measurements, metadata, _level) do
    Logger.log(:error, "❌ Pool compilation failed", %{
      operation_id: metadata.operation_id,
      duration_ms: div(measurements.duration, 1000),
      error: metadata.error
    })
  end

  defp log_event([:tailwind_port_pool, :pool, :port_created], measurements, metadata, level) do
    Logger.log(level, "🔧 New port created in pool", %{
      config_hash: metadata.config_hash,
      creation_duration_ms: div(measurements.creation_duration, 1000),
      pool_size: measurements.pool_size
    })
  end

  defp log_event([:tailwind_port_pool, :pool, :exhausted], measurements, metadata, _level) do
    Logger.log(:warning, "⚠️  Port pool exhausted", %{
      config_hash: metadata.config_hash,
      pool_size: measurements.pool_size,
      max_size: measurements.max_size
    })
  end

  defp log_event(_, _, _, _), do: :ok

  defp check_alerts(_event, measurements, _metadata, thresholds) do
    current_metrics = get_current_metrics()

    # Check error rate
    error_rate = calculate_error_rate(current_metrics)

    if error_rate > thresholds.error_rate do
      emit_alert(:high_error_rate, %{
        current_rate: error_rate,
        threshold: thresholds.error_rate,
        total_errors: current_metrics.total_errors,
        total_compilations: current_metrics.total_compilations
      })
    end

    # Check average compilation time
    if current_metrics.avg_compilation_time > thresholds.avg_compilation_time do
      emit_alert(:slow_compilation, %{
        current_avg: current_metrics.avg_compilation_time,
        threshold: thresholds.avg_compilation_time
      })
    end

    # Check pool utilization
    if Map.has_key?(measurements, :pool_size) and Map.has_key?(measurements, :max_size) do
      utilization = measurements.pool_size / measurements.max_size

      if utilization > thresholds.pool_utilization do
        emit_alert(:high_pool_utilization, %{
          current_utilization: utilization,
          threshold: thresholds.pool_utilization,
          pool_size: measurements.pool_size,
          max_size: measurements.max_size
        })
      end
    end
  end

  defp emit_alert(alert_type, data) do
    :telemetry.execute(
      [:tailwind_port_pool, :alert, alert_type],
      %{severity: alert_severity(alert_type)},
      data
    )

    Logger.warning("🚨 TailwindPort Pool Alert: #{alert_type}", data)
  end

  defp alert_severity(:high_error_rate), do: :high
  defp alert_severity(:slow_compilation), do: :medium
  defp alert_severity(:high_pool_utilization), do: :medium
  defp alert_severity(_), do: :low

  defp init_metrics do
    %{
      total_compilations: 0,
      successful_compilations: 0,
      failed_compilations: 0,
      total_errors: 0,
      ports_created: 0,
      ports_terminated: 0,
      port_reuses: 0,
      pool_exhaustions: 0,
      cleanup_cycles: 0,
      peak_pool_size: 0,
      current_pool_size: 0,
      pool_utilization: 0.0,
      avg_compilation_time: 0,
      avg_port_lifetime: 0,
      config_variations: MapSet.new(),
      last_compilation_start: 0,
      started_at: System.monotonic_time(:millisecond)
    }
  end

  defp update_counter(key) do
    metrics = get_current_metrics()
    updated = Map.update(metrics, key, 1, &(&1 + 1))
    :persistent_term.put(:optimized_telemetry_metrics, updated)
  end

  defp update_gauge(key, value) do
    metrics = get_current_metrics()
    updated = Map.put(metrics, key, value)
    :persistent_term.put(:optimized_telemetry_metrics, updated)
  end

  defp update_max(key, value) do
    metrics = get_current_metrics()
    current_max = Map.get(metrics, key, 0)
    updated = Map.put(metrics, key, max(current_max, value))
    :persistent_term.put(:optimized_telemetry_metrics, updated)
  end

  defp update_timing(key, duration) do
    metrics = get_current_metrics()
    current_avg = Map.get(metrics, :"avg_#{key}", 0)
    count_key = :"#{key}_count"
    count = Map.get(metrics, count_key, 0) + 1

    new_avg = (current_avg * (count - 1) + duration) / count

    updated =
      metrics
      |> Map.put(:"avg_#{key}", new_avg)
      |> Map.put(count_key, count)

    :persistent_term.put(:optimized_telemetry_metrics, updated)
  end

  defp track_config_variation(config_hash) do
    metrics = get_current_metrics()
    variations = MapSet.put(metrics.config_variations, config_hash)
    updated = Map.put(metrics, :config_variations, variations)
    :persistent_term.put(:optimized_telemetry_metrics, updated)
  end

  defp calculate_success_rate(%{successful_compilations: success, total_compilations: total})
       when total > 0 do
    Float.round(success / total * 100, 1)
  end

  defp calculate_success_rate(_), do: 0.0

  defp calculate_error_rate(%{total_errors: errors, total_compilations: total})
       when total > 0 do
    Float.round(errors / total * 100, 1)
  end

  defp calculate_error_rate(_), do: 0.0

  defp calculate_cache_hit_rate(%{port_reuses: hits, total_compilations: total})
       when total > 0 do
    Float.round(hits / total * 100, 1)
  end

  defp calculate_cache_hit_rate(_), do: 0.0

  defp calculate_port_reuse_rate(%{port_reuses: reuses, ports_created: created})
       when created > 0 do
    Float.round(reuses / created * 100, 1)
  end

  defp calculate_port_reuse_rate(_), do: 0.0

  defp calculate_pool_utilization(%{current_pool_size: current, peak_pool_size: peak})
       when peak > 0 do
    Float.round(current / peak * 100, 1)
  end

  defp calculate_pool_utilization(_), do: 0.0

  defp format_duration(microseconds) when is_number(microseconds) do
    cond do
      microseconds < 1000 -> "#{Float.round(microseconds, 1)}μs"
      microseconds < 1_000_000 -> "#{Float.round(microseconds / 1000, 1)}ms"
      true -> "#{Float.round(microseconds / 1_000_000, 2)}s"
    end
  end

  defp format_duration(_), do: "N/A"

  defp generate_insights(metrics) do
    insights = []

    insights =
      if calculate_cache_hit_rate(metrics) > 70 do
        ["✅ Excellent cache hit rate - port reuse is working well" | insights]
      else
        ["⚠️  Low cache hit rate - consider reviewing configuration patterns" | insights]
      end

    insights =
      if calculate_error_rate(metrics) < 5 do
        ["✅ Low error rate indicates stable compilation" | insights]
      else
        ["⚠️  High error rate detected - investigate compilation failures" | insights]
      end

    insights =
      if metrics.pool_exhaustions > 0 do
        ["⚠️  Pool exhaustions detected - consider increasing max_pool_size" | insights]
      else
        ["✅ No pool exhaustions - pool size is adequate" | insights]
      end

    if Enum.empty?(insights) do
      "📊 Insufficient data for insights"
    else
      Enum.join(insights, "\n")
    end
  end

  defp generate_recommendations(metrics) do
    recommendations = []

    cache_hit_rate = calculate_cache_hit_rate(metrics)

    recommendations =
      cond do
        cache_hit_rate < 30 ->
          ["🔧 Consider enabling configuration warming for common use cases" | recommendations]

        cache_hit_rate > 90 ->
          [
            "🚀 Excellent cache performance - consider reducing pool cleanup frequency"
            | recommendations
          ]

        true ->
          recommendations
      end

    error_rate = calculate_error_rate(metrics)

    recommendations =
      if error_rate > 10 do
        [
          "🔍 High error rate - enable detailed error logging and review input validation"
          | recommendations
        ]
      else
        recommendations
      end

    config_variety = MapSet.size(metrics.config_variations)

    recommendations =
      cond do
        config_variety > 50 ->
          [
            "📊 High configuration variety - consider configuration normalization"
            | recommendations
          ]

        config_variety < 3 ->
          ["💡 Low configuration variety - pool size could be reduced" | recommendations]

        true ->
          recommendations
      end

    if Enum.empty?(recommendations) do
      "✅ System is performing optimally - no specific recommendations"
    else
      Enum.join(recommendations, "\n")
    end
  end
end
