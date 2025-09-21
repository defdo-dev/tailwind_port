# Developer Guide

A comprehensive guide for developers working with TailwindPort - the robust Elixir library for integrating Tailwind CSS CLI.

## Table of Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
- [Architecture](#architecture)
- [Development Workflow](#development-workflow)
- [Best Practices](#best-practices)
- [Testing](#testing)
- [Deployment](#deployment)
- [Monitoring & Debugging](#monitoring--debugging)
- [Performance Optimization](#performance-optimization)
- [Security Considerations](#security-considerations)
- [Contributing](#contributing)
- [Resources](#resources)

## Overview

TailwindPort is a production-ready Elixir library that provides a robust interface to the Tailwind CSS CLI. It's designed with reliability, observability, and developer experience in mind.

### Key Features

- **Production-Ready Reliability**: Comprehensive error handling, automatic retries, input validation, and graceful cleanup
- **Port Synchronization**: Readiness detection, synchronous startup, configurable timeouts
- **Health Monitoring**: Real-time metrics, activity tracking, telemetry integration
- **Security**: Binary verification, secure downloads, input sanitization
- **Configuration Management**: Validation, default creation, effective resolution

### When to Use TailwindPort

✅ **Good for:**
- Phoenix applications requiring Tailwind CSS integration
- Applications needing reliable CSS build processes
- Production environments requiring monitoring and observability
- Projects with complex CSS build requirements
- Applications requiring hot reload during development

❌ **Not ideal for:**
- Simple static sites (consider using Tailwind CLI directly)
- Applications with very basic CSS needs
- Environments where Elixir/OTP overhead isn't justified

## Getting Started

### Prerequisites

- Elixir 1.16 or later
- Erlang/OTP 26 or later
- Node.js (for Tailwind CSS CLI)

### Quick Installation

1. **Add to dependencies** in `mix.exs`:
   ```elixir
   def deps do
     [
       {:tailwind_port, "~> 0.2.0", organization: "defdo"}
     ]
   end
   ```

2. **Install dependencies**:
   ```bash
   mix deps.get
   ```

3. **Install Tailwind CSS binary**:
   ```elixir
   # In your application or IEx
   :ok = Defdo.TailwindDownload.install()
   ```

4. **Basic usage**:
   ```elixir
   # Start a TailwindPort process
   {:ok, _pid} = Defdo.TailwindPort.start_link([
     name: :my_tailwind,
     opts: ["-i", "assets/css/app.css", "-o", "priv/static/css/app.css"]
   ])
   
   # Wait for it to be ready
   :ok = Defdo.TailwindPort.wait_until_ready(:my_tailwind)
   
   # Check health
   {:ok, health} = Defdo.TailwindPort.health(:my_tailwind)
   ```

For detailed setup instructions, see [QUICK_START.md](./QUICK_START.md).

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                    TailwindPort Application                 │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │ TailwindPort    │  │ TailwindDownload│  │ Config      │ │
│  │ (GenServer)     │  │ (Module)        │  │ (Module)    │ │
│  │                 │  │                 │  │             │ │
│  │ • Port Mgmt     │  │ • Binary DL     │  │ • Validation│ │
│  │ • Health Track  │  │ • Verification  │  │ • Defaults  │ │
│  │ • Telemetry     │  │ • Security      │  │ • Resolution│ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                    Erlang Port (Tailwind CLI)              │
└─────────────────────────────────────────────────────────────┘
```

### Process Lifecycle

1. **Initialization**: GenServer starts, validates configuration
2. **Port Creation**: Spawns Tailwind CLI process via Erlang port
3. **Readiness Detection**: Monitors port output for readiness signals
4. **Operation**: Handles CSS builds, watches for changes
5. **Health Monitoring**: Tracks metrics, activity, errors
6. **Cleanup**: Graceful shutdown, port termination

### State Management

The TailwindPort GenServer maintains state including:

```elixir
%{
  port: port(),                    # Erlang port reference
  name: atom(),                    # Process name
  opts: [String.t()],             # Tailwind CLI options
  port_ready: boolean(),          # Readiness status
  health: map(),                  # Health metrics
  created_at: integer(),          # Creation timestamp
  last_activity: integer(),       # Last activity timestamp
  total_outputs: integer(),       # Output counter
  css_builds: integer(),          # CSS build counter
  errors: integer()               # Error counter
}
```

## Development Workflow

### Local Development Setup

1. **Clone and setup**:
   ```bash
   git clone <your-project>
   cd <your-project>
   mix deps.get
   mix compile
   ```

2. **Install Tailwind binary**:
   ```bash
   mix run -e "Defdo.TailwindDownload.install()"
   ```

3. **Create Tailwind config** (if not exists):
   ```bash
   mix run -e "Defdo.TailwindPort.Config.ensure_config('./tailwind.config.js')"
   ```

### Development with Watch Mode

```elixir
# Start with watch mode for development
{:ok, _pid} = Defdo.TailwindPort.start_link([
  name: :dev_tailwind,
  opts: [
    "-i", "assets/css/app.css",
    "-o", "priv/static/css/app.css",
    "--watch"
  ]
])

# Wait for readiness
:ok = Defdo.TailwindPort.wait_until_ready(:dev_tailwind)

# Monitor health during development
Task.start(fn ->
  :timer.sleep(5000)
  {:ok, health} = Defdo.TailwindPort.health(:dev_tailwind)
  IO.puts("CSS builds: #{health.css_builds}")
end)
```

### Phoenix Integration

For Phoenix applications, integrate TailwindPort into your application supervision tree:

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # ... other children
      {Defdo.TailwindPort, [
        name: :app_tailwind,
        opts: tailwind_opts()
      ]}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp tailwind_opts do
    if Mix.env() == :dev do
      ["-i", "assets/css/app.css", "-o", "priv/static/css/app.css", "--watch"]
    else
      ["-i", "assets/css/app.css", "-o", "priv/static/css/app.css", "--minify"]
    end
  end
end
```

### Hot Reload Setup

For development with hot reload:

```elixir
# config/dev.exs
config :my_app, MyAppWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/my_app_web/(live|views)/.*(ex)$",
      ~r"lib/my_app_web/templates/.*(eex)$"
    ]
  ]

# The TailwindPort watch mode will automatically rebuild CSS
# when your templates or classes change
```

## Best Practices

### Error Handling

Always handle errors properly:

```elixir
# ✅ Good: Proper error handling
case Defdo.TailwindPort.start_link(opts) do
  {:ok, pid} -> 
    case Defdo.TailwindPort.wait_until_ready() do
      :ok -> {:ok, pid}
      {:error, :timeout} -> {:error, :startup_timeout}
    end
  {:error, reason} -> 
    Logger.error("Failed to start TailwindPort: #{inspect(reason)}")
    {:error, reason}
end

# ❌ Bad: Ignoring errors
Defdo.TailwindPort.start_link(opts)
```

### Configuration Management

```elixir
# ✅ Good: Validate configuration
case Defdo.TailwindPort.Config.validate_config("./tailwind.config.js") do
  :ok -> start_tailwind()
  {:error, reason} -> handle_config_error(reason)
end

# ✅ Good: Ensure config exists
:ok = Defdo.TailwindPort.Config.ensure_config("./tailwind.config.js")

# ✅ Good: Use effective configuration
effective_opts = Defdo.TailwindPort.Config.get_effective_config(
  opts: base_opts,
  config_path: "./tailwind.config.js"
)
```

### Resource Management

```elixir
# ✅ Good: Proper supervision
defmodule MyApp.TailwindSupervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      {Defdo.TailwindPort, [
        name: :main_tailwind,
        opts: ["-i", "assets/css/app.css", "-o", "priv/static/css/app.css"]
      ]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

# ✅ Good: Graceful shutdown
defmodule MyApp.TailwindManager do
  def stop_tailwind(name) do
    case GenServer.whereis(name) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal, 5000)
    end
  end
end
```

### Performance Optimization

```elixir
# ✅ Good: Optimize for environment
defp tailwind_opts do
  base_opts = ["-i", "assets/css/app.css", "-o", "priv/static/css/app.css"]
  
  case Mix.env() do
    :dev -> base_opts ++ ["--watch"]
    :test -> base_opts  # No watch in tests
    :prod -> base_opts ++ ["--minify", "--purge"]
  end
end

# ✅ Good: Use content paths for better performance
# In tailwind.config.js
module.exports = {
  content: [
    "./lib/**/*.{ex,exs,heex}",
    "./assets/js/**/*.js"
  ],
  // ... rest of config
}
```

## Testing

### Unit Testing

```elixir
defmodule MyApp.TailwindTest do
  use ExUnit.Case
  
  describe "TailwindPort integration" do
    test "starts and becomes ready" do
      opts = [
        name: :test_tailwind,
        opts: ["-i", "test/fixtures/input.css", "-o", "test/fixtures/output.css"]
      ]
      
      assert {:ok, pid} = Defdo.TailwindPort.start_link(opts)
      assert :ok = Defdo.TailwindPort.wait_until_ready(:test_tailwind, 5000)
      assert Defdo.TailwindPort.ready?(:test_tailwind)
      
      # Cleanup
      GenServer.stop(pid)
    end
    
    test "health monitoring works" do
      # ... setup ...
      
      assert {:ok, health} = Defdo.TailwindPort.health(:test_tailwind)
      assert health.port_ready
      assert health.port_active
      assert is_integer(health.uptime_seconds)
    end
  end
end
```

### Integration Testing

```elixir
defmodule MyApp.TailwindIntegrationTest do
  use ExUnit.Case
  
  @moduletag :integration
  
  test "full CSS build pipeline" do
    # Setup test files
    input_css = """
    @tailwind base;
    @tailwind components;
    @tailwind utilities;
    
    .custom-class {
      @apply text-blue-500 font-bold;
    }
    """
    
    File.write!("test/tmp/input.css", input_css)
    
    # Start TailwindPort
    opts = [
      name: :integration_test,
      opts: ["-i", "test/tmp/input.css", "-o", "test/tmp/output.css"]
    ]
    
    {:ok, pid} = Defdo.TailwindPort.start_link(opts)
    :ok = Defdo.TailwindPort.wait_until_ready(:integration_test)
    
    # Wait for build to complete
    :timer.sleep(2000)
    
    # Verify output
    assert File.exists?("test/tmp/output.css")
    output = File.read!("test/tmp/output.css")
    assert String.contains?(output, "text-blue-500")
    
    # Cleanup
    GenServer.stop(pid)
    File.rm_rf!("test/tmp")
  end
end
```

### Test Configuration

```elixir
# config/test.exs
config :logger, level: :warn

# Don't start TailwindPort automatically in tests
config :my_app, start_tailwind: false

# Use test-specific paths
config :my_app, :tailwind,
  input: "test/fixtures/input.css",
  output: "test/tmp/output.css"
```

## Deployment

### Production Configuration

```elixir
# config/prod.exs
config :my_app, :tailwind,
  opts: [
    "-i", "assets/css/app.css",
    "-o", "priv/static/css/app.css",
    "--minify",
    "--purge"
  ]

# Ensure binary is available
config :my_app, :tailwind_binary_path, "/app/bin/tailwindcss"
```

### Docker Setup

```dockerfile
# Dockerfile
FROM elixir:1.15-alpine AS builder

# Install build dependencies
RUN apk add --no-cache build-base git nodejs npm

# Install Tailwind CSS binary
RUN mix run -e "Defdo.TailwindDownload.install()"

# ... rest of build steps ...

FROM alpine:3.18 AS runner

# Copy Tailwind binary
COPY --from=builder /app/_build/tailwind_bin/tailwindcss /app/bin/tailwindcss
RUN chmod +x /app/bin/tailwindcss

# ... rest of runtime setup ...
```

### Release Configuration

```elixir
# rel/env.sh.eex
#!/bin/sh

# Ensure Tailwind binary is executable
if [ -f "${RELEASE_ROOT}/bin/tailwindcss" ]; then
  chmod +x "${RELEASE_ROOT}/bin/tailwindcss"
fi

# Set binary path
export TAILWIND_BINARY_PATH="${RELEASE_ROOT}/bin/tailwindcss"
```

### Health Checks

```elixir
# For load balancers and monitoring
defmodule MyApp.HealthCheck do
  def tailwind_health do
    case Defdo.TailwindPort.health(:app_tailwind) do
      {:ok, health} when health.port_ready and health.port_active ->
        {:ok, "healthy"}
      {:ok, health} ->
        {:error, "unhealthy: #{inspect(health)}"}
      {:error, reason} ->
        {:error, "error: #{inspect(reason)}"}
    end
  end
end
```

## Monitoring & Debugging

### Telemetry Integration

TailwindPort emits telemetry events that you can hook into:

```elixir
# lib/my_app/telemetry.ex
defmodule MyApp.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    # Inherit TailwindPort's default pooling KPIs and add any app-specific metrics.
    Defdo.TailwindPort.Metrics.default_metrics() ++
      [
        counter("tailwind_port.port.start"),
        counter("tailwind_port.port.stop")
      ]
  end

  defp periodic_measurements do
    [
      {MyApp.Telemetry, :dispatch_tailwind_health, []}
    ]
  end

  def dispatch_tailwind_health do
    case Defdo.TailwindPort.health(:app_tailwind) do
      {:ok, health} ->
        :telemetry.execute(
          [:tailwind_port, :health],
          health,
          %{port_name: :app_tailwind}
        )
      {:error, _reason} ->
        :ok
    end
  end
end
```

### Logging Configuration

```elixir
# config/config.exs
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :port_name, :tailwind_event]

# In your application
require Logger

case Defdo.TailwindPort.start_link(opts) do
  {:ok, pid} ->
    Logger.info("TailwindPort started", port_name: :app_tailwind)
  {:error, reason} ->
    Logger.error("TailwindPort failed to start", 
      port_name: :app_tailwind, 
      reason: inspect(reason)
    )
end
```

### Debug Mode

```elixir
# Enable debug logging for TailwindPort
config :logger, level: :debug

# Or selectively
Logger.configure(level: :debug)

# Check detailed health information
{:ok, health} = Defdo.TailwindPort.health(:app_tailwind)
IO.inspect(health, label: "TailwindPort Health")

# Monitor port activity
Task.start(fn ->
  Stream.interval(1000)
  |> Enum.each(fn _ ->
    {:ok, health} = Defdo.TailwindPort.health(:app_tailwind)
    IO.puts("Activity: #{health.last_activity_seconds_ago}s ago")
  end)
end)
```

### Common Debug Commands

```elixir
# Check if port is running
GenServer.whereis(:app_tailwind)

# Get current state (for debugging)
:sys.get_state(:app_tailwind)

# Check port readiness
Defdo.TailwindPort.ready?(:app_tailwind)

# Get detailed health metrics
Defdo.TailwindPort.health(:app_tailwind)

# Validate configuration
Defdo.TailwindPort.Config.validate_config("./tailwind.config.js")
```

## Performance Optimization

### CSS Build Optimization

1. **Use specific content paths**:
   ```javascript
   // tailwind.config.js
   module.exports = {
     content: [
       "./lib/**/*.{ex,exs,heex}",  // Only scan relevant files
       "./assets/js/**/*.js"
     ],
     // ...
   }
   ```

2. **Enable JIT mode** (default in Tailwind 3+):
   ```javascript
   module.exports = {
     mode: 'jit',  // Just-in-time compilation
     // ...
   }
   ```

3. **Use purge in production**:
   ```elixir
   defp tailwind_opts do
     base = ["-i", "assets/css/app.css", "-o", "priv/static/css/app.css"]
     
     case Mix.env() do
       :prod -> base ++ ["--minify", "--purge"]
       _ -> base
     end
   end
   ```

### Memory Management

```elixir
# Monitor memory usage
defmodule MyApp.TailwindMonitor do
  def memory_stats do
    case GenServer.whereis(:app_tailwind) do
      nil -> {:error, :not_found}
      pid ->
        info = Process.info(pid, [:memory, :message_queue_len])
        {:ok, info}
    end
  end
end
```

### Process Optimization

```elixir
# Use appropriate restart strategies
defmodule MyApp.TailwindSupervisor do
  use Supervisor

  def init(_opts) do
    children = [
      {Defdo.TailwindPort, [
        name: :app_tailwind,
        opts: tailwind_opts()
      ]}
    ]

    # Use :temporary for development, :permanent for production
    restart_strategy = if Mix.env() == :dev, do: :temporary, else: :permanent
    
    Supervisor.init(children, 
      strategy: :one_for_one,
      restart: restart_strategy
    )
  end
end
```

## Security Considerations

### Binary Verification

TailwindPort automatically verifies downloaded binaries:

```elixir
# Binary verification is automatic, but you can check manually
case Defdo.TailwindDownload.verify_binary() do
  :ok -> IO.puts("Binary is verified")
  {:error, reason} -> IO.puts("Verification failed: #{inspect(reason)}")
end
```

### Input Sanitization

```elixir
# ✅ Good: Validate inputs
defp validate_css_paths(input_path, output_path) do
  with :ok <- validate_path(input_path),
       :ok <- validate_path(output_path) do
    :ok
  else
    {:error, reason} -> {:error, {:invalid_path, reason}}
  end
end

defp validate_path(path) do
  cond do
    not is_binary(path) -> {:error, :not_string}
    String.contains?(path, "..") -> {:error, :path_traversal}
    not String.match?(path, ~r/^[\w\/.\-]+$/) -> {:error, :invalid_characters}
    true -> :ok
  end
end
```

### Secure Configuration

```elixir
# ✅ Good: Secure defaults
defp secure_tailwind_opts(input, output) do
  with :ok <- validate_css_paths(input, output),
       :ok <- ensure_output_directory(output) do
    {
      :ok,
      [
        "-i", Path.expand(input),
        "-o", Path.expand(output),
        "--config", Path.expand("./tailwind.config.js")
      ]
    }
  end
end
```

### Environment Isolation

```elixir
# Isolate environments
config :my_app, :tailwind,
  input: Path.join([Application.app_dir(:my_app), "priv", "css", "app.css"]),
  output: Path.join([Application.app_dir(:my_app), "priv", "static", "css", "app.css"]),
  config: Path.join([Application.app_dir(:my_app), "priv", "tailwind.config.js"])
```

## Contributing

### Development Setup

1. **Fork and clone**:
   ```bash
   git clone https://github.com/your-username/tailwind_port.git
   cd tailwind_port
   ```

2. **Install dependencies**:
   ```bash
   mix deps.get
   mix compile
   ```

3. **Run tests**:
   ```bash
   mix test
   mix test --include integration
   ```

4. **Check code quality**:
   ```bash
   mix format --check-formatted
   mix credo --strict
   mix dialyzer
   ```

### Code Style

- Follow Elixir community conventions
- Use `mix format` for consistent formatting
- Add typespecs for public functions
- Write comprehensive tests
- Update documentation for API changes

### Testing Guidelines

- Write unit tests for all public functions
- Include integration tests for complex workflows
- Test error conditions and edge cases
- Use descriptive test names
- Mock external dependencies appropriately

### Documentation

- Update relevant documentation files
- Include examples for new features
- Add migration notes for breaking changes
- Keep API reference up to date

## Resources

### Documentation

- [Quick Start Guide](./QUICK_START.md) - Get up and running quickly
- [API Reference](./API_REFERENCE.md) - Complete API documentation
- [Examples](./EXAMPLES.md) - Comprehensive usage examples
- [Migration Guide](./MIGRATION_GUIDE.md) - Upgrade between versions
- [Usage Guide](./USAGE.md) - Detailed usage patterns
- [Changelog](../CHANGELOG.md) - Version history and changes

### External Resources

- [TailwindPort on Hex](https://hex.pm/packages/tailwind_port)
- [TailwindPort on HexDocs](https://hexdocs.pm/tailwind_port)
- [GitHub Repository](https://github.com/defdo-dev/tailwind_cli_port)
- [Tailwind CSS Documentation](https://tailwindcss.com/docs)
- [Elixir Ports Documentation](https://hexdocs.pm/elixir/Port.html)

### Community

- [GitHub Issues](https://github.com/defdo-dev/tailwind_cli_port/issues) - Bug reports and feature requests
- [GitHub Discussions](https://github.com/defdo-dev/tailwind_cli_port/discussions) - Community discussions
- [Elixir Forum](https://elixirforum.com/) - General Elixir community

### Related Projects

- [Phoenix](https://phoenixframework.org/) - Web framework for Elixir
- [Tailwind CSS](https://tailwindcss.com/) - Utility-first CSS framework
- [Esbuild](https://hex.pm/packages/esbuild) - JavaScript bundler for Elixir
- [Dart Sass](https://hex.pm/packages/dart_sass) - Sass compiler for Elixir

---

**Happy coding with TailwindPort!** 🎨✨

For questions, issues, or contributions, please visit our [GitHub repository](https://github.com/defdo-dev/tailwind_cli_port).
