defmodule Defdo.TailwindPort.Retry do
  @moduledoc """
  Retry logic functionality for TailwindPort operations.

  This module provides configurable retry mechanisms with exponential backoff
  for handling transient failures in port creation and other operations. It's
  designed to improve reliability when dealing with system resources that may
  temporarily be unavailable.

  ## Features

  - **Exponential Backoff**: Increases delay between retries to avoid overwhelming systems
  - **Configurable Limits**: Allows customization of retry count and delays
  - **Comprehensive Logging**: Detailed logging of retry attempts and failures
  - **Error Handling**: Proper error propagation and classification

  ## Configuration

  The retry behavior can be configured via application environment:

      # config/config.exs
      config :tailwind_port,
        max_retries: 3,
        retry_delay: 1000  # milliseconds

  For tests, you can use faster settings:

      # test/test_helper.exs
      Application.put_env(:tailwind_port, :retry_delay, 50)
      Application.put_env(:tailwind_port, :max_retries, 2)

  ## Usage

      # Retry port creation with exponential backoff
      case Retry.with_backoff(fn -> create_port(args) end) do
        {:ok, port} -> 
          # Port created successfully
        {:error, :max_retries_exceeded} ->
          # Failed after all retries
        {:error, reason} ->
          # Other error occurred
      end

  """

  require Logger

  @typedoc "Function that may fail and need retrying"
  @type retryable_fun :: (-> any())

  @typedoc "Retry configuration options"
  @type retry_opts :: [
          max_retries: non_neg_integer(),
          retry_delay: non_neg_integer(),
          backoff_factor: number()
        ]

  @doc """
  Executes a function with exponential backoff retry logic.

  This is the main entry point for retry functionality. It attempts to execute
  the provided function, retrying on failure with exponential backoff until
  either success or maximum retries are reached.

  ## Parameters

    * `fun` - Function to execute with retry logic
    * `opts` - Optional retry configuration (uses app config defaults if not provided)

  ## Options

    * `:max_retries` - Maximum number of retry attempts (default: from app config)
    * `:retry_delay` - Initial delay between retries in milliseconds (default: from app config)
    * `:backoff_factor` - Multiplier for exponential backoff (default: 2)

  ## Returns

    * `{:ok, result}` - Function succeeded, returns its result
    * `{:error, :max_retries_exceeded}` - All retry attempts failed
    * `{:error, reason}` - Function failed with non-retryable error

  ## Examples

      # Basic retry with default settings
      result = Retry.with_backoff(fn -> 
        risky_operation() 
      end)

      # Custom retry configuration
      result = Retry.with_backoff(
        fn -> create_resource() end,
        max_retries: 5,
        retry_delay: 2000,
        backoff_factor: 1.5
      )

      # Error handling
      case Retry.with_backoff(fn -> may_fail() end) do
        {:ok, result} -> 
          IO.puts("Success: " <> inspect(result))
        {:error, :max_retries_exceeded} ->
          IO.puts("Failed after all retries")
        {:error, reason} ->
          IO.puts("Error: " <> inspect(reason))
      end

  """
  @spec with_backoff(retryable_fun(), retry_opts()) :: {:ok, any()} | {:error, term()}
  def with_backoff(fun, opts \\ []) when is_function(fun, 0) do
    max_retries = Keyword.get(opts, :max_retries, get_max_retries())
    retry_delay = Keyword.get(opts, :retry_delay, get_retry_delay())
    backoff_factor = Keyword.get(opts, :backoff_factor, 2)

    execute_with_retry(fun, 0, max_retries, retry_delay, backoff_factor)
  end

  @doc """
  Calculates the delay for a specific retry attempt using exponential backoff.

  This function computes the delay time based on the retry attempt number
  and backoff configuration. It's useful for testing or when you need to
  predict retry timing.

  ## Parameters

    * `attempt` - Current retry attempt number (0-based)
    * `base_delay` - Base delay in milliseconds
    * `backoff_factor` - Exponential backoff multiplier

  ## Returns

    * `non_neg_integer()` - Delay in milliseconds for this attempt

  ## Examples

      # First retry (attempt 0)
      delay = Retry.calculate_delay(0, 1000, 2)
      assert delay == 1000

      # Second retry (attempt 1)  
      delay = Retry.calculate_delay(1, 1000, 2)
      assert delay == 2000

      # Third retry (attempt 2)
      delay = Retry.calculate_delay(2, 1000, 2)
      assert delay == 4000

      # With custom backoff factor
      delay = Retry.calculate_delay(1, 1000, 1.5)
      assert delay == 1500

  """
  @spec calculate_delay(non_neg_integer(), non_neg_integer(), number()) :: non_neg_integer()
  def calculate_delay(attempt, base_delay, backoff_factor) when attempt >= 0 do
    trunc(base_delay * :math.pow(backoff_factor, attempt))
  end

  @doc """
  Determines if an error should trigger a retry attempt.

  This function analyzes the error to decide whether retrying might be
  successful. Some errors are permanent and shouldn't be retried.

  ## Parameters

    * `error` - The error to analyze

  ## Returns

    * `true` - Error is potentially transient, retry may succeed
    * `false` - Error is permanent, retrying won't help

  ## Examples

      # Transient errors that should be retried
      assert Retry.should_retry?(:timeout)
      assert Retry.should_retry?({:error, :enoent})
      assert Retry.should_retry?(:resource_unavailable)

      # Permanent errors that shouldn't be retried
      refute Retry.should_retry?(:invalid_args)
      refute Retry.should_retry?({:error, :invalid_binary})

  """
  @spec should_retry?(term()) :: boolean()
  def should_retry?(error) do
    not permanent_error?(error)
  end

  defp permanent_error?(:invalid_args), do: true
  defp permanent_error?(:invalid_cmd), do: true
  defp permanent_error?(:invalid_opts), do: true
  defp permanent_error?({:error, :invalid_binary}), do: true
  defp permanent_error?({:error, :permission_denied}), do: true
  defp permanent_error?(_), do: false

  @doc """
  Gets the configured maximum number of retries.

  Returns the max_retries setting from application configuration,
  with a sensible default for production use.

  ## Returns

    * `non_neg_integer()` - Maximum retry attempts

  """
  @spec get_max_retries() :: non_neg_integer()
  def get_max_retries do
    Application.get_env(:tailwind_port, :max_retries, 3)
  end

  @doc """
  Gets the configured retry delay in milliseconds.

  Returns the retry_delay setting from application configuration,
  with a sensible default for production use.

  ## Returns

    * `non_neg_integer()` - Base retry delay in milliseconds

  """
  @spec get_retry_delay() :: non_neg_integer()
  def get_retry_delay do
    Application.get_env(:tailwind_port, :retry_delay, 1000)
  end

  @doc """
  Logs retry attempt information with appropriate detail.

  This function provides consistent logging for retry attempts,
  including attempt numbers, delays, and error information.

  ## Parameters

    * `attempt` - Current attempt number (1-based for logging)
    * `max_retries` - Maximum number of retries configured
    * `error` - The error that caused this retry
    * `delay` - Delay before next attempt in milliseconds

  """
  @spec log_retry_attempt(pos_integer(), non_neg_integer(), term(), non_neg_integer()) :: :ok
  def log_retry_attempt(attempt, max_retries, error, delay) do
    Logger.warning([
      "Retry attempt #{attempt}/#{max_retries} failed: #{inspect(error)}",
      if(attempt < max_retries, do: " - retrying in #{delay}ms", else: "")
    ])
  end

  # Private functions

  defp execute_with_retry(_fun, retry_count, max_retries, _delay, _backoff_factor)
       when retry_count >= max_retries do
    {:error, :max_retries_exceeded}
  end

  defp execute_with_retry(fun, retry_count, max_retries, base_delay, backoff_factor) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        handle_retry_error(reason, fun, retry_count, max_retries, base_delay, backoff_factor)

      # Assume success if not error tuple
      result ->
        {:ok, result}
    end
  rescue
    error ->
      handle_retry_error(error, fun, retry_count, max_retries, base_delay, backoff_factor)
  catch
    kind, reason ->
      error = {kind, reason}
      handle_retry_error(error, fun, retry_count, max_retries, base_delay, backoff_factor)
  end

  defp handle_retry_error(error, fun, retry_count, max_retries, base_delay, backoff_factor) do
    if should_retry?(error) and retry_count < max_retries - 1 do
      delay = calculate_delay(retry_count, base_delay, backoff_factor)
      log_retry_attempt(retry_count + 1, max_retries, error, delay)

      Process.sleep(delay)
      execute_with_retry(fun, retry_count + 1, max_retries, base_delay, backoff_factor)
    else
      if retry_count >= max_retries - 1 do
        log_retry_attempt(retry_count + 1, max_retries, error, 0)
        {:error, :max_retries_exceeded}
      else
        {:error, error}
      end
    end
  end
end
