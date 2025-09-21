defmodule Defdo.TailwindPort do
  @moduledoc """
  High-level API for Tailwind CSS compilation with intelligent port pooling.

  This module delegates to `Defdo.TailwindPort.Optimized`, which manages a pool of
  Tailwind CLI ports, reuses live processes, and emits rich telemetry so you can
  track reuse rate, lifetimes, and performance KPIs out of the box.

  ## Quick Start

      # Start the optimized pool
      {:ok, _pid} = Defdo.TailwindPort.start_link()

      # Compile HTML snippets with automatic port reuse
      {:ok, result} = Defdo.TailwindPort.compile(opts, html)
      css = result.compiled_css

      # Inspect runtime stats / KPIs
      stats = Defdo.TailwindPort.get_stats()

  For advanced control over a single Tailwind port (the classic behaviour),
  use `Defdo.TailwindPort.Standalone` directly.
  """

  alias Defdo.TailwindPort.Optimized

  @doc """
  Starts the optimized Tailwind port pool.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  defdelegate start_link(opts \\ []), to: Optimized

  @doc """
  Compiles HTML content using pooled Tailwind ports.
  """
  @spec compile(keyword(), String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate compile(opts, content), to: Optimized

  @doc """
  Compiles multiple operations in a single call.
  """
  @spec batch_compile([Optimized.compile_operation()]) :: {:ok, [map()]} | {:error, term()}
  defdelegate batch_compile(operations), to: Optimized

  @doc """
  Returns runtime statistics and derived KPIs for the optimized pool.
  """
  @spec get_stats() :: map()
  defdelegate get_stats, to: Optimized

  @doc """
  Pre-warms common configurations so subsequent compilations hit a ready port.
  """
  @spec warm_up([keyword()]) :: :ok
  defdelegate warm_up(configs), to: Optimized
end
