defmodule Defdo.TailwindPort.Metrics do
  @moduledoc """
  Telemetry metric helpers for TailwindPort.

  This module provides ready-to-use `Telemetry.Metrics` definitions so
  applications can expose TailwindPort KPIs through exporters such as
  `TelemetryMetricsPrometheus`, `TelemetryMetricsStatsd`, or OpenTelemetry
  bridges.

  ## Usage

      children = [
        {TelemetryMetricsPrometheus.Core, metrics: Defdo.TailwindPort.Metrics.default_metrics()}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  The returned metrics include compilation timing, pool lifecycle counters,
  and the derived KPIs emitted by `Defdo.TailwindPort.Optimized.get_stats/0`
  via the `[:tailwind_port_optimized, :metrics, :snapshot]` event.

  Call `optimized_metrics/1` to customise prefixes or tag sets.
  """

  alias Telemetry.Metrics

  @doc """
  Returns the default set of metrics that cover the optimized pooling layer.

  Equivalent to `optimized_metrics/1` with default options.
  """
  @spec default_metrics() :: [Metrics.t()]
  def default_metrics, do: optimized_metrics()

  @doc """
  Builds telemetry metric definitions for the optimized TailwindPort layer.

  ## Options

    * `:event_prefix` – override the event prefix (default: `[:tailwind_port_optimized]`).
    * `:compile_tags` – tags to keep for compile events (default: `[:config_hash]`).
    * `:snapshot_tags` – tags to keep for snapshot events (default: `[:active_ports, :cache_size, :queue_size]`).
  """
  @spec optimized_metrics(keyword()) :: [Metrics.t()]
  def optimized_metrics(opts \\ []) do
    prefix = Keyword.get(opts, :event_prefix, [:tailwind_port_optimized])
    compile_tags = Keyword.get(opts, :compile_tags, [:config_hash])
    snapshot_tags = Keyword.get(opts, :snapshot_tags, [:active_ports, :cache_size, :queue_size])

    compile_stop = prefix ++ [:compile, :stop]
    compile_error = prefix ++ [:compile, :error]
    pool_created = prefix ++ [:pool, :port_created]
    pool_reused = prefix ++ [:pool, :port_reused]
    pool_terminated = prefix ++ [:pool, :port_terminated]
    pool_exhausted = prefix ++ [:pool, :exhausted]
    maintenance_cleanup = prefix ++ [:maintenance, :cleanup_completed]
    snapshot = prefix ++ [:metrics, :snapshot]

    [
      Metrics.summary(
        "tailwind_port.compile.duration",
        event_name: compile_stop,
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: compile_tags
      ),
      Metrics.last_value(
        "tailwind_port.compile.cache_hits",
        event_name: compile_stop,
        measurement: :cache_hits,
        tags: compile_tags
      ),
      Metrics.counter(
        "tailwind_port.compile.errors",
        event_name: compile_error
      ),
      Metrics.summary(
        "tailwind_port.pool.creation_time",
        event_name: pool_created,
        measurement: :creation_duration,
        unit: {:native, :millisecond}
      ),
      Metrics.last_value(
        "tailwind_port.pool.size",
        event_name: pool_created,
        measurement: :pool_size
      ),
      Metrics.summary(
        "tailwind_port.pool.reuse.age",
        event_name: pool_reused,
        measurement: :port_age_ms,
        unit: {:native, :millisecond}
      ),
      Metrics.counter(
        "tailwind_port.pool.reuses",
        event_name: pool_reused
      ),
      Metrics.summary(
        "tailwind_port.pool.lifetime",
        event_name: pool_terminated,
        measurement: :port_lifetime,
        unit: {:native, :millisecond}
      ),
      Metrics.counter(
        "tailwind_port.pool.terminated",
        event_name: pool_terminated
      ),
      Metrics.last_value(
        "tailwind_port.pool.utilization",
        event_name: pool_exhausted,
        measurement: :pool_utilization,
        tags: compile_tags
      ),
      Metrics.counter(
        "tailwind_port.pool.exhaustions",
        event_name: pool_exhausted
      ),
      Metrics.summary(
        "tailwind_port.maintenance.cleanup_duration",
        event_name: maintenance_cleanup,
        measurement: :cleanup_duration,
        unit: {:native, :millisecond}
      ),
      Metrics.last_value(
        "tailwind_port.maintenance.active_ports",
        event_name: maintenance_cleanup,
        measurement: :active_ports
      ),
      Metrics.last_value(
        "tailwind_port.kpi.reuse_rate",
        event_name: snapshot,
        measurement: :reuse_rate,
        tags: snapshot_tags
      ),
      Metrics.last_value(
        "tailwind_port.kpi.avg_port_lifetime_ms",
        event_name: snapshot,
        measurement: :avg_port_lifetime_ms,
        tags: snapshot_tags
      ),
      Metrics.last_value(
        "tailwind_port.kpi.compilation_count_per_port",
        event_name: snapshot,
        measurement: :compilation_count_per_port,
        tags: snapshot_tags
      ),
      Metrics.last_value(
        "tailwind_port.kpi.average_compilation_time_ms",
        event_name: snapshot,
        measurement: :average_compilation_time_ms,
        tags: snapshot_tags
      ),
      Metrics.last_value(
        "tailwind_port.kpi.degraded_rate",
        event_name: snapshot,
        measurement: :degraded_rate,
        tags: snapshot_tags
      ),
      Metrics.last_value(
        "tailwind_port.kpi.compilation_time_improvement",
        event_name: snapshot,
        measurement: :compilation_time_improvement,
        tags: snapshot_tags
      )
    ]
  end
end
