# TailwindPort Examples

This document provides comprehensive examples for different use cases and integration patterns with TailwindPort.

## Table of Contents

- [Basic Examples](#basic-examples)
- [Phoenix Integration](#phoenix-integration)
- [Multiple Environments](#multiple-environments)
- [Production Builds](#production-builds)
- [Error Handling](#error-handling)
- [Health Monitoring](#health-monitoring)
- [Configuration Management](#configuration-management)
- [CI/CD Integration](#cicd-integration)
- [Advanced Patterns](#advanced-patterns)

## Basic Examples

### Simple One-time Build

```elixir
defmodule MyApp.SimpleBuild do
  def build_css do
    # Start TailwindPort for a single build
    {:ok, _pid} = Defdo.TailwindPort.start_link([
      name: :simple_build,
      opts: [
        "-i", "./assets/css/app.css",
        "-o", "./priv/static/css/app.css",
        "--content", "./lib/**/*.{ex,heex}"
      ]
    ])
    
    # Wait for completion
    case Defdo.TailwindPort.wait_until_ready(:simple_build, 10_000) do
      :ok -> 
        IO.puts("✅ CSS build completed successfully!")
        :ok
      {:error, :timeout} ->
        IO.puts("❌ Build timed out")
        {:error, :timeout}
    end
  end
end
```

### Watch Mode with Custom Configuration

```elixir
defmodule MyApp.DevWatcher do
  use GenServer
  require Logger
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    config = Keyword.merge(default_config(), opts)
    
    case start_watcher(config) do
      {:ok, port_name} -> 
        {:ok, %{port_name: port_name, config: config}}
      {:error, reason} -> 
        {:stop, reason}
    end
  end
  
  defp default_config do
    [
      input: "./assets/css/app.css",
      output: "./priv/static/css/app.css",
      content: "./lib/**/*.{ex,heex,js}",
      config_file: "./assets/tailwind.config.js",
      watch: true
    ]
  end
  
  defp start_watcher(config) do
    port_name = :dev_watcher
    
    opts = [
      name: port_name,
      opts: build_tailwind_args(config)
    ]
    
    with {:ok, _pid} <- Defdo.TailwindPort.start_link(opts),
         :ok <- Defdo.TailwindPort.wait_until_ready(port_name, 15_000) do
      Logger.info("🎨 Tailwind watcher started successfully")
      {:ok, port_name}
    else
      {:error, reason} -> 
        Logger.error("Failed to start Tailwind watcher: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp build_tailwind_args(config) do
    args = [
      "-i", config[:input],
      "-o", config[:output],
      "--content", config[:content]
    ]
    
    args = if config[:config_file], do: args ++ ["-c", config[:config_file]], else: args
    args = if config[:watch], do: args ++ ["--watch"], else: args
    args = if config[:minify], do: args ++ ["--minify"], else: args
    
    args
  end
end
```

## Phoenix Integration

### Complete Phoenix Setup

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      MyApp.Repo,
      MyAppWeb.Telemetry,
      {Phoenix.PubSub, name: MyApp.PubSub},
      
      # Add TailwindPort based on environment
      tailwind_child_spec(),
      
      MyAppWeb.Endpoint
    ]
    
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
  
  defp tailwind_child_spec do
    case Mix.env() do
      :dev -> {MyApp.TailwindManager, [mode: :watch]}
      :test -> {MyApp.TailwindManager, [mode: :build_once]}
      _ -> {MyApp.TailwindManager, [mode: :disabled]}
    end
  end
end

# lib/my_app/tailwind_manager.ex
defmodule MyApp.TailwindManager do
  use GenServer
  require Logger
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    mode = Keyword.get(opts, :mode, :disabled)
    
    case mode do
      :watch -> start_watch_mode()
      :build_once -> start_build_once()
      :disabled -> {:ok, %{mode: :disabled}}
    end
  end
  
  defp start_watch_mode do
    opts = [
      name: :phoenix_tailwind,
      opts: [
        "-i", "./assets/css/app.css",
        "-o", "./priv/static/css/app.css",
        "--content", "./lib/**/*.{ex,heex}",
        "-c", "./assets/tailwind.config.js",
        "--watch"
      ]
    ]
    
    case Defdo.TailwindPort.start_link(opts) do
      {:ok, _pid} ->
        Logger.info("🎨 Starting Tailwind CSS watcher for Phoenix...")
        
        # Start async task to wait for readiness
        task = Task.async(fn ->
          Defdo.TailwindPort.wait_until_ready(:phoenix_tailwind, 20_000)
        end)
        
        {:ok, %{mode: :watch, port_name: :phoenix_tailwind, startup_task: task}}
        
      {:error, reason} ->
        Logger.error("Failed to start Tailwind watcher: #{inspect(reason)}")
        {:stop, reason}
    end
  end
  
  defp start_build_once do
    # For test environment - build once and exit
    Task.start(fn ->
      MyApp.AssetBuilder.build_test_assets()
    end)
    
    {:ok, %{mode: :build_once}}
  end
  
  def handle_info({ref, :ok}, %{startup_task: %Task{ref: ref}} = state) do
    Logger.info("✅ Tailwind CSS watcher ready!")
    Process.demonitor(ref, [:flush])
    {:noreply, Map.delete(state, :startup_task)}
  end
  
  def handle_info({ref, {:error, :timeout}}, %{startup_task: %Task{ref: ref}} = state) do
    Logger.error("❌ Tailwind watcher startup timed out")
    Process.demonitor(ref, [:flush])
    {:noreply, Map.delete(state, :startup_task)}
  end
  
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{startup_task: %Task{ref: ref}} = state) do
    Logger.error("Tailwind startup task crashed: #{inspect(reason)}")
    {:noreply, Map.delete(state, :startup_task)}
  end
  
  def handle_info(_msg, state), do: {:noreply, state}
end
```

### Phoenix LiveView Integration

```elixir
# lib/my_app_web/live/tailwind_live.ex
defmodule MyAppWeb.TailwindLive do
  use MyAppWeb, :live_view
  
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to Tailwind telemetry events
      :telemetry.attach(
        "tailwind-css-builds",
        [:tailwind_port, :css, :done],
        &handle_css_build/4,
        %{live_view_pid: self()}
      )
    end
    
    socket = 
      socket
      |> assign(:tailwind_health, get_tailwind_health())
      |> assign(:css_builds, 0)
    
    {:ok, socket}
  end
  
  def handle_info({:css_build_complete, metadata}, socket) do
    socket = 
      socket
      |> update(:css_builds, &(&1 + 1))
      |> assign(:tailwind_health, get_tailwind_health())
      |> put_flash(:info, "CSS rebuilt at #{format_time(metadata.timestamp)}")
    
    {:noreply, socket}
  end
  
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-4xl mx-auto">
      <h1 class="text-3xl font-bold text-gray-900 mb-6">Tailwind CSS Status</h1>
      
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div class="bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold mb-4">Health Status</h2>
          <%= if @tailwind_health do %>
            <div class="space-y-2">
              <div class="flex justify-between">
                <span>Status:</span>
                <span class={["font-medium", status_color(@tailwind_health.port_ready)]}>
                  <%= if @tailwind_health.port_ready, do: "Ready", else: "Not Ready" %>
                </span>
              </div>
              <div class="flex justify-between">
                <span>Uptime:</span>
                <span><%= format_uptime(@tailwind_health.uptime_seconds) %></span>
              </div>
              <div class="flex justify-between">
                <span>CSS Builds:</span>
                <span><%= @tailwind_health.css_builds %></span>
              </div>
              <div class="flex justify-between">
                <span>Errors:</span>
                <span class={["font-medium", error_color(@tailwind_health.errors)]}>
                  <%= @tailwind_health.errors %>
                </span>
              </div>
            </div>
          <% else %>
            <p class="text-gray-500">Tailwind not running</p>
          <% end %>
        </div>
        
        <div class="bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold mb-4">Live Builds</h2>
          <p class="text-2xl font-bold text-blue-600"><%= @css_builds %></p>
          <p class="text-sm text-gray-500">Builds this session</p>
        </div>
      </div>
    </div>
    """
  end
  
  defp get_tailwind_health do
    case Defdo.TailwindPort.health(:phoenix_tailwind) do
      {:ok, health} -> health
      {:error, _} -> nil
    end
  end
  
  defp handle_css_build(_event, _measurements, metadata, %{live_view_pid: pid}) do
    send(pid, {:css_build_complete, metadata})
  end
  
  defp status_color(true), do: "text-green-600"
  defp status_color(false), do: "text-red-600"
  
  defp error_color(0), do: "text-green-600"
  defp error_color(_), do: "text-red-600"
  
  defp format_uptime(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}m #{remaining_seconds}s"
  end
  
  defp format_time(timestamp) do
    timestamp
    |> DateTime.from_unix!(:nanosecond)
    |> DateTime.to_time()
    |> Time.to_string()
  end
end
```

## Multiple Environments

### Environment-Specific Configuration

```elixir
defmodule MyApp.TailwindConfig do
  def get_config(env \\ Mix.env()) do
    base_config()
    |> Map.merge(env_specific_config(env))
  end
  
  defp base_config do
    %{
      input: "./assets/css/app.css",
      output: "./priv/static/css/app.css",
      content: "./lib/**/*.{ex,heex}",
      config_file: "./assets/tailwind.config.js"
    }
  end
  
  defp env_specific_config(:dev) do
    %{
      watch: true,
      minify: false,
      timeout: 15_000,
      port_name: :dev_tailwind
    }
  end
  
  defp env_specific_config(:test) do
    %{
      watch: false,
      minify: false,
      timeout: 30_000,
      port_name: :test_tailwind
    }
  end
  
  defp env_specific_config(:prod) do
    %{
      watch: false,
      minify: true,
      timeout: 60_000,
      port_name: :prod_tailwind
    }
  end
  
  def build_args(config) do
    args = [
      "-i", config.input,
      "-o", config.output,
      "--content", config.content,
      "-c", config.config_file
    ]
    
    args = if config[:watch], do: args ++ ["--watch"], else: args
    args = if config[:minify], do: args ++ ["--minify"], else: args
    
    args
  end
end

# Usage
defmodule MyApp.EnvironmentBuilder do
  def start_for_environment(env \\ Mix.env()) do
    config = MyApp.TailwindConfig.get_config(env)
    
    opts = [
      name: config.port_name,
      opts: MyApp.TailwindConfig.build_args(config)
    ]
    
    with {:ok, _pid} <- Defdo.TailwindPort.start_link(opts),
         :ok <- Defdo.TailwindPort.wait_until_ready(config.port_name, config.timeout) do
      {:ok, config.port_name}
    end
  end
end
```

## Production Builds

### Optimized Production Builder

```elixir
defmodule MyApp.ProductionBuilder do
  require Logger
  
  @build_timeout 120_000  # 2 minutes
  
  def build_all_assets do
    Logger.info("🏗️  Starting production asset build...")
    
    with :ok <- ensure_directories(),
         :ok <- validate_source_files(),
         {:ok, css_result} <- build_css(),
         :ok <- verify_output(),
         :ok <- optimize_assets() do
      
      Logger.info("✅ Production build completed successfully!")
      log_build_stats(css_result)
      :ok
    else
      {:error, reason} ->
        Logger.error("❌ Production build failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp ensure_directories do
    dirs = ["./priv/static/css", "./priv/static/js"]
    
    Enum.each(dirs, fn dir ->
      File.mkdir_p!(dir)
    end)
    
    :ok
  end
  
  defp validate_source_files do
    required_files = [
      "./assets/css/app.css",
      "./assets/tailwind.config.js"
    ]
    
    missing_files = 
      required_files
      |> Enum.reject(&File.exists?/1)
    
    case missing_files do
      [] -> :ok
      files -> {:error, {:missing_files, files}}
    end
  end
  
  defp build_css do
    Logger.info("📦 Building CSS with Tailwind...")
    
    opts = [
      name: :prod_css_build,
      opts: [
        "-i", "./assets/css/app.css",
        "-o", "./priv/static/css/app.css",
        "--content", "./lib/**/*.{ex,heex}",
        "-c", "./assets/tailwind.config.js",
        "--minify"
      ]
    ]
    
    start_time = System.monotonic_time(:millisecond)
    
    with {:ok, _pid} <- Defdo.TailwindPort.start_link(opts),
         :ok <- Defdo.TailwindPort.wait_until_ready(:prod_css_build, @build_timeout) do
      
      end_time = System.monotonic_time(:millisecond)
      build_time = end_time - start_time
      
      # Get health stats
      health = Defdo.TailwindPort.health(:prod_css_build)
      
      # Clean up
      Defdo.TailwindPort.terminate(:prod_css_build)
      
      result = %{
        build_time_ms: build_time,
        css_builds: health.css_builds,
        errors: health.errors
      }
      
      {:ok, result}
    end
  end
  
  defp verify_output do
    output_file = "./priv/static/css/app.css"
    
    cond do
      not File.exists?(output_file) ->
        {:error, :output_file_missing}
      
      File.stat!(output_file).size == 0 ->
        {:error, :output_file_empty}
      
      true ->
        Logger.info("📊 CSS file size: #{format_file_size(output_file)}")
        :ok
    end
  end
  
  defp optimize_assets do
    # Additional optimization steps
    Logger.info("⚡ Running additional optimizations...")
    
    # Example: Gzip compression
    css_file = "./priv/static/css/app.css"
    gzip_file = css_file <> ".gz"
    
    case System.cmd("gzip", ["-9", "-c", css_file], into: File.stream!(gzip_file)) do
      {_, 0} -> 
        Logger.info("📦 Gzip compression completed")
        :ok
      {_, _} -> 
        Logger.warn("⚠️  Gzip compression failed, continuing...")
        :ok
    end
  end
  
  defp log_build_stats(result) do
    Logger.info("""
    📊 Build Statistics:
    - Build time: #{result.build_time_ms}ms
    - CSS builds: #{result.css_builds}
    - Errors: #{result.errors}
    """)
  end
  
  defp format_file_size(file_path) do
    size = File.stat!(file_path).size
    
    cond do
      size > 1_000_000 -> "#{Float.round(size / 1_000_000, 2)} MB"
      size > 1_000 -> "#{Float.round(size / 1_000, 2)} KB"
      true -> "#{size} bytes"
    end
  end
end
```

## Error Handling

### Comprehensive Error Handling

```elixir
defmodule MyApp.RobustTailwind do
  require Logger
  
  @max_retries 3
  @retry_delay 1_000
  
  def start_with_retry(opts, retries \\ @max_retries) do
    case Defdo.TailwindPort.start_link(opts) do
      {:ok, pid} -> 
        {:ok, pid}
      
      {:error, reason} when retries > 0 ->
        Logger.warn("Tailwind start failed (#{@max_retries - retries + 1}/#{@max_retries}): #{inspect(reason)}")
        Process.sleep(@retry_delay * (@max_retries - retries + 1))
        start_with_retry(opts, retries - 1)
      
      {:error, reason} ->
        Logger.error("Tailwind start failed after #{@max_retries} retries: #{inspect(reason)}")
        {:error, {:max_retries_exceeded, reason}}
    end
  end
  
  def safe_operation(port_name, operation) do
    try do
      case Defdo.TailwindPort.ready?(port_name) do
        true -> 
          operation.()
        false -> 
          {:error, :port_not_ready}
      end
    rescue
      e -> 
        Logger.error("Operation failed: #{inspect(e)}")
        {:error, {:operation_failed, e}}
    end
  end
  
  def monitor_health(port_name, callback) do
    Task.start(fn ->
      monitor_loop(port_name, callback)
    end)
  end
  
  defp monitor_loop(port_name, callback) do
    case Defdo.TailwindPort.health(port_name) do
      {:ok, health} ->
        callback.({:health_update, health})
        
        # Check for concerning metrics
        if health.errors > 5 do
          callback.({:alert, :high_error_count, health.errors})
        end
        
        if health.last_activity_seconds_ago > 300 do  # 5 minutes
          callback.({:alert, :inactive_port, health.last_activity_seconds_ago})
        end
        
      {:error, reason} ->
        callback.({:error, :health_check_failed, reason})
    end
    
    Process.sleep(10_000)  # Check every 10 seconds
    monitor_loop(port_name, callback)
  end
end

# Usage example
defmodule MyApp.MonitoredTailwind do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    port_name = Keyword.get(opts, :name, :monitored_tailwind)
    
    case MyApp.RobustTailwind.start_with_retry([name: port_name] ++ opts) do
      {:ok, _pid} ->
        # Start health monitoring
        MyApp.RobustTailwind.monitor_health(port_name, fn event ->
          send(self(), {:health_event, event})
        end)
        
        {:ok, %{port_name: port_name, alerts: []}}
        
      {:error, reason} ->
        {:stop, reason}
    end
  end
  
  def handle_info({:health_event, {:health_update, health}}, state) do
    # Log health updates periodically
    if rem(System.system_time(:second), 60) == 0 do  # Every minute
      Logger.info("Tailwind health: #{health.css_builds} builds, #{health.uptime_seconds}s uptime")
    end
    
    {:noreply, state}
  end
  
  def handle_info({:health_event, {:alert, type, value}}, state) do
    alert = {type, value, System.system_time(:second)}
    Logger.warn("Tailwind alert: #{type} = #{value}")
    
    state = update_in(state.alerts, &[alert | Enum.take(&1, 9)])  # Keep last 10 alerts
    {:noreply, state}
  end
  
  def handle_info({:health_event, {:error, type, reason}}, state) do
    Logger.error("Tailwind health check error: #{type} - #{inspect(reason)}")
    {:noreply, state}
  end
end
```

## Health Monitoring

### Advanced Health Dashboard

```elixir
defmodule MyApp.TailwindDashboard do
  use GenServer
  require Logger
  
  defstruct [
    :port_name,
    :metrics_history,
    :alerts,
    :start_time
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def get_dashboard_data do
    GenServer.call(__MODULE__, :get_dashboard_data)
  end
  
  def init(opts) do
    port_name = Keyword.get(opts, :port_name, :default_tailwind)
    
    # Schedule periodic health checks
    :timer.send_interval(5_000, :health_check)
    
    state = %__MODULE__{
      port_name: port_name,
      metrics_history: [],
      alerts: [],
      start_time: System.system_time(:second)
    }
    
    {:ok, state}
  end
  
  def handle_call(:get_dashboard_data, _from, state) do
    data = %{
      port_name: state.port_name,
      uptime: System.system_time(:second) - state.start_time,
      recent_metrics: Enum.take(state.metrics_history, 20),
      active_alerts: get_active_alerts(state.alerts),
      summary: calculate_summary(state.metrics_history)
    }
    
    {:reply, data, state}
  end
  
  def handle_info(:health_check, state) do
    case Defdo.TailwindPort.health(state.port_name) do
      {:ok, health} ->
        timestamp = System.system_time(:second)
        metric = Map.put(health, :timestamp, timestamp)
        
        # Add to history (keep last 100 entries)
        metrics_history = [metric | Enum.take(state.metrics_history, 99)]
        
        # Check for alerts
        new_alerts = check_for_alerts(health, timestamp)
        alerts = new_alerts ++ state.alerts
        
        state = %{state | metrics_history: metrics_history, alerts: alerts}
        {:noreply, state}
        
      {:error, reason} ->
        Logger.warn("Health check failed for #{state.port_name}: #{inspect(reason)}")
        {:noreply, state}
    end
  end
  
  defp check_for_alerts(health, timestamp) do
    alerts = []
    
    # High error rate
    alerts = if health.errors > 10 do
      [{:high_errors, health.errors, timestamp} | alerts]
    else
      alerts
    end
    
    # Port not ready
    alerts = if not health.port_ready do
      [{:port_not_ready, nil, timestamp} | alerts]
    else
      alerts
    end
    
    # Long inactivity
    alerts = if health.last_activity_seconds_ago > 600 do  # 10 minutes
      [{:long_inactivity, health.last_activity_seconds_ago, timestamp} | alerts]
    else
      alerts
    end
    
    alerts
  end
  
  defp get_active_alerts(alerts) do
    current_time = System.system_time(:second)
    
    alerts
    |> Enum.filter(fn {_type, _value, timestamp} -> 
      current_time - timestamp < 300  # Last 5 minutes
    end)
    |> Enum.uniq_by(fn {type, _value, _timestamp} -> type end)
  end
  
  defp calculate_summary(metrics_history) do
    case metrics_history do
      [] -> %{}
      metrics ->
        %{
          total_builds: List.first(metrics).css_builds,
          avg_uptime: Enum.map(metrics, & &1.uptime_seconds) |> Enum.sum() |> div(length(metrics)),
          total_errors: List.first(metrics).errors,
          data_points: length(metrics)
        }
    end
  end
end
```

## CI/CD Integration

### GitHub Actions Example

```yaml
# .github/workflows/assets.yml
name: Build Assets

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  build-assets:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.15'
        otp-version: '26'
    
    - name: Cache deps
      uses: actions/cache@v3
      with:
        path: deps
        key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
    
    - name: Install dependencies
      run: mix deps.get
    
    - name: Compile project
      run: mix compile
    
    - name: Build production assets
      run: mix run -e "MyApp.ProductionBuilder.build_all_assets()"
    
    - name: Verify assets
      run: |
        test -f priv/static/css/app.css
        test -s priv/static/css/app.css
    
    - name: Upload assets
      uses: actions/upload-artifact@v3
      with:
        name: built-assets
        path: priv/static/
```

### Docker Build Example

```dockerfile
# Dockerfile
FROM elixir:1.15-alpine AS builder

# Install build dependencies
RUN apk add --no-cache build-base git

WORKDIR /app

# Copy mix files
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy source code
COPY . .

# Build the application
RUN mix compile

# Build production assets
RUN mix run -e "MyApp.ProductionBuilder.build_all_assets()"

# Production stage
FROM alpine:3.18

RUN apk add --no-cache openssl ncurses-libs

WORKDIR /app

# Copy built application and assets
COPY --from=builder /app/_build/prod/rel/my_app ./
COPY --from=builder /app/priv/static ./priv/static/

CMD ["./bin/my_app", "start"]
```

These examples provide comprehensive patterns for integrating TailwindPort into various scenarios, from simple builds to complex production deployments with monitoring and CI/CD integration.