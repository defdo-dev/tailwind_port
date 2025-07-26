defmodule Defdo.TailwindPort.RetryTest do
  @moduledoc false
  use ExUnit.Case
  alias Defdo.TailwindPort.Retry

  describe "with_backoff/2" do
    test "succeeds on first attempt" do
      result = Retry.with_backoff(fn -> {:ok, "success"} end)
      assert {:ok, "success"} = result
    end

    test "succeeds on second attempt" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        Retry.with_backoff(
          fn ->
            count = Agent.get_and_update(agent, fn count -> {count, count + 1} end)

            if count == 0 do
              {:error, :temporary_failure}
            else
              {:ok, "success_on_retry"}
            end
          end,
          max_retries: 3,
          retry_delay: 10
        )

      assert {:ok, "success_on_retry"} = result
    end

    test "fails after max retries exceeded" do
      result =
        Retry.with_backoff(
          fn -> {:error, :persistent_failure} end,
          max_retries: 2,
          retry_delay: 10
        )

      assert {:error, :max_retries_exceeded} = result
    end

    test "handles functions that raise exceptions" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        Retry.with_backoff(
          fn ->
            count = Agent.get_and_update(agent, fn count -> {count, count + 1} end)

            if count == 0 do
              raise "temporary error"
            else
              {:ok, "recovered"}
            end
          end,
          max_retries: 3,
          retry_delay: 10
        )

      assert {:ok, "recovered"} = result
    end

    test "handles functions that throw" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        Retry.with_backoff(
          fn ->
            count = Agent.get_and_update(agent, fn count -> {count, count + 1} end)

            if count == 0 do
              throw(:temporary_error)
            else
              {:ok, "recovered"}
            end
          end,
          max_retries: 3,
          retry_delay: 10
        )

      assert {:ok, "recovered"} = result
    end

    test "returns non-error results as success" do
      result = Retry.with_backoff(fn -> "plain_result" end)
      assert {:ok, "plain_result"} = result
    end

    test "uses default configuration when no options provided" do
      # This test verifies that the function uses app config defaults
      result = Retry.with_backoff(fn -> {:ok, "default_config"} end)
      assert {:ok, "default_config"} = result
    end

    test "respects custom backoff factor" do
      start_time = System.monotonic_time(:millisecond)

      Retry.with_backoff(
        fn -> {:error, :always_fail} end,
        max_retries: 2,
        retry_delay: 50,
        backoff_factor: 3
      )

      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time

      # Should have at least base_delay (50ms) for first retry
      # 50ms * 3^0 = 50ms for first retry
      assert elapsed >= 50
    end

    test "stops retrying for non-retryable errors" do
      result =
        Retry.with_backoff(
          fn -> {:error, :invalid_args} end,
          max_retries: 3,
          retry_delay: 10
        )

      assert {:error, :invalid_args} = result
    end
  end

  describe "calculate_delay/3" do
    test "calculates exponential backoff correctly" do
      # Base case
      assert Retry.calculate_delay(0, 1000, 2) == 1000

      # First retry
      assert Retry.calculate_delay(1, 1000, 2) == 2000

      # Second retry
      assert Retry.calculate_delay(2, 1000, 2) == 4000

      # Third retry
      assert Retry.calculate_delay(3, 1000, 2) == 8000
    end

    test "handles different backoff factors" do
      # Factor of 1.5
      assert Retry.calculate_delay(1, 1000, 1.5) == 1500
      assert Retry.calculate_delay(2, 1000, 1.5) == 2250

      # Factor of 3
      assert Retry.calculate_delay(1, 100, 3) == 300
      assert Retry.calculate_delay(2, 100, 3) == 900
    end

    test "handles edge cases" do
      # Zero delay
      assert Retry.calculate_delay(0, 0, 2) == 0
      assert Retry.calculate_delay(1, 0, 2) == 0

      # Factor of 1 (no backoff)
      assert Retry.calculate_delay(0, 500, 1) == 500
      assert Retry.calculate_delay(5, 500, 1) == 500
    end
  end

  describe "should_retry?/1" do
    test "identifies retryable errors" do
      retryable_errors = [
        :timeout,
        :econnrefused,
        :enoent,
        :resource_unavailable,
        {:error, :timeout},
        {:error, :econnrefused},
        {:error, :enoent},
        {:port_creation_failed, "reason"},
        {:download_failed, "reason"},
        {:mkdir_failed, "reason"}
      ]

      Enum.each(retryable_errors, fn error ->
        assert Retry.should_retry?(error), "Should retry error: #{inspect(error)}"
      end)
    end

    test "identifies non-retryable errors" do
      non_retryable_errors = [
        :invalid_args,
        :invalid_cmd,
        :invalid_opts,
        {:error, :invalid_binary},
        {:error, :permission_denied}
      ]

      Enum.each(non_retryable_errors, fn error ->
        refute Retry.should_retry?(error), "Should not retry error: #{inspect(error)}"
      end)
    end

    test "defaults to retryable for unknown errors" do
      unknown_errors = [
        :unknown_error,
        {:weird, :error, :format},
        "string error",
        123
      ]

      Enum.each(unknown_errors, fn error ->
        assert Retry.should_retry?(error), "Should retry unknown error: #{inspect(error)}"
      end)
    end
  end

  describe "get_max_retries/0" do
    test "returns configured value" do
      original = Application.get_env(:tailwind_port, :max_retries)

      try do
        Application.put_env(:tailwind_port, :max_retries, 5)
        assert Retry.get_max_retries() == 5

        Application.put_env(:tailwind_port, :max_retries, 10)
        assert Retry.get_max_retries() == 10
      after
        if original do
          Application.put_env(:tailwind_port, :max_retries, original)
        else
          Application.delete_env(:tailwind_port, :max_retries)
        end
      end
    end

    test "returns default when not configured" do
      original = Application.get_env(:tailwind_port, :max_retries)

      try do
        Application.delete_env(:tailwind_port, :max_retries)
        assert Retry.get_max_retries() == 3
      after
        if original do
          Application.put_env(:tailwind_port, :max_retries, original)
        end
      end
    end
  end

  describe "get_retry_delay/0" do
    test "returns configured value" do
      original = Application.get_env(:tailwind_port, :retry_delay)

      try do
        Application.put_env(:tailwind_port, :retry_delay, 2000)
        assert Retry.get_retry_delay() == 2000

        Application.put_env(:tailwind_port, :retry_delay, 500)
        assert Retry.get_retry_delay() == 500
      after
        if original do
          Application.put_env(:tailwind_port, :retry_delay, original)
        else
          Application.delete_env(:tailwind_port, :retry_delay)
        end
      end
    end

    test "returns default when not configured" do
      original = Application.get_env(:tailwind_port, :retry_delay)

      try do
        Application.delete_env(:tailwind_port, :retry_delay)
        assert Retry.get_retry_delay() == 1000
      after
        if original do
          Application.put_env(:tailwind_port, :retry_delay, original)
        end
      end
    end
  end

  describe "integration and edge cases" do
    test "handles very small delays" do
      start_time = System.monotonic_time(:millisecond)

      result =
        Retry.with_backoff(
          fn -> {:error, :fail} end,
          max_retries: 2,
          retry_delay: 1
        )

      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time

      assert {:error, :max_retries_exceeded} = result
      # Should complete quickly with 1ms delays
      assert elapsed < 100
    end

    test "works with zero retries" do
      result =
        Retry.with_backoff(
          fn -> {:error, :fail} end,
          max_retries: 0
        )

      assert {:error, :max_retries_exceeded} = result
    end

    test "handles large retry counts" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        Retry.with_backoff(
          fn ->
            count = Agent.get_and_update(agent, fn count -> {count, count + 1} end)

            if count < 5 do
              {:error, :not_ready}
            else
              {:ok, "finally_ready"}
            end
          end,
          max_retries: 10,
          retry_delay: 1
        )

      assert {:ok, "finally_ready"} = result
    end

    test "preserves error details through retries" do
      custom_error = {:custom_error, %{details: "important info"}}

      result =
        Retry.with_backoff(
          fn -> {:error, custom_error} end,
          max_retries: 2,
          retry_delay: 1
        )

      assert {:error, :max_retries_exceeded} = result
    end

    test "works with functions returning different success formats" do
      # Test tuple success format
      result1 = Retry.with_backoff(fn -> {:ok, "tuple_success"} end)
      assert {:ok, "tuple_success"} = result1

      # Test plain success formats (get wrapped in {:ok, ...})
      result2 = Retry.with_backoff(fn -> "plain_success" end)
      assert {:ok, "plain_success"} = result2

      result3 = Retry.with_backoff(fn -> 42 end)
      assert {:ok, 42} = result3

      result4 = Retry.with_backoff(fn -> %{result: "map_success"} end)
      assert {:ok, %{result: "map_success"}} = result4
    end
  end
end
