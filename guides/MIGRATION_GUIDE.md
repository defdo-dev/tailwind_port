# Migration Guide

This guide helps you migrate between different versions of TailwindPort and understand breaking changes.

## Table of Contents

- [Migrating from 0.1.x to 0.2.0](#migrating-from-01x-to-020)
- [Breaking Changes](#breaking-changes)
- [New Features](#new-features)
- [Deprecated Features](#deprecated-features)
- [Step-by-Step Migration](#step-by-step-migration)
- [Common Issues](#common-issues)
- [Testing Your Migration](#testing-your-migration)

## Migrating from 0.1.x to 0.2.0

Version 0.2.0 introduces significant improvements in reliability, error handling, and monitoring capabilities. While most of the core API remains the same, there are important breaking changes to be aware of.

### Overview of Changes

- **Enhanced error handling**: All functions now return proper `{:ok, result}` or `{:error, reason}` tuples
- **Port synchronization**: New functions for reliable port startup and readiness checking
- **Health monitoring**: Comprehensive health metrics and monitoring capabilities
- **Security improvements**: Binary verification and enhanced download security
- **Configuration management**: New utilities for managing Tailwind configuration files

## Breaking Changes

### 1. Function Return Types

**Before (0.1.x):**
```elixir
# Functions returned results directly or raised exceptions
result = TailwindPort.new(:my_port, opts: opts)
TailwindDownload.install()
```

**After (0.2.0):**
```elixir
# Functions return {:ok, result} or {:error, reason} tuples
{:ok, result} = Defdo.TailwindPort.new(:my_port, opts: opts)
:ok = Defdo.TailwindDownload.install()

# With error handling
case Defdo.TailwindPort.new(:my_port, opts: opts) do
  {:ok, result} -> result
  {:error, reason} -> handle_error(reason)
end
```

### 2. Process Startup Synchronization

**Before (0.1.x):**
```elixir
# Unreliable timing-based approach
{:ok, pid} = TailwindPort.start_link(opts: opts)
Process.sleep(3000)  # Hope it's ready!
# Continue with operations...
```

**After (0.2.0):**
```elixir
# Reliable synchronization
{:ok, pid} = Defdo.TailwindPort.start_link(opts: opts)
:ok = Defdo.TailwindPort.Standalone.wait_until_ready(TailwindPort, 10_000)
# Now guaranteed to be ready
```

### 3. Module Namespace

**Before (0.1.x):**
```elixir
TailwindPort.start_link(opts)
TailwindDownload.install()
```

**After (0.2.0):**
```elixir
Defdo.TailwindPort.start_link(opts)
Defdo.TailwindDownload.install()
```

### 4. State Structure Changes

If you were accessing internal state (not recommended), the state structure has changed:

**Before (0.1.x):**
```elixir
%{
  port: port,
  name: name,
  opts: opts
}
```

**After (0.2.0):**
```elixir
%{
  port: port,
  name: name,
  opts: opts,
  port_ready: boolean(),
  health: health_map(),
  created_at: timestamp(),
  # ... additional fields
}
```

## New Features

### 1. Port Readiness Detection

```elixir
# Check if port is ready
if Defdo.TailwindPort.Standalone.ready?(:my_port) do
  IO.puts("Port is ready for operations")
end

# Wait for port to become ready
case Defdo.TailwindPort.Standalone.wait_until_ready(:my_port, 15_000) do
  :ok -> IO.puts("Port is ready!")
  {:error, :timeout} -> IO.puts("Port startup timed out")
end
```

### 2. Health Monitoring

```elixir
# Get comprehensive health metrics
{:ok, health} = Defdo.TailwindPort.Standalone.health(:my_port)
IO.inspect(health)
# %{
#   created_at: 1706364000000000000,
#   last_activity: 1706364120000000000,
#   total_outputs: 15,
#   css_builds: 3,
#   errors: 0,
#   uptime_seconds: 120.5,
#   port_active: true,
#   port_ready: true,
#   last_activity_seconds_ago: 2.1
# }
```

### 3. Configuration Management

```elixir
# Validate Tailwind config
case Defdo.TailwindPort.Config.validate_config("./tailwind.config.js") do
  :ok -> IO.puts("Config is valid")
  {:error, reason} -> IO.puts("Config error: #{inspect(reason)}")
end

# Ensure config exists (creates default if missing)
:ok = Defdo.TailwindPort.Config.ensure_config("./tailwind.config.js")

# Get effective configuration
config = Defdo.TailwindPort.Config.get_effective_config(opts: ["-w", "-m"])
```

### 4. Enhanced Error Handling

```elixir
# Comprehensive error handling with retry logic
case Defdo.TailwindPort.start_link(opts) do
  {:ok, pid} -> 
    IO.puts("Started successfully")
  {:error, :max_retries_exceeded} -> 
    IO.puts("Failed after maximum retries")
  {:error, :invalid_args} -> 
    IO.puts("Invalid arguments provided")
  {:error, reason} -> 
    IO.puts("Other error: #{inspect(reason)}")
end
```

## Deprecated Features

Currently, no features are deprecated, but the following patterns are discouraged:

### Timing-Based Synchronization

**Discouraged:**
```elixir
{:ok, pid} = Defdo.TailwindPort.start_link(opts)
Process.sleep(5000)  # Don't do this!
```

**Recommended:**
```elixir
{:ok, pid} = Defdo.TailwindPort.start_link(opts)
:ok = Defdo.TailwindPort.Standalone.wait_until_ready()
```

### Ignoring Error Tuples

**Discouraged:**
```elixir
# Ignoring potential errors
Defdo.TailwindPort.start_link(opts)
```

**Recommended:**
```elixir
# Proper error handling
case Defdo.TailwindPort.start_link(opts) do
  {:ok, pid} -> pid
  {:error, reason} -> handle_error(reason)
end
```

## Step-by-Step Migration

### Step 1: Update Dependencies

Update your `mix.exs`:

```elixir
def deps do
  [
    {:tailwind_port, "~> 0.3.0", organization: "defdo"}
  ]
end
```

Run:
```bash
mix deps.update tailwind_port
mix deps.get
```

### Step 2: Update Module References

Find and replace module references:

```bash
# In your project directory
grep -r "TailwindPort" lib/
grep -r "TailwindDownload" lib/
```

Update:
- `TailwindPort` → `Defdo.TailwindPort`
- `TailwindDownload` → `Defdo.TailwindDownload`

### Step 3: Update Function Calls

**Pattern matching for return values:**

```elixir
# Before
result = TailwindPort.new(:my_port, opts: opts)

# After
{:ok, result} = Defdo.TailwindPort.new(:my_port, opts: opts)
# or with error handling
case Defdo.TailwindPort.new(:my_port, opts: opts) do
  {:ok, result} -> result
  {:error, reason} -> handle_error(reason)
end
```

### Step 4: Replace Timing-Based Code

**Before:**
```elixir
{:ok, pid} = TailwindPort.start_link(opts: opts)
Process.sleep(3000)
# Continue...
```

**After:**
```elixir
{:ok, pid} = Defdo.TailwindPort.start_link(opts: opts)
:ok = Defdo.TailwindPort.Standalone.wait_until_ready()
# Continue...
```

### Step 5: Add Error Handling

Wrap TailwindPort operations in proper error handling:

```elixir
defmodule MyApp.TailwindManager do
  def start_tailwind(opts) do
    case Defdo.TailwindPort.start_link(opts) do
      {:ok, pid} ->
        case Defdo.TailwindPort.Standalone.wait_until_ready() do
          :ok -> {:ok, pid}
          {:error, :timeout} -> {:error, :startup_timeout}
        end
      {:error, reason} ->
        {:error, {:startup_failed, reason}}
    end
  end
end
```

### Step 6: Add Health Monitoring (Optional)

Take advantage of new health monitoring capabilities:

```elixir
defmodule MyApp.TailwindMonitor do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    port_name = Keyword.get(opts, :port_name, :default)
    :timer.send_interval(30_000, :health_check)  # Check every 30 seconds
    {:ok, %{port_name: port_name}}
  end
  
  def handle_info(:health_check, %{port_name: port_name} = state) do
    case Defdo.TailwindPort.Standalone.health(port_name) do
      {:ok, health} ->
        if health.errors > 0 do
          Logger.warn("Tailwind port has #{health.errors} errors")
        end
        
        if health.last_activity_seconds_ago > 300 do  # 5 minutes
          Logger.warn("Tailwind port inactive for #{health.last_activity_seconds_ago}s")
        end
        
      {:error, :not_found} ->
        Logger.error("Tailwind port #{port_name} not found")
    end
    
    {:noreply, state}
  end
end
```

### Step 7: Update Tests

Update your tests to handle new return types and use synchronization:

```elixir
defmodule MyApp.TailwindTest do
  use ExUnit.Case
  
  test "starts tailwind port successfully" do
    opts = [
      name: :test_port,
      opts: ["-i", "input.css", "-o", "output.css"]
    ]
    
    # Before
    # pid = TailwindPort.start_link(opts)
    # Process.sleep(1000)
    
    # After
    assert {:ok, pid} = Defdo.TailwindPort.start_link(opts)
    assert :ok = Defdo.TailwindPort.Standalone.wait_until_ready(:test_port, 5000)
    
    # Verify it's ready
    assert Defdo.TailwindPort.Standalone.ready?(:test_port)
    
    # Check health
    assert {:ok, health} = Defdo.TailwindPort.Standalone.health(:test_port)
    assert health.port_ready
    assert health.port_active
  end
end
```

## Common Issues

### Issue 1: Pattern Match Errors

**Error:**
```
** (MatchError) no match of right hand side value: {:error, :invalid_args}
```

**Solution:**
Update pattern matching to handle error tuples:

```elixir
# Instead of
result = Defdo.TailwindPort.new(:my_port, opts: opts)

# Use
{:ok, result} = Defdo.TailwindPort.new(:my_port, opts: opts)
# or
case Defdo.TailwindPort.new(:my_port, opts: opts) do
  {:ok, result} -> result
  {:error, reason} -> handle_error(reason)
end
```

### Issue 2: Undefined Function Errors

**Error:**
```
** (UndefinedFunctionError) function TailwindPort.start_link/1 is undefined
```

**Solution:**
Update module references:

```elixir
# Change
TailwindPort.start_link(opts)

# To
Defdo.TailwindPort.start_link(opts)
```

### Issue 3: Timing Issues in Tests

**Problem:**
Tests that previously used `Process.sleep/1` may fail due to timing.

**Solution:**
Use proper synchronization:

```elixir
# Instead of
{:ok, pid} = Defdo.TailwindPort.start_link(opts)
Process.sleep(2000)

# Use
{:ok, pid} = Defdo.TailwindPort.start_link(opts)
:ok = Defdo.TailwindPort.Standalone.wait_until_ready()
```

### Issue 4: Health Function Not Found

**Error:**
```
** (UndefinedFunctionError) function Defdo.TailwindPort.health/1 is undefined
```

**Solution:**
Ensure you're using version 0.2.0 or later:

```bash
mix deps.update tailwind_port
```

## Testing Your Migration

### 1. Compile Check

```bash
mix compile
```

Ensure there are no compilation errors.

### 2. Run Tests

```bash
mix test
```

All tests should pass with the new API.

### 3. Manual Testing

Create a simple test script:

```elixir
# test_migration.exs
defmodule MigrationTest do
  def test_basic_functionality do
    IO.puts("Testing TailwindPort 0.2.0...")
    
    # Test basic startup
    opts = [
      name: :migration_test,
      opts: ["-i", "assets/css/app.css", "-o", "priv/static/css/app.css"]
    ]
    
    case Defdo.TailwindPort.start_link(opts) do
      {:ok, _pid} ->
        IO.puts("✅ Port started successfully")
        
        case Defdo.TailwindPort.Standalone.wait_until_ready(:migration_test, 10_000) do
          :ok ->
            IO.puts("✅ Port ready")
            
            if Defdo.TailwindPort.Standalone.ready?(:migration_test) do
              IO.puts("✅ Ready check works")
            end
            
            case Defdo.TailwindPort.Standalone.health(:migration_test) do
              {:ok, health} ->
                IO.puts("✅ Health check works")
                IO.puts("   Uptime: #{health.uptime_seconds}s")
                IO.puts("   Ready: #{health.port_ready}")
              {:error, reason} ->
                IO.puts("❌ Health check failed: #{inspect(reason)}")
            end
            
          {:error, :timeout} ->
            IO.puts("❌ Port startup timed out")
        end
        
      {:error, reason} ->
        IO.puts("❌ Port startup failed: #{inspect(reason)}")
    end
  end
end

MigrationTest.test_basic_functionality()
```

Run with:
```bash
mix run test_migration.exs
```

### 4. Integration Testing

Test with your actual application:

1. Start your application
2. Verify CSS builds work correctly
3. Check that watch mode functions properly
4. Ensure production builds complete successfully

## Getting Help

If you encounter issues during migration:

1. **Check the CHANGELOG**: Review [CHANGELOG.md](../CHANGELOG.md) for detailed changes
2. **API Reference**: Consult [API_REFERENCE.md](./API_REFERENCE.md) for function signatures
3. **Examples**: See [EXAMPLES.md](./EXAMPLES.md) for usage patterns
4. **GitHub Issues**: [Report issues](https://github.com/defdo-dev/tailwind_cli_port/issues)
5. **Documentation**: [HexDocs](https://hexdocs.pm/tailwind_port)

## Summary

Migrating to TailwindPort 0.2.0 provides significant benefits:

- **Reliability**: Proper error handling and synchronization
- **Observability**: Health monitoring and telemetry
- **Security**: Binary verification and secure downloads
- **Developer Experience**: Better error messages and type specifications

While there are breaking changes, the migration is straightforward and the improvements make it worthwhile. The new API is more robust and production-ready.