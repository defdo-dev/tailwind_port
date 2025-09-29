# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

### Development
- `mix deps.get` - Install dependencies
- `mix compile` - Compile the project
- `mix test` - Run all tests
- `mix test test/path/to/specific_test.exs` - Run a specific test file
- `mix docs` - Generate documentation

### Testing
- Tests are located in the `test/` directory
- Test helper is at `test/test_helper.exs` (configures faster retries and suppresses logs for testing)
- Uses ExUnit testing framework
- `mix test --failed` - Run only previously failed tests
- `mix test test/path/to/specific_test.exs` - Run a specific test file
- Coverage: `mix coveralls` or `mix coveralls.html` for HTML reports

### Code Quality
- `mix format` - Format code according to `.formatter.exs` configuration
- `mix credo` - Static code analysis and style checking
- `mix credo --strict` - Strict mode analysis (all issues resolved)
- `mix dialyzer` - Type checking with Dialyxir
- `mix docs` - Generate HTML documentation from @doc attributes

## Architecture Overview

This is an Elixir library (`tailwind_port`) that provides a GenServer-based interface to the Tailwind CSS CLI. The architecture consists of:

### Core Components

**Main Modules:**
- `Defdo.TailwindPort` (`lib/defdo/tailwind_port.ex`) - High-level API that delegates to Pool for intelligent port pooling
- `Defdo.TailwindPort.Pool` (`lib/defdo/tailwind_port/pool.ex`) - Pooled implementation with resource management and port reuse
- `Defdo.TailwindPort.Standalone` (`lib/defdo/tailwind_port/standalone.ex`) - Legacy single-port GenServer interface
- `Defdo.TailwindDownload` (`lib/defdo/tailwind_download.ex`) - Handles downloading and installing the Tailwind CSS binary for different platforms
- `Defdo.TailwindPort.FS` (`lib/defdo/tailwind_port/fs.ex`) - Manages filesystem operations and temporary directory structures
- `TailwindPort.Application` (`lib/application.ex`) - OTP application that starts a DynamicSupervisor for managing multiple TailwindPort instances

### Key Patterns

**Port Management:**
- Uses Elixir ports to spawn and communicate with external Tailwind CSS CLI processes
- Implements proper cleanup via `:trap_exit` to prevent orphaned OS processes
- Supports both direct binary calls and wrapped commands via shell scripts

**Dynamic Process Management:**
- Uses DynamicSupervisor to allow multiple concurrent TailwindPort instances
- Each instance can be named and managed independently
- Processes are configured as `:transient` restart strategy

**Configuration System:**
- Supports custom Tailwind CSS versions via application config
- Configurable download URLs with placeholder replacement (`$version`, `$target`)
- Platform-specific binary detection and download

**Telemetry Integration:**
- Emits telemetry events for CSS compilation completion (`:tailwind_port, :css, :done`)
- Emits events for other process outputs (`:tailwind_port, :other, :done`)

### File Structure
- `lib/defdo/tailwind_port/` - Core port management logic
- `priv/bin/` - Directory for downloaded Tailwind binaries
- `assets/` - Default location for CSS and config files
- `test/` - Test files following the same directory structure as `lib/`

## Critical: CSS Generation Timing Fix

### Problem Solved
**Fixed critical race condition** where CSS was generated correctly but lost due to port termination timing. The port would exit before CSS could be extracted, resulting in `extract_css_with_fallbacks() => ""`.

### Solution: Immediate CSS Callback System
Implemented a robust callback system that captures CSS **immediately** when generated, before port termination can occur:

```elixir
# Pool registers as CSS listener
register_css_listener(port_info.pid, self(), capture_ref, operation.id)

# Standalone notifies immediately when CSS is generated
notify_css_listeners(listeners, css_output)
```

### Resilience Layers
1. **Primary**: Immediate callback system (eliminates race condition)
2. **Secondary**: File-based extraction (existing)
3. **Tertiary**: Degraded state extraction (existing)
4. **Emergency**: Process dictionary fallback (existing)

### API Compatibility
- **Zero breaking changes** - existing code works unchanged
- **Enhanced metadata**: Results now include optional `capture_method` field
- **Full backward compatibility** with fallback to original methods

### Documentation Reference
See `guides/notes/TIMING_FIX.md` for complete technical details, implementation specifics, and debugging information.

## Recent Improvements

### Enhanced Error Handling & Reliability
- **Comprehensive error handling**: All functions now return proper `{:ok, result}` or `{:error, reason}` tuples
- **Retry logic**: Port creation includes automatic retry with exponential backoff (max 3 retries)
- **Input validation**: All public APIs validate inputs and return descriptive error messages
- **Graceful degradation**: Better handling of download failures, invalid configurations, and process crashes

### Port Synchronization & Monitoring
- **Port readiness detection**: New `ready?/2` and `wait_until_ready/2` functions for reliable port state checking
- **Startup timeouts**: Configurable timeouts to avoid hanging on port startup
- **Process cleanup**: Improved cleanup of orphaned OS processes on termination

### Health Monitoring & Metrics
- **Health endpoint**: `health/1` function provides real-time process metrics
- **Activity tracking**: Monitors port outputs, CSS builds, errors, and uptime
- **Enhanced telemetry**: More detailed telemetry events with metrics

### Security Enhancements
- **Binary verification**: Downloaded binaries are verified for size and platform-appropriate signatures
- **Secure downloads**: Improved HTTPS handling with proper certificate validation
- **Input sanitization**: All user inputs are validated before processing

### Configuration Management
- **Config validation**: `Defdo.TailwindPort.Config` module for validating Tailwind config files
- **Default config creation**: Automatic creation of sensible default configurations
- **Effective config resolution**: Utilities to resolve final configuration from various sources

### Improved Testing
- **Integration tests**: Comprehensive test coverage including error scenarios
- **Synchronization tests**: Tests for port readiness and timeout handling
- **Health monitoring tests**: Verification of metrics and monitoring functionality
- **Configuration tests**: Validation of config parsing and creation
- **Multi-version support**: Tests for both Tailwind CSS v3 and v4 compatibility

## Development Guidelines

### Elixir-Specific Rules
- **Never** use map access syntax (`my_struct[:field]`) on structs - use direct field access (`my_struct.field`) instead
- **Never** use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should end with `?` and not start with `is_` (e.g., `ready?/2` not `is_ready/2`)
- When rebinding variables in block expressions (`if`, `case`, `cond`), bind the result of the entire expression:
  ```elixir
  # GOOD
  socket = if connected?(socket), do: assign(socket, :val, val), else: socket

  # BAD - rebinding inside the block
  if connected?(socket) do
    socket = assign(socket, :val, val)  # This doesn't work as expected
  end
  ```

### Module Organization
- **Never** nest multiple modules in the same file (causes cyclic dependencies)
- Each module should have its own file following the standard `lib/` directory structure
- Support modules are organized under `lib/defdo/tailwind_port/` namespace

### OTP Patterns
- Uses `DynamicSupervisor` for managing multiple TailwindPort instances dynamically
- Processes are configured as `:transient` restart strategy
- Proper supervision tree with `TailwindPort.Application` as root supervisor

### Code Quality Standards
- All code must pass `mix credo --strict` (currently compliant)
- Use `Enum.empty?/1` instead of `length(list) == 0` for performance
- Extract complex functions into smaller, focused helper functions
- Prefer `if/else` over single-condition `cond` statements
- Use implicit `try` instead of explicit `try do...catch` blocks

## New API Functions

### Synchronization
- `TailwindPort.ready?(name, timeout)` - Check if port is ready
- `TailwindPort.wait_until_ready(name, timeout)` - Wait for port readiness

### Health Monitoring
- `TailwindPort.health(name)` - Get health metrics and status

### Configuration
- `Config.validate_config(config_path)` - Validate Tailwind config files
- `Config.ensure_config(config_path)` - Create default config if needed
- `Config.get_effective_config(opts)` - Resolve effective configuration

### Enhanced Pool API
- `Pool.compile(opts, content)` - Compile with immediate CSS capture
- `Pool.batch_compile(operations)` - Batch multiple operations
- `Pool.get_stats()` - Get comprehensive pool statistics and KPIs

The library is designed to integrate Tailwind CSS build processes into Elixir applications by wrapping the CLI in a supervised GenServer process with enterprise-grade reliability, monitoring, and observability features.