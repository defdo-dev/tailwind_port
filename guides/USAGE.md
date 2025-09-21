# Usage Guide

## Overview

TailwindPort is a robust Elixir library for integrating Tailwind CSS CLI with comprehensive error handling, health monitoring, and telemetry features. It provides a GenServer-based interface for managing Tailwind CSS processes in Elixir applications.

## Basic Usage

### Installation

Add `tailwind_port` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tailwind_port, "~> 0.3.0"}
  ]
end
```

### Quick Start

```elixir
# Start a TailwindPort process
{:ok, pid} = Defdo.TailwindPort.start_link(
  opts: ["-i", "assets/css/app.css", "-o", "priv/static/assets/app.css", "-w"]
)

# Check if the port is ready
:ok = Defdo.TailwindPort.Standalone.wait_until_ready(pid, 5000)

# Get health information
health = Defdo.TailwindPort.Standalone.health(pid)
```

## Configuration

### Environment Configuration

```elixir
# config/config.exs
config :tailwind_port,
  version: "3.4.1",
  path: "/usr/local/bin/tailwindcss",
  url: "https://github.com/tailwindlabs/tailwindcss/releases/download/v$version/tailwindcss-$target"
```

### Telemetry Configuration

TailwindPort includes comprehensive telemetry integration:

```elixir
# Attach telemetry handlers
:telemetry.attach_many(
  "tailwind-port-handler",
  [
    [:tailwind_port, :compile, :start],
    [:tailwind_port, :compile, :complete],
    [:tailwind_port, :download, :complete],
    [:tailwind_port, :error, :port_exit]
  ],
  &MyApp.TelemetryHandler.handle_event/4,
  %{}
)
```

## API Reference

### Starting Processes

```elixir
# Start with default name
{:ok, pid} = Defdo.TailwindPort.start_link(opts: ["-w"])

# Start with custom name
{:ok, pid} = Defdo.TailwindPort.start_link(
  opts: ["-i", "input.css", "-o", "output.css"],
  name: :my_tailwind
)
```

### Process Management

```elixir
# Get current state
state = Defdo.TailwindPort.state(:my_tailwind)

# Wait for readiness
case Defdo.TailwindPort.Standalone.wait_until_ready(:my_tailwind, 5000) do
  :ok -> IO.puts("Ready!")
  {:error, :timeout} -> IO.puts("Timed out waiting")
end

# Check readiness
ready? = Defdo.TailwindPort.Standalone.ready?(:my_tailwind, 1000)

# Get health metrics
health = Defdo.TailwindPort.Standalone.health(:my_tailwind)
```

### File System Operations

```elixir
# Initialize file system tracking
fs = Defdo.TailwindPort.init_fs(:my_tailwind)

# Update file system with new files
updated_fs = Defdo.TailwindPort.update_fs(:my_tailwind, ["new_file.css"])

# Combined update and init
fs = Defdo.TailwindPort.update_and_init_fs(:my_tailwind, ["file1.css", "file2.css"])
```

## Error Handling

TailwindPort provides comprehensive error handling:

```elixir
case Defdo.TailwindPort.start_link(opts: ["--invalid-flag"]) do
  {:ok, pid} ->
    # Success case
    :ok
  {:error, reason} ->
    Logger.error("Failed to start TailwindPort: #{inspect(reason)}")
end
```

## Health Monitoring

The health system provides detailed metrics:

```elixir
health = Defdo.TailwindPort.Standalone.health(:my_tailwind)

# Health structure:
%{
  uptime_seconds: 45.2,
  port_ready: true,
  port_active: true,
  total_outputs: 15,
  css_builds: 3,
  errors: 0,
  last_activity: 1634567890,
  last_activity_seconds_ago: 2.1,
  created_at: 1634567845
}
```

## Telemetry Events

TailwindPort emits the following telemetry events:

### Compilation Events
- `[:tailwind_port, :compile, :start]` - Compilation started
- `[:tailwind_port, :compile, :complete]` - Compilation finished
- `[:tailwind_port, :compile, :error]` - Compilation failed

### Download Events
- `[:tailwind_port, :download, :start]` - Binary download started
- `[:tailwind_port, :download, :complete]` - Binary download finished
- `[:tailwind_port, :download, :error]` - Binary download failed

### Performance Events
- `[:tailwind_port, :performance, :memory]` - Memory usage metrics
- `[:tailwind_port, :performance, :cpu]` - CPU usage metrics
- `[:tailwind_port, :performance, :concurrency]` - Concurrency metrics

### Health Events
- `[:tailwind_port, :health, :healthy]` - System healthy
- `[:tailwind_port, :health, :degraded]` - Performance degraded
- `[:tailwind_port, :health, :critical]` - Critical issues

### Error Events
- `[:tailwind_port, :error, :port_exit]` - Port process exited
- `[:tailwind_port, :error, :download_failed]` - Download failed
- `[:tailwind_port, :error, :compilation_failed]` - Compilation failed

## Best Practices

### 1. Use Named Processes

```elixir
# Good - use named processes for easy access
{:ok, _} = Defdo.TailwindPort.start_link(opts: ["-w"], name: :main_tailwind)

# Access later without keeping PID
state = Defdo.TailwindPort.state(:main_tailwind)
```

### 2. Handle Timeouts

```elixir
# Always handle timeout cases
case Defdo.TailwindPort.Standalone.wait_until_ready(:main_tailwind, 5000) do
  :ok -> 
    proceed_with_build()
  {:error, :timeout} -> 
    Logger.warning("Tailwind not ready after 5 seconds")
    handle_timeout()
end
```

### 3. Monitor Health

```elixir
# Regular health monitoring
health = Defdo.TailwindPort.Standalone.health(:main_tailwind)
if health.errors > 0 do
  Logger.warning("Tailwind has #{health.errors} errors")
end
```

### 4. Use Telemetry

```elixir
# Set up comprehensive telemetry monitoring
defmodule MyApp.TelemetryHandler do
  def handle_event([:tailwind_port, :compile, :complete], measurements, metadata, _config) do
    Logger.info("CSS compiled in #{measurements.duration_ms}ms")
  end

  def handle_event([:tailwind_port, :error, :port_exit], _measurements, metadata, _config) do
    Logger.error("Tailwind port exited: #{inspect(metadata)}")
  end
end
```

## Troubleshooting

### Common Issues

1. **Port Not Ready**: Increase timeout or check Tailwind CLI options
2. **Binary Not Found**: Run `Defdo.TailwindDownload.install()` to download
3. **Permission Errors**: Ensure binary is executable
4. **Watch Mode Issues**: Verify file paths and permissions

### Debug Information

```elixir
# Get detailed state information
state = Defdo.TailwindPort.state(:my_tailwind)
IO.inspect(state, label: "TailwindPort State")

# Check health metrics
health = Defdo.TailwindPort.Standalone.health(:my_tailwind)
IO.inspect(health, label: "Health Metrics")
```