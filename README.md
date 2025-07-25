# TailwindPort

A robust, production-ready Elixir library for integrating Tailwind CSS CLI with comprehensive error handling, health monitoring, and synchronization features.

The `Defdo.TailwindPort` module provides a reliable interface to interact with the Tailwind CSS CLI through Elixir ports, enabling seamless integration of Tailwind CSS build processes into Elixir applications with enterprise-grade reliability and monitoring.

## Installation

If [available in Hex](https://defdo.hexdocs.pm/tailwind_port), the package can be installed
by adding `tailwind_port` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tailwind_port, "~> 0.2.0", organization: "defdo"}
  ]
end
```

Then, run:

```sh
mix deps.get
```

## Features

### 🚀 **Production-Ready Reliability**
- **Comprehensive error handling** with proper `{:ok, result}` or `{:error, reason}` return types
- **Automatic retry logic** with exponential backoff for port creation failures
- **Input validation** for all public APIs with descriptive error messages
- **Graceful process cleanup** to prevent orphaned OS processes

### 🔄 **Port Synchronization**
- **Port readiness detection** - `ready?/2` to check if port is operational
- **Synchronous startup** - `wait_until_ready/2` for reliable port initialization
- **Configurable timeouts** to prevent hanging processes
- **Race condition elimination** with proper synchronization mechanisms

### 📊 **Health Monitoring & Metrics**
- **Real-time health monitoring** - `health/1` provides process metrics
- **Activity tracking** - monitors port outputs, CSS builds, errors, and uptime
- **Enhanced telemetry** with detailed metrics and structured events
- **Process lifecycle visibility** for better observability

### 🔒 **Security & Validation**
- **Binary verification** - downloaded binaries verified for size and platform signatures
- **Secure HTTPS downloads** with proper certificate validation
- **Input sanitization** - all user inputs validated and sanitized
- **Platform-specific signature checking** (PE, Mach-O, ELF)

### ⚙️ **Configuration Management**
- **Config validation** - validate Tailwind configuration files
- **Default config creation** - automatic setup of sensible defaults
- **Effective config resolution** - utilities to resolve configuration from various sources
- **Syntax validation** for Tailwind configuration structure

## Usage

### Basic Usage

```elixir
# Start a TailwindPort process
{:ok, pid} = Defdo.TailwindPort.start_link([
  opts: ["-i", "./assets/css/app.css", 
         "--content", "./priv/static/html/**/*.{html,js}", 
         "-c", "./assets/tailwind.config.js", 
         "--watch"]
])

# Wait for the port to be ready (replaces unreliable Process.sleep)
:ok = Defdo.TailwindPort.wait_until_ready()

# Check if port is ready
if Defdo.TailwindPort.ready?() do
  IO.puts("Port is ready for CSS processing!")
end
```

### Health Monitoring

```elixir
# Get comprehensive health metrics
health = Defdo.TailwindPort.health()

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

### Configuration Management

```elixir
alias Defdo.TailwindPort.Config

# Ensure config exists (creates default if missing)
:ok = Config.ensure_config("./tailwind.config.js")

# Validate existing config
case Config.validate_config("./tailwind.config.js") do
  :ok -> IO.puts("Config is valid!")
  {:error, reason} -> IO.puts("Config error: #{inspect(reason)}")
end

# Get effective configuration
config = Config.get_effective_config(opts: ["-w", "-m"])
# %{watch_mode: true, minify: true, ...}
```

### Error Handling

```elixir
# All functions now return proper error tuples
case Defdo.TailwindPort.new(:my_port, cmd: "/invalid/path") do
  {:ok, state} -> 
    IO.puts("Port created successfully!")
  {:error, :max_retries_exceeded} -> 
    IO.puts("Failed to create port after retries")
  {:error, reason} -> 
    IO.puts("Error: #{inspect(reason)}")
end
```


## Documentation

Comprehensive documentation is available to help you get started and make the most of TailwindPort:

### 📚 **Getting Started**
- **[Quick Start Guide](guides/QUICK_START.md)** - Get up and running in minutes
- **[Developer Guide](guides/DEVELOPER_GUIDE.md)** - Comprehensive guide for developers
- **[Usage Guide](guides/USAGE.md)** - Detailed usage patterns and workflows

### 📖 **Reference**
- **[API Reference](guides/API_REFERENCE.md)** - Complete API documentation
- **[Examples](guides/EXAMPLES.md)** - Real-world usage examples
- **[Migration Guide](guides/MIGRATION_GUIDE.md)** - Upgrade between versions

### 📋 **Project Information**
- **[Changelog](CHANGELOG.md)** - Version history and changes
- **[Architecture Overview](CLAUDE.md)** - Technical architecture details

## Quick Links

- 🏠 **[Homepage](https://github.com/defdo-dev/tailwind_cli_port)**
- 📦 **[Hex Package](https://hex.pm/packages/tailwind_port)**
- 📚 **[HexDocs](https://hexdocs.pm/tailwind_port)**
- 🐛 **[Issues](https://github.com/defdo-dev/tailwind_cli_port/issues)**
- 💬 **[Discussions](https://github.com/defdo-dev/tailwind_cli_port/discussions)**

## Contributing

We welcome contributions! Please see our [Developer Guide](guides/DEVELOPER_GUIDE.md) for information on:

- Setting up the development environment
- Running tests
- Code style guidelines
- Submitting pull requests

## Support

If you need help:

1. Check the documentation first
2. Search [existing issues](https://github.com/defdo-dev/tailwind_cli_port/issues)
3. Create a [new issue](https://github.com/defdo-dev/tailwind_cli_port/issues/new) if needed
4. Join the [discussions](https://github.com/defdo-dev/tailwind_cli_port/discussions)

## License

This project is licensed under the Apache License, Version 2.0. See the [LICENSE](LICENSE) file for details.