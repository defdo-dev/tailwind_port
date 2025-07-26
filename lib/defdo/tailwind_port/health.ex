defmodule Defdo.TailwindPort.Health do
  @moduledoc """
  Health monitoring and metrics functionality for TailwindPort.

  This module provides comprehensive health monitoring capabilities including
  metrics tracking, port readiness detection, and activity monitoring. It's
  designed to give deep insights into the performance and status of TailwindPort
  processes for production monitoring and debugging.

  ## Features

  - **Metrics Tracking**: Monitors outputs, CSS builds, errors, and activity
  - **Port Readiness Detection**: Intelligent detection of when ports are operational
  - **Activity Monitoring**: Tracks last activity and uptime
  - **Performance Metrics**: Build rates, error rates, and timing information
  - **Caller Management**: Handles waiting callers for readiness events

  ## Health Metrics

  The health system tracks the following metrics:

  - `:created_at` - Process creation timestamp
  - `:last_activity` - Timestamp of last activity
  - `:total_outputs` - Total number of outputs received
  - `:css_builds` - Number of CSS compilation events detected
  - `:errors` - Number of errors encountered
  - `:uptime_seconds` - Process uptime in seconds
  - `:port_ready` - Boolean indicating if port is operational
  - `:port_active` - Boolean indicating if underlying port is active
  - `:last_activity_seconds_ago` - Seconds since last activity

  ## Usage

      # Create initial health state
      health = Health.create_initial_health()

      # Update metrics with new data
      updated_health = Health.update_metrics(health, "CSS build completed")

      # Check if data indicates readiness
      is_ready = Health.detect_readiness("Rebuilding...")

      # Calculate comprehensive health info
      health_info = Health.calculate_health_info(state)

  """

  require Logger
  alias Defdo.TailwindPort.ProcessManager

  @typedoc "Health metrics structure"
  @type health_metrics :: %{
          created_at: integer(),
          last_activity: integer(),
          total_outputs: non_neg_integer(),
          css_builds: non_neg_integer(),
          errors: non_neg_integer()
        }

  @typedoc "Comprehensive health information"
  @type health_info :: %{
          uptime_seconds: float(),
          port_ready: boolean(),
          port_active: boolean(),
          total_outputs: non_neg_integer(),
          css_builds: non_neg_integer(),
          errors: non_neg_integer(),
          last_activity: integer(),
          last_activity_seconds_ago: float(),
          created_at: integer()
        }

  @doc """
  Creates initial health metrics for a new process.

  Returns a health metrics map with initial values set to current time
  and zero counters.

  ## Returns

    * `health_metrics()` - Initial health state

  ## Examples

      iex> health = Health.create_initial_health()
      iex> health.total_outputs
      0
      iex> health.css_builds  
      0
      iex> health.errors
      0

  """
  @spec create_initial_health() :: health_metrics()
  def create_initial_health do
    current_time = System.system_time()

    %{
      created_at: current_time,
      last_activity: current_time,
      total_outputs: 0,
      css_builds: 0,
      errors: 0
    }
  end

  @doc """
  Updates health metrics with new activity data.

  This function processes incoming data from the Tailwind port and updates
  the health metrics accordingly. It detects CSS-related outputs and increments
  appropriate counters.

  ## Parameters

    * `health` - Current health metrics
    * `data` - Output data from the port

  ## Returns

    * `health_metrics()` - Updated health metrics

  ## Examples

      health = Health.create_initial_health()
      
      # CSS build output
      updated = Health.update_metrics(health, "Done in 45ms")
      assert updated.css_builds == 1
      assert updated.total_outputs == 1

      # Regular output
      updated2 = Health.update_metrics(updated, "some output")
      assert updated2.css_builds == 1  # No change
      assert updated2.total_outputs == 2

  """
  @spec update_metrics(health_metrics(), String.t()) :: health_metrics()
  def update_metrics(health, data) when is_map(health) and is_binary(data) do
    updated_health =
      health
      |> Map.put(:last_activity, System.system_time())
      |> Map.update!(:total_outputs, &(&1 + 1))

    # Increment CSS builds if this looks like a CSS-related output
    if css_related_output?(data) do
      Map.update!(updated_health, :css_builds, &(&1 + 1))
    else
      updated_health
    end
  end

  @doc """
  Increments the error counter in health metrics.

  Used when errors are detected in the port or process operations.

  ## Parameters

    * `health` - Current health metrics

  ## Returns

    * `health_metrics()` - Health metrics with incremented error count

  """
  @spec increment_errors(health_metrics()) :: health_metrics()
  def increment_errors(health) when is_map(health) do
    Map.update!(health, :errors, &(&1 + 1))
  end

  @doc """
  Detects if port output indicates readiness.

  Analyzes the output data to determine if the Tailwind port is ready
  for operations. This uses various heuristics to detect different
  types of readiness indicators.

  ## Parameters

    * `data` - Output data from the port

  ## Returns

    * `boolean()` - True if data indicates readiness

  ## Examples

      assert Health.detect_readiness("Rebuilding...")
      assert Health.detect_readiness("Done in 45ms")
      assert Health.detect_readiness("Built successfully")
      assert Health.detect_readiness("Watching for changes")
      refute Health.detect_readiness("")

  """
  @spec detect_readiness(String.t()) :: boolean()
  def detect_readiness(data) when is_binary(data) do
    # Consider port ready if we get any output that suggests Tailwind is running
    String.contains?(data, "Rebuilding") or
      String.contains?(data, "Done in") or
      String.contains?(data, "Built successfully") or
      String.contains?(data, "Watching") or
      String.contains?(data, "Ready") or
      byte_size(data) > 0
  end

  @doc """
  Calculates comprehensive health information for a GenServer state.

  Takes the current state and calculates derived health metrics including
  uptime, activity freshness, and port status.

  ## Parameters

    * `state` - GenServer state containing health metrics and port info

  ## Returns

    * `health_info()` - Comprehensive health information map

  ## Examples

      state = %{
        health: Health.create_initial_health(),
        port: some_port,
        port_ready: true
      }
      
      info = Health.calculate_health_info(state)
      assert info.uptime_seconds >= 0
      assert is_boolean(info.port_ready)
      assert is_boolean(info.port_active)

  """
  @spec calculate_health_info(map()) :: health_info()
  def calculate_health_info(state) when is_map(state) do
    health = Map.get(state, :health, create_initial_health())
    current_time = System.system_time()

    Map.merge(health, %{
      uptime_seconds: (current_time - health.created_at) / 1_000_000_000,
      port_active: port_active?(state),
      port_ready: Map.get(state, :port_ready, false),
      last_activity_seconds_ago: (current_time - health.last_activity) / 1_000_000_000
    })
  end

  @doc """
  Manages waiting callers when port becomes ready.

  This function handles the notification of processes that are waiting
  for the port to become ready. It cancels timeouts and replies to
  waiting GenServer calls.

  ## Parameters

    * `state` - Current GenServer state
    * `data` - Port output data that triggered readiness

  ## Returns

    * `map()` - Updated state with readiness marked and callers notified

  """
  @spec mark_port_ready(map(), String.t()) :: map()
  def mark_port_ready(state, data) when is_map(state) and is_binary(data) do
    if detect_readiness(data) do
      Logger.debug("Port marked as ready based on output: #{inspect(String.slice(data, 0, 100))}")

      state
      |> ProcessManager.cancel_startup_timeout()
      |> ProcessManager.reply_to_waiting_callers(:ok)
      |> Map.put(:port_ready, true)
    else
      state
    end
  end

  @doc """
  Checks if port is already ready and skips processing if so.

  This is a guard function that prevents unnecessary processing when
  the port is already in a ready state.

  ## Parameters

    * `state` - Current GenServer state
    * `data` - Port output data

  ## Returns

    * `map()` - Unchanged state if already ready, processed state otherwise

  """
  @spec maybe_mark_port_ready(map(), String.t()) :: map()
  def maybe_mark_port_ready(%{port_ready: true} = state, _data), do: state
  def maybe_mark_port_ready(%{port_ready: false} = state, data), do: mark_port_ready(state, data)
  def maybe_mark_port_ready(state, data), do: mark_port_ready(state, data)

  @doc """
  Validates and normalizes health metrics structure.

  Ensures that health metrics have all required fields with proper defaults.

  ## Parameters

    * `health` - Health metrics to validate

  ## Returns

    * `health_metrics()` - Validated and normalized health metrics

  """
  @spec normalize_health(map()) :: health_metrics()
  def normalize_health(health) when is_map(health) do
    defaults = create_initial_health()

    Map.merge(defaults, health)
  end

  # Private helper functions

  defp css_related_output?(data) do
    String.contains?(data, "{") or
      String.contains?(data, "}") or
      String.contains?(data, "Done") or
      String.contains?(data, "Rebuilding") or
      String.contains?(data, "Built") or
      String.contains?(data, "CSS") or
      String.contains?(data, "Watching")
  end

  defp port_active?(state) do
    port = Map.get(state, :port)
    not is_nil(port) and not is_nil(Port.info(port))
  end
end
