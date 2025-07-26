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
- Test helper is at `test/test_helper.exs`
- Uses ExUnit testing framework

## Architecture Overview

This is an Elixir library (`tailwind_port`) that provides a GenServer-based interface to the Tailwind CSS CLI. The architecture consists of:

### Core Components

**Main Modules:**
- `Defdo.TailwindPort` (`lib/defdo/tailwind_port.ex`) - Main GenServer that manages Elixir ports to communicate with the Tailwind CSS CLI binary
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

The library is designed to integrate Tailwind CSS build processes into Elixir applications by wrapping the CLI in a supervised GenServer process.

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

### Enhanced Downloads
- Binary verification during download
- Better error reporting and validation
- Improved proxy and certificate handling