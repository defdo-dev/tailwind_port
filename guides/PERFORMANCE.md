# Performance Guide & Best Practices

This guide covers performance optimization techniques, best practices, and common patterns for using TailwindPort in production environments.

## Table of Contents

- [Performance Optimization](#performance-optimization)
- [Best Practices](#best-practices)
- [Common Patterns](#common-patterns)
- [Monitoring & Observability](#monitoring--observability)
- [Troubleshooting](#troubleshooting)

## Performance Optimization

### 1. Port Lifecycle Management

**✅ DO: Use proper synchronization**
```elixir
# Good - reliable synchronization
{:ok, _pid} = TailwindPort.start_link(opts: build_opts)
:ok = TailwindPort.wait_until_ready()
# Port is now ready for use
```

**❌ DON'T: Use arbitrary sleeps**
```elixir
# Bad - unreliable and slow
{:ok, _pid} = TailwindPort.start_link(opts: build_opts)
Process.sleep(2000)  # Unreliable timing
```

### 2. Watch Mode Optimization

For development environments, optimize watch mode for faster rebuilds:

```elixir
# Optimized watch mode configuration
opts = [
  "-i", "./assets/css/app.css",
  "--content", "./lib/**/*.{ex,heex,sface}",  # Specific file patterns
  "-o", "./priv/static/css/app.css",
  "--watch",
  "--poll"  # Use polling on systems with filesystem event issues
]

{:ok, _pid} = TailwindPort.start_link(name: :dev_watcher, opts: opts)
```

### 3. Production Build Optimization

For production builds, prioritize build speed and output optimization:

```elixir
# Production build configuration
production_opts = [
  "-i", "./assets/css/app.css",
  "--content", "./lib/**/*.{ex,heex,sface}",
  "--content", "./assets/js/**/*.js",
  "-o", "./priv/static/css/app.css",
  "--minify",              # Minimize output size
  "--no-autoprefixer"      # Skip if handled elsewhere
]

{:ok, _pid} = TailwindPort.start_link(name: :prod_build, opts: production_opts)
:ok = TailwindPort.wait_until_ready(:prod_build, 30_000)  # Longer timeout for production
```

### 4. Content Path Optimization

Optimize content paths to reduce file scanning overhead:

```elixir
# Specific patterns - faster scanning
content_paths = [
  "--content", "./lib/my_app_web/**/*.{ex,heex}",
  "--content", "./assets/js/**/*.{js,ts}",
  "--content", "./priv/static/html/*.html"
]

# Avoid overly broad patterns
# "--content", "./**/*"  # Too broad - scans everything
```

## Best Practices

### 1. Error Handling

Always handle errors properly and implement retry logic:

```elixir
defmodule MyApp.TailwindManager do
  def ensure_css_build(opts) do
    case TailwindPort.new(:css_build, opts: opts) do
      {:ok, _state} ->
        case TailwindPort.wait_until_ready(:css_build, 15_000) do
          :ok ->
            {:ok, :build_ready}
          {:error, :timeout} ->
            TailwindPort.terminate(:css_build)
            {:error, :build_timeout}
        end
      
      {:error, :max_retries_exceeded} ->
        {:error, :port_creation_failed}
      
      {:error, reason} ->
        {:error, {:port_error, reason}}
    end
  end
end
```

### 2. Health Monitoring

Implement comprehensive health monitoring:

```elixir
defmodule MyApp.TailwindHealthChecker do
  def check_health(name) do
    health = TailwindPort.health(name)
    
    cond do
      not health.port_ready ->
        {:warning, "Port not ready"}
      
      health.errors > 0 ->
        error_rate = health.errors / max(health.total_outputs, 1)
        if error_rate > 0.1 do
          {:error, "High error rate: #{Float.round(error_rate * 100, 1)}%"}
        else
          {:ok, "Acceptable error rate"}
        end
      
      health.last_activity_seconds_ago > 300 ->
        {:warning, "No activity for 5+ minutes"}
      
      true ->
        {:ok, "Healthy"}
    end
  end
end
```

### 3. Named Process Management

Use named processes for better debugging and management:

```elixir
# Good - named processes for different environments
defmodule MyApp.TailwindSupervisor do
  def start_dev_watcher do
    TailwindPort.start_link(
      name: :dev_tailwind,
      opts: ["-w", "-i", "input.css", "-o", "output.css"]
    )
  end
  
  def start_prod_build do
    TailwindPort.start_link(
      name: :prod_tailwind,
      opts: ["-m", "-i", "input.css", "-o", "output.css"]
    )
  end
end
```

### 4. Configuration Management

Use configuration files for maintainable setups:

```elixir
# config/dev.exs
config :my_app, :tailwind,
  dev_opts: [
    "-i", "./assets/css/app.css",
    "--content", "./lib/**/*.{ex,heex}",
    "-o", "./priv/static/css/app.css",
    "--watch"
  ]

# config/prod.exs  
config :my_app, :tailwind,
  prod_opts: [
    "-i", "./assets/css/app.css",
    "--content", "./lib/**/*.{ex,heex}",
    "-o", "./priv/static/css/app.css",
    "--minify"
  ]

# Usage
def get_tailwind_opts do
  Application.get_env(:my_app, :tailwind)[Mix.env()]
end
```

## Common Patterns

### 1. Build Pipeline Integration

Integrate TailwindPort into your build pipeline:

```elixir
defmodule MyApp.BuildPipeline do
  def run_full_build do
    with {:ok, _} <- ensure_assets_dir(),
         {:ok, _} <- compile_css(),
         {:ok, _} <- optimize_assets() do
      {:ok, :build_complete}
    end
  end
  
  defp compile_css do
    opts = Application.get_env(:my_app, :tailwind)[:prod_opts]
    
    case TailwindPort.new(:build_css, opts: opts) do
      {:ok, _} ->
        TailwindPort.wait_until_ready(:build_css, 30_000)
      error ->
        error
    end
  end
end
```

### 2. Development Server Integration

For development servers like Phoenix:

```elixir
# In your application.ex
defmodule MyApp.Application do
  def start(_type, _args) do
    children = [
      # ... other children
      {MyApp.TailwindWatcher, []}
    ]
    
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

defmodule MyApp.TailwindWatcher do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    if Mix.env() == :dev do
      start_watcher()
    end
    {:ok, %{}}
  end
  
  defp start_watcher do
    opts = Application.get_env(:my_app, :tailwind)[:dev_opts]
    
    case TailwindPort.start_link(name: :dev_watcher, opts: opts) do
      {:ok, _pid} ->
        TailwindPort.wait_until_ready(:dev_watcher)
        Logger.info("Tailwind watcher started successfully")
      
      {:error, reason} ->
        Logger.error("Failed to start Tailwind watcher: #{inspect(reason)}")
    end
  end
end
```

### 3. Circuit Breaker Pattern

Implement circuit breaker for resilience:

```elixir
defmodule MyApp.TailwindCircuitBreaker do
  use GenServer
  
  @failure_threshold 5
  @recovery_timeout 30_000
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def build_css(opts) do
    GenServer.call(__MODULE__, {:build_css, opts})
  end
  
  def init(_opts) do
    {:ok, %{state: :closed, failures: 0, last_failure: nil}}
  end
  
  def handle_call({:build_css, opts}, _from, %{state: :open} = state) do
    if should_attempt_recovery?(state) do
      attempt_build(opts, %{state | state: :half_open})
    else
      {:reply, {:error, :circuit_open}, state}
    end
  end
  
  def handle_call({:build_css, opts}, _from, state) do
    attempt_build(opts, state)
  end
  
  defp attempt_build(opts, state) do
    case TailwindPort.new(:circuit_build, opts: opts) do
      {:ok, _} ->
        case TailwindPort.wait_until_ready(:circuit_build, 15_000) do
          :ok ->
            TailwindPort.terminate(:circuit_build)
            {:reply, {:ok, :build_success}, %{state | failures: 0, state: :closed}}
          
          {:error, _} = error ->
            handle_failure(error, state)
        end
      
      {:error, _} = error ->
        handle_failure(error, state)
    end
  end
  
  defp handle_failure(error, state) do
    failures = state.failures + 1
    
    new_state = 
      if failures >= @failure_threshold do
        %{state | failures: failures, state: :open, last_failure: System.system_time()}
      else
        %{state | failures: failures}
      end
    
    {:reply, error, new_state}
  end
  
  defp should_attempt_recovery?(%{last_failure: last_failure}) do
    System.system_time() - last_failure > @recovery_timeout
  end
end
```

## Monitoring & Observability

### 1. Telemetry Integration

Set up telemetry for monitoring:

```elixir
defmodule MyApp.TailwindTelemetry do
  def setup do
    :telemetry.attach_many(
      "tailwind-port-handler",
      [
        [:tailwind_port, :css, :done],
        [:tailwind_port, :other, :done], 
        [:tailwind_port, :port, :exit]
      ],
      &handle_event/4,
      nil
    )
  end
  
  defp handle_event([:tailwind_port, :css, :done], measurements, metadata, _config) do
    Logger.info("CSS build completed", 
      css_builds: measurements.css_builds,
      port: inspect(metadata.port)
    )
  end
  
  defp handle_event([:tailwind_port, :port, :exit], measurements, metadata, _config) do
    if measurements.exit_status != 0 do
      Logger.error("Port exited with error", 
        exit_status: measurements.exit_status,
        port: inspect(metadata.port)
      )
    end
  end
  
  defp handle_event(event, measurements, metadata, _config) do
    Logger.debug("Tailwind event", 
      event: event,
      measurements: measurements,
      metadata: metadata
    )
  end
end
```

### 2. Metrics Collection

Collect performance metrics:

```elixir
defmodule MyApp.TailwindMetrics do
  def collect_metrics(name) do
    health = TailwindPort.health(name)
    
    # Example metrics you might want to track
    %{
      uptime_seconds: health.uptime_seconds,
      build_rate: health.css_builds / max(health.uptime_seconds, 1),
      error_rate: health.errors / max(health.total_outputs, 1),
      activity_freshness: health.last_activity_seconds_ago,
      port_status: if(health.port_ready, do: "ready", else: "not_ready")
    }
  end
  
  def log_metrics(name) do
    metrics = collect_metrics(name)
    
    Logger.info("Tailwind metrics", 
      name: name,
      build_rate: Float.round(metrics.build_rate, 3),
      error_rate: Float.round(metrics.error_rate, 3),
      uptime: Float.round(metrics.uptime_seconds, 1),
      status: metrics.port_status
    )
  end
end
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Port Not Becoming Ready

**Problem**: `wait_until_ready/2` times out

**Solutions**:
```elixir
# Check if binary exists and is executable
case TailwindPort.ready?(:my_port, 1000) do
  false ->
    # Port might be starting up, check health
    health = TailwindPort.health(:my_port)
    
    if health.port_active do
      Logger.info("Port is active but not ready yet, waiting longer...")
      TailwindPort.wait_until_ready(:my_port, 30_000)
    else
      Logger.error("Port is not active, restarting...")
      TailwindPort.terminate(:my_port)
      # Restart logic here
    end
  
  true ->
    Logger.info("Port is ready!")
end
```

#### 2. High Error Rates

**Problem**: Many errors in health metrics

**Solutions**:
```elixir
# Analyze error patterns
health = TailwindPort.health(:my_port)

if health.errors > 0 do
  error_rate = health.errors / health.total_outputs
  
  cond do
    error_rate > 0.5 ->
      Logger.error("Critical error rate, restarting port")
      TailwindPort.terminate(:my_port)
    
    error_rate > 0.1 ->
      Logger.warning("High error rate, monitoring closely")
    
    true ->
      Logger.info("Acceptable error rate: #{Float.round(error_rate * 100, 1)}%")
  end
end
```

#### 3. Memory Leaks

**Problem**: Memory usage growing over time

**Solutions**:
```elixir
# Monitor process memory and restart if needed
defmodule MyApp.MemoryMonitor do
  def check_memory(pid) do
    {:memory, memory} = Process.info(pid, :memory)
    
    # Restart if memory exceeds threshold (e.g., 100MB)
    if memory > 100_000_000 do
      Logger.warning("High memory usage detected, restarting TailwindPort")
      TailwindPort.terminate(pid)
      # Restart logic
    end
  end
end
```

#### 4. Build Performance Issues

**Problem**: Slow CSS compilation

**Solutions**:
```elixir
# Optimize content paths and options
optimized_opts = [
  "-i", "./assets/css/app.css",
  
  # Be specific with content paths
  "--content", "./lib/my_app_web/**/*.{ex,heex}",  # Not "./lib/**/*"
  "--content", "./assets/js/app.js",              # Specific files
  
  "-o", "./priv/static/css/app.css",
  
  # Consider using config file for complex setups
  "-c", "./assets/tailwind.config.js"
]
```

### Debug Mode

Enable debug logging for troubleshooting:

```elixir
# In config/dev.exs
config :logger, level: :debug

# Or set at runtime
Logger.configure(level: :debug)
```

This will show detailed port creation and output information from TailwindPort.