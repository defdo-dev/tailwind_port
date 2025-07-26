defmodule Defdo.TailwindPort.ProcessManager do
  @moduledoc """
  Process lifecycle management functionality for TailwindPort.

  This module handles the lifecycle management of Elixir processes including
  timeout management, process monitoring, caller management, and cleanup operations.
  It provides a clean abstraction for managing GenServer state related to process
  lifecycle events.

  ## Features

  - **Timeout Management**: Handles startup timeouts with automatic cleanup
  - **Caller Management**: Manages waiting callers for process readiness events
  - **Process Monitoring**: Handles DOWN and EXIT messages from ports
  - **State Management**: Manages process-related state fields consistently
  - **Cleanup Operations**: Handles graceful cleanup of timeouts and references

  ## Process Lifecycle Events

  - **Startup**: Setting up initial timeouts and monitoring
  - **Readiness**: Managing waiting callers and timeout cancellation
  - **Monitoring**: Handling port monitoring and process events
  - **Cleanup**: Cleaning up references, timeouts, and callers

  ## Usage

      # Setup startup timeout
      state = ProcessManager.setup_startup_timeout(state, 10_000)

      # Add waiting caller
      state = ProcessManager.add_waiting_caller(state, from)

      # Handle startup timeout
      state = ProcessManager.handle_startup_timeout(state)

      # Cancel timeouts
      state = ProcessManager.cancel_startup_timeout(state)

  """

  require Logger

  @typedoc "GenServer state map"
  @type state :: map()

  @typedoc "GenServer from tuple"
  @type from :: GenServer.from()

  @typedoc "Timer reference"
  @type timer_ref :: reference() | nil

  @doc """
  Sets up a startup timeout for the process.

  This function creates a startup timeout that will fire after the specified
  duration if the process hasn't become ready. It manages the timer reference
  in the state for later cancellation.

  ## Parameters

    * `state` - Current GenServer state
    * `timeout_ms` - Timeout duration in milliseconds

  ## Returns

    * `state()` - Updated state with startup timeout reference

  ## Examples

      # Set 10 second startup timeout
      state = ProcessManager.setup_startup_timeout(state, 10_000)

      # Set custom timeout
      state = ProcessManager.setup_startup_timeout(state, 5_000)

  ## State Changes

  The function updates the following state fields:
  - `:startup_timeout_ref` - Set to the new timer reference

  """
  @spec setup_startup_timeout(state(), non_neg_integer()) :: state()
  def setup_startup_timeout(state, timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0 do
    timeout_ref = Process.send_after(self(), :startup_timeout, timeout_ms)
    Map.put(state, :startup_timeout_ref, timeout_ref)
  end

  @doc """
  Cancels an existing startup timeout.

  This function cancels any existing startup timeout and clears the timeout
  reference from the state. It's safe to call even if no timeout is active.

  ## Parameters

    * `state` - Current GenServer state

  ## Returns

    * `state()` - Updated state with cleared timeout reference

  ## Examples

      # Cancel existing timeout
      state = ProcessManager.cancel_startup_timeout(state)

      # Safe to call multiple times
      state = state 
      |> ProcessManager.cancel_startup_timeout()
      |> ProcessManager.cancel_startup_timeout()

  """
  @spec cancel_startup_timeout(state()) :: state()
  def cancel_startup_timeout(state) do
    if state[:startup_timeout_ref] do
      Process.cancel_timer(state.startup_timeout_ref)
    end

    Map.put(state, :startup_timeout_ref, nil)
  end

  @doc """
  Adds a waiting caller to the state.

  This function adds a GenServer caller to the list of processes waiting
  for readiness events. These callers will be replied to when the process
  becomes ready or times out.

  ## Parameters

    * `state` - Current GenServer state
    * `from` - GenServer from tuple to add to waiting list

  ## Returns

    * `state()` - Updated state with caller added to waiting list

  ## Examples

      # Add caller from handle_call
      def handle_call(:wait_until_ready, from, state) do
        new_state = ProcessManager.add_waiting_caller(state, from)
        {:noreply, new_state}
      end

  """
  @spec add_waiting_caller(state(), from()) :: state()
  def add_waiting_caller(state, from) do
    waiting_callers = Map.get(state, :waiting_callers, [])
    Map.put(state, :waiting_callers, [from | waiting_callers])
  end

  @doc """
  Replies to all waiting callers with the specified response.

  This function sends replies to all waiting callers and clears the waiting
  list from the state. It's used when the process becomes ready or encounters
  an error that affects all waiting callers.

  ## Parameters

    * `state` - Current GenServer state
    * `reply` - Reply to send to all waiting callers

  ## Returns

    * `state()` - Updated state with cleared waiting callers list

  ## Examples

      # Reply with success
      state = ProcessManager.reply_to_waiting_callers(state, :ok)

      # Reply with error
      state = ProcessManager.reply_to_waiting_callers(state, {:error, :timeout})

  """
  @spec reply_to_waiting_callers(state(), term()) :: state()
  def reply_to_waiting_callers(state, reply) do
    waiting_callers = Map.get(state, :waiting_callers, [])

    Enum.each(waiting_callers, fn from ->
      GenServer.reply(from, reply)
    end)

    Map.put(state, :waiting_callers, [])
  end

  @doc """
  Handles a startup timeout event.

  This function is called when a startup timeout fires. It logs a warning,
  replies to all waiting callers with a timeout error, and cleans up the
  timeout state.

  ## Parameters

    * `state` - Current GenServer state

  ## Returns

    * `state()` - Updated state with timeout handled and cleaned up

  ## Examples

      # In handle_info for :startup_timeout
      def handle_info(:startup_timeout, state) do
        new_state = ProcessManager.handle_startup_timeout(state)
        {:noreply, new_state}
      end

  ## Side Effects

  - Logs a warning about the timeout
  - Replies to all waiting callers with `{:error, :startup_timeout}`
  - Clears the timeout reference and waiting callers list

  """
  @spec handle_startup_timeout(state()) :: state()
  def handle_startup_timeout(state) do
    Logger.warning("Port startup timeout reached")

    state
    |> reply_to_waiting_callers({:error, :startup_timeout})
    |> Map.put(:startup_timeout_ref, nil)
  end

  @doc """
  Handles a port DOWN message.

  This function processes a DOWN message from a monitored port, logs the
  event, and returns the updated state. It's used to handle port monitoring
  events cleanly.

  ## Parameters

    * `state` - Current GenServer state  
    * `port` - Port that went down
    * `reason` - Reason for the DOWN message

  ## Returns

    * `state()` - Updated state (typically unchanged for normal exits)

  ## Examples

      # In handle_info for DOWN messages
      def handle_info({:DOWN, _ref, :port, port, reason}, state) do
        new_state = ProcessManager.handle_port_down(state, port, reason)
        {:noreply, new_state}
      end

  """
  @spec handle_port_down(state(), port(), term()) :: state()
  def handle_port_down(state, port, reason) do
    Logger.warning(
      "Handled :DOWN message from port: #{inspect(port)} (reason: #{inspect(reason)})"
    )

    state
  end

  @doc """
  Handles a port EXIT message.

  This function processes an EXIT message from a port, logs the event,
  and returns the updated state. It's used for handling port process
  termination events.

  ## Parameters

    * `state` - Current GenServer state
    * `port` - Port that exited
    * `reason` - Exit reason

  ## Returns

    * `state()` - Updated state (typically unchanged for normal exits)

  ## Examples

      # In handle_info for EXIT messages
      def handle_info({:EXIT, port, reason}, state) do
        new_state = ProcessManager.handle_port_exit(state, port, reason)
        {:noreply, new_state}
      end

  """
  @spec handle_port_exit(state(), port(), term()) :: state()
  def handle_port_exit(state, port, reason) do
    Logger.warning("handle_info: EXIT - #{inspect(port)} (reason: #{inspect(reason)})")
    state
  end

  @doc """
  Initializes process management fields in state.

  This function sets up the initial state fields needed for process management.
  It ensures all required fields are present with proper default values.

  ## Parameters

    * `state` - Base state map

  ## Returns

    * `state()` - State with process management fields initialized

  ## Examples

      # Initialize state in init/1
      def init(args) do
        state = %{port: nil}
        |> ProcessManager.initialize_state()
        
        {:ok, state}
      end

  ## State Fields Added

  - `:startup_timeout_ref` - Timer reference for startup timeout (nil)
  - `:waiting_callers` - List of waiting GenServer callers ([])

  """
  @spec initialize_state(state()) :: state()
  def initialize_state(state) do
    state
    |> Map.put_new(:startup_timeout_ref, nil)
    |> Map.put_new(:waiting_callers, [])
  end

  @doc """
  Cleans up all process management resources.

  This function performs a complete cleanup of all process management
  resources including timeouts, waiting callers, and references. It's
  typically used during process shutdown or restart.

  ## Parameters

    * `state` - Current GenServer state

  ## Returns

    * `state()` - State with all process management resources cleaned up

  ## Examples

      # During terminate/2
      def terminate(reason, state) do
        ProcessManager.cleanup_all(state)
      end

      # During process restart
      state = ProcessManager.cleanup_all(state)

  ## Cleanup Operations

  - Cancels any active startup timeout
  - Replies to waiting callers with shutdown error
  - Clears all process management state fields

  """
  @spec cleanup_all(state()) :: state()
  def cleanup_all(state) do
    state
    |> cancel_startup_timeout()
    |> reply_to_waiting_callers({:error, :shutdown})
  end

  @doc """
  Checks if the process is currently waiting for readiness.

  This function determines if there are any callers waiting for the
  process to become ready. It's useful for determining process state
  and making decisions about timeout handling.

  ## Parameters

    * `state` - Current GenServer state

  ## Returns

    * `boolean()` - True if there are waiting callers, false otherwise

  ## Examples

      # Check before setting timeouts
      if ProcessManager.has_waiting_callers?(state) do
        # Process timeout differently
      end

      # Conditional logging
      if ProcessManager.has_waiting_callers?(state) do
        Logger.info("Process has waiting callers")
      end

  """
  @spec has_waiting_callers?(state()) :: boolean()
  def has_waiting_callers?(state) do
    waiting_callers = Map.get(state, :waiting_callers, [])
    not Enum.empty?(waiting_callers)
  end

  @doc """
  Gets the count of waiting callers.

  ## Parameters

    * `state` - Current GenServer state

  ## Returns

    * `non_neg_integer()` - Number of waiting callers

  """
  @spec waiting_callers_count(state()) :: non_neg_integer()
  def waiting_callers_count(state) do
    waiting_callers = Map.get(state, :waiting_callers, [])
    length(waiting_callers)
  end

  @doc """
  Checks if a startup timeout is currently active.

  ## Parameters

    * `state` - Current GenServer state

  ## Returns

    * `boolean()` - True if startup timeout is active, false otherwise

  """
  @spec has_startup_timeout?(state()) :: boolean()
  def has_startup_timeout?(state) do
    not is_nil(state[:startup_timeout_ref])
  end
end
