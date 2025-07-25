defmodule Defdo.TailwindPort.ProcessManagerTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Defdo.TailwindPort.ProcessManager

  describe "setup_startup_timeout/2" do
    test "sets up startup timeout with valid duration" do
      state = %{}
      result = ProcessManager.setup_startup_timeout(state, 5000)

      assert Map.has_key?(result, :startup_timeout_ref)
      assert is_reference(result.startup_timeout_ref)
    end

    test "replaces existing timeout" do
      state = %{startup_timeout_ref: make_ref()}
      result = ProcessManager.setup_startup_timeout(state, 1000)

      assert result.startup_timeout_ref != state.startup_timeout_ref
      assert is_reference(result.startup_timeout_ref)
    end

    test "handles different timeout durations" do
      state = %{}

      # Test various durations
      durations = [1, 100, 1000, 10_000, 60_000]

      Enum.each(durations, fn duration ->
        result = ProcessManager.setup_startup_timeout(state, duration)
        assert is_reference(result.startup_timeout_ref)
      end)
    end

    test "preserves other state fields" do
      state = %{port: :some_port, other_field: "value"}
      result = ProcessManager.setup_startup_timeout(state, 1000)

      assert result.port == :some_port
      assert result.other_field == "value"
      assert Map.has_key?(result, :startup_timeout_ref)
    end
  end

  describe "cancel_startup_timeout/1" do
    test "cancels existing timeout" do
      # Create a timeout that we can cancel
      timeout_ref = Process.send_after(self(), :test_timeout, 10_000)
      state = %{startup_timeout_ref: timeout_ref}

      result = ProcessManager.cancel_startup_timeout(state)

      assert result.startup_timeout_ref == nil

      # Verify timeout was actually cancelled by waiting and checking
      receive do
        :test_timeout -> flunk("Timeout should have been cancelled")
      after
        # Timeout was cancelled successfully
        100 -> :ok
      end
    end

    test "handles state without timeout" do
      state = %{}
      result = ProcessManager.cancel_startup_timeout(state)

      assert result.startup_timeout_ref == nil
    end

    test "handles state with nil timeout" do
      state = %{startup_timeout_ref: nil}
      result = ProcessManager.cancel_startup_timeout(state)

      assert result.startup_timeout_ref == nil
    end

    test "preserves other state fields" do
      state = %{port: :some_port, startup_timeout_ref: make_ref()}
      result = ProcessManager.cancel_startup_timeout(state)

      assert result.port == :some_port
      assert result.startup_timeout_ref == nil
    end
  end

  describe "add_waiting_caller/2" do
    test "adds caller to empty waiting list" do
      state = %{}
      from = {self(), make_ref()}

      result = ProcessManager.add_waiting_caller(state, from)

      assert result.waiting_callers == [from]
    end

    test "adds caller to existing waiting list" do
      existing_from = {self(), make_ref()}
      state = %{waiting_callers: [existing_from]}
      new_from = {self(), make_ref()}

      result = ProcessManager.add_waiting_caller(state, new_from)

      assert result.waiting_callers == [new_from, existing_from]
    end

    test "handles multiple callers" do
      state = %{}
      callers = for _ <- 1..5, do: {self(), make_ref()}

      final_state =
        Enum.reduce(callers, state, fn from, acc ->
          ProcessManager.add_waiting_caller(acc, from)
        end)

      assert length(final_state.waiting_callers) == 5
      assert Enum.all?(callers, fn caller -> caller in final_state.waiting_callers end)
    end
  end

  describe "reply_to_waiting_callers/2" do
    test "replies to single waiting caller" do
      ref = make_ref()
      from = {self(), ref}
      state = %{waiting_callers: [from]}

      result = ProcessManager.reply_to_waiting_callers(state, :ok)

      assert result.waiting_callers == []

      # Check we received the reply
      assert_receive {^ref, :ok}
    end

    test "replies to multiple waiting callers" do
      callers = for _ <- 1..3, do: {self(), make_ref()}
      state = %{waiting_callers: callers}

      result = ProcessManager.reply_to_waiting_callers(state, {:error, :timeout})

      assert result.waiting_callers == []

      # Check all callers received replies
      Enum.each(callers, fn {_pid, ref} ->
        assert_receive {^ref, {:error, :timeout}}
      end)
    end

    test "handles empty waiting list" do
      state = %{waiting_callers: []}
      result = ProcessManager.reply_to_waiting_callers(state, :ok)

      assert result.waiting_callers == []
    end

    test "handles state without waiting_callers field" do
      state = %{}
      result = ProcessManager.reply_to_waiting_callers(state, :ok)

      assert result.waiting_callers == []
    end

    test "sends different reply types" do
      replies = [:ok, {:error, :timeout}, {:ok, "success"}, :shutdown]

      Enum.each(replies, fn reply ->
        ref = make_ref()
        from = {self(), ref}
        state = %{waiting_callers: [from]}

        ProcessManager.reply_to_waiting_callers(state, reply)
        assert_receive {^ref, ^reply}
      end)
    end
  end

  describe "handle_startup_timeout/1" do
    test "replies to waiting callers and clears timeout" do
      ref1 = make_ref()
      ref2 = make_ref()
      callers = [{self(), ref1}, {self(), ref2}]
      state = %{waiting_callers: callers, startup_timeout_ref: make_ref()}

      # Test that timeout handling works correctly
      result = ProcessManager.handle_startup_timeout(state)
      assert result.waiting_callers == []
      assert result.startup_timeout_ref == nil

      # Check both callers received timeout errors
      assert_receive {^ref1, {:error, :startup_timeout}}
      assert_receive {^ref2, {:error, :startup_timeout}}
    end

    test "handles state without waiting callers" do
      state = %{startup_timeout_ref: make_ref()}

      # Test that timeout handling works correctly even without waiting callers
      result = ProcessManager.handle_startup_timeout(state)
      assert result.waiting_callers == []
      assert result.startup_timeout_ref == nil
    end
  end

  describe "handle_port_down/3" do
    test "handles port down event" do
      state = %{}
      port = Port.open({:spawn, "echo test"}, [:binary])

      # Test that the function handles port down events gracefully
      result = ProcessManager.handle_port_down(state, port, :normal)
      # State should be unchanged
      assert result == state

      # Close port safely
      if Port.info(port), do: Port.close(port)
    end

    test "handles different exit reasons" do
      state = %{}
      # Mock port for testing
      port = make_ref()
      reasons = [:normal, :killed, {:error, :econnrefused}]

      Enum.each(reasons, fn reason ->
        result = ProcessManager.handle_port_down(state, port, reason)
        assert result == state
      end)
    end
  end

  describe "handle_port_exit/3" do
    test "handles port exit event" do
      state = %{}
      # Mock port for testing
      port = make_ref()

      # Test that the function handles port exit events gracefully
      result = ProcessManager.handle_port_exit(state, port, :normal)
      # State should be unchanged
      assert result == state
    end
  end

  describe "initialize_state/1" do
    test "adds process management fields to empty state" do
      state = %{}
      result = ProcessManager.initialize_state(state)

      assert result.startup_timeout_ref == nil
      assert result.waiting_callers == []
    end

    test "does not overwrite existing fields" do
      state = %{
        startup_timeout_ref: make_ref(),
        waiting_callers: [{self(), make_ref()}],
        other_field: "value"
      }

      result = ProcessManager.initialize_state(state)

      # Should not overwrite existing values
      assert result.startup_timeout_ref == state.startup_timeout_ref
      assert result.waiting_callers == state.waiting_callers
      assert result.other_field == "value"
    end

    test "adds missing fields while preserving others" do
      state = %{port: :some_port, startup_timeout_ref: make_ref()}
      result = ProcessManager.initialize_state(state)

      assert result.port == :some_port
      assert result.startup_timeout_ref == state.startup_timeout_ref
      # Added because missing
      assert result.waiting_callers == []
    end
  end

  describe "cleanup_all/1" do
    test "performs complete cleanup" do
      ref1 = make_ref()
      ref2 = make_ref()
      callers = [{self(), ref1}, {self(), ref2}]
      timeout_ref = Process.send_after(self(), :test_timeout, 10_000)

      state = %{
        startup_timeout_ref: timeout_ref,
        waiting_callers: callers,
        other_field: "preserved"
      }

      result = ProcessManager.cleanup_all(state)

      # Check cleanup results
      assert result.startup_timeout_ref == nil
      assert result.waiting_callers == []
      assert result.other_field == "preserved"

      # Check callers received shutdown errors
      assert_receive {^ref1, {:error, :shutdown}}
      assert_receive {^ref2, {:error, :shutdown}}

      # Verify timeout was cancelled
      receive do
        :test_timeout -> flunk("Timeout should have been cancelled")
      after
        100 -> :ok
      end
    end
  end

  describe "has_waiting_callers?/1" do
    test "returns true when callers are waiting" do
      state = %{waiting_callers: [{self(), make_ref()}]}
      assert ProcessManager.has_waiting_callers?(state) == true
    end

    test "returns false when no callers are waiting" do
      state = %{waiting_callers: []}
      assert ProcessManager.has_waiting_callers?(state) == false
    end

    test "returns false when waiting_callers field is missing" do
      state = %{}
      assert ProcessManager.has_waiting_callers?(state) == false
    end

    test "handles multiple callers" do
      callers = for _ <- 1..5, do: {self(), make_ref()}
      state = %{waiting_callers: callers}
      assert ProcessManager.has_waiting_callers?(state) == true
    end
  end

  describe "waiting_callers_count/1" do
    test "returns correct count for multiple callers" do
      callers = for _ <- 1..3, do: {self(), make_ref()}
      state = %{waiting_callers: callers}
      assert ProcessManager.waiting_callers_count(state) == 3
    end

    test "returns zero for empty list" do
      state = %{waiting_callers: []}
      assert ProcessManager.waiting_callers_count(state) == 0
    end

    test "returns zero for missing field" do
      state = %{}
      assert ProcessManager.waiting_callers_count(state) == 0
    end
  end

  describe "has_startup_timeout?/1" do
    test "returns true when timeout is active" do
      state = %{startup_timeout_ref: make_ref()}
      assert ProcessManager.has_startup_timeout?(state) == true
    end

    test "returns false when timeout is nil" do
      state = %{startup_timeout_ref: nil}
      assert ProcessManager.has_startup_timeout?(state) == false
    end

    test "returns false when field is missing" do
      state = %{}
      assert ProcessManager.has_startup_timeout?(state) == false
    end
  end

  describe "integration and edge cases" do
    test "complete workflow: setup -> add callers -> timeout -> cleanup" do
      # Start with empty state
      state =
        %{}
        |> ProcessManager.initialize_state()
        # Short timeout for test
        |> ProcessManager.setup_startup_timeout(50)

      # Add some waiting callers
      ref1 = make_ref()
      ref2 = make_ref()

      state =
        state
        |> ProcessManager.add_waiting_caller({self(), ref1})
        |> ProcessManager.add_waiting_caller({self(), ref2})

      assert ProcessManager.has_waiting_callers?(state)
      assert ProcessManager.has_startup_timeout?(state)
      assert ProcessManager.waiting_callers_count(state) == 2

      # Simulate timeout handling
      state = ProcessManager.handle_startup_timeout(state)
      assert not ProcessManager.has_waiting_callers?(state)
      assert not ProcessManager.has_startup_timeout?(state)

      # Check that callers received timeout errors
      assert_receive {^ref1, {:error, :startup_timeout}}
      assert_receive {^ref2, {:error, :startup_timeout}}
    end

    test "handles rapid setup and cancellation" do
      state = %{}

      # Rapid setup and cancellation cycles
      final_state =
        1..10
        |> Enum.reduce(state, fn _, acc ->
          acc
          |> ProcessManager.setup_startup_timeout(1000)
          |> ProcessManager.cancel_startup_timeout()
        end)

      assert not ProcessManager.has_startup_timeout?(final_state)
    end

    test "stress test with many callers" do
      state = ProcessManager.initialize_state(%{})
      callers = for _ <- 1..100, do: {self(), make_ref()}

      # Add all callers
      final_state =
        Enum.reduce(callers, state, fn from, acc ->
          ProcessManager.add_waiting_caller(acc, from)
        end)

      assert ProcessManager.waiting_callers_count(final_state) == 100

      # Reply to all
      result = ProcessManager.reply_to_waiting_callers(final_state, :mass_reply)
      assert ProcessManager.waiting_callers_count(result) == 0

      # Verify all received replies
      Enum.each(callers, fn {_pid, ref} ->
        assert_receive {^ref, :mass_reply}
      end)
    end
  end
end
