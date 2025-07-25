# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-01-27

### ⚡ Major Improvements

This release represents a significant overhaul of the TailwindPort library, transforming it from a basic implementation into a robust, production-ready solution.

### 🚀 Added

#### Port Synchronization & Reliability
- **Port readiness detection**: New `ready?/2` function to check if port is operational
- **Synchronous startup**: New `wait_until_ready/2` function for reliable port initialization
- **Startup timeouts**: Configurable timeouts to prevent hanging on port startup
- **Retry logic**: Automatic retry with exponential backoff for port creation failures (max 3 retries)

#### Health Monitoring & Metrics
- **Health endpoint**: New `health/1` function providing real-time process metrics
- **Activity tracking**: Monitors port outputs, CSS builds, errors, and uptime
- **Enhanced telemetry**: More detailed telemetry events with comprehensive metrics
- **Process lifecycle tracking**: Better visibility into port state and performance

#### Security & Validation  
- **Binary verification**: Downloaded binaries are verified for size and platform-appropriate signatures (PE, Mach-O, ELF)
- **Input validation**: Comprehensive validation for all public API parameters
- **Secure downloads**: Improved HTTPS handling with proper certificate validation
- **Error sanitization**: All user inputs are validated and sanitized before processing

#### Configuration Management
- **Config validation**: New `Defdo.TailwindPort.Config` module for validating Tailwind config files
- **Default config creation**: Automatic creation of sensible default configurations
- **Effective config resolution**: Utilities to resolve final configuration from various sources
- **Config structure validation**: Basic validation of Tailwind configuration syntax and structure

#### Developer Experience
- **Type specifications**: Added `@spec` annotations to all public functions
- **Comprehensive error handling**: All functions now return proper `{:ok, result}` or `{:error, reason}` tuples
- **Better error messages**: Descriptive error messages for easier debugging
- **Enhanced logging**: Structured logging with appropriate log levels

### 🧪 Testing
- **Expanded test coverage**: Increased from 6 to 23 tests (284% increase)
- **Integration tests**: Comprehensive test coverage including error scenarios
- **Synchronization tests**: Tests for port readiness and timeout handling  
- **Health monitoring tests**: Verification of metrics and monitoring functionality
- **Configuration tests**: Validation of config parsing and creation
- **Download tests**: Tests for binary verification and download error handling

### 🔧 Changed

#### Breaking Changes
- **Return types**: `TailwindPort.new/2` now returns `{:ok, result}` or `{:error, reason}` instead of just the result
- **Download functions**: `TailwindDownload.download/2` and `install/2` now return `:ok` or `{:error, reason}`
- **Input validation**: Functions now validate inputs and return `{:error, :invalid_*}` for invalid parameters
- **State structure**: Internal state includes additional fields (`port_ready`, `health`, etc.)

#### Improvements
- **Process cleanup**: Better cleanup of orphaned OS processes on termination
- **Download reliability**: Enhanced error handling and validation in download process
- **Port management**: More robust port creation and monitoring
- **Memory efficiency**: Optimized state management and reduced memory footprint

### 🐛 Fixed
- **Race conditions**: Eliminated timing-based race conditions in tests using proper synchronization
- **Process leaks**: Fixed potential orphaned OS process issues
- **Download failures**: Better handling of network errors and proxy configurations
- **Port monitoring**: More reliable port monitoring and lifecycle management
- **Error propagation**: Proper error propagation throughout the system

### 📚 Documentation
- **Updated CLAUDE.md**: Comprehensive documentation of all new features and architectural changes
- **API documentation**: Complete documentation for all new functions and modules
- **Migration guide**: Clear guidance for upgrading from v0.1.x
- **Examples**: Practical examples of new functionality usage

### 🏗️ Internal
- **Code organization**: Better separation of concerns with new modules
- **Error handling patterns**: Consistent error handling patterns throughout
- **Logging standards**: Standardized logging with structured messages
- **Test organization**: Better organized test suite with clear separation of concerns

---

## [0.1.5] - Previous Release

### Added
- Basic TailwindPort functionality
- Download capability for Tailwind binaries
- GenServer-based port management
- Dynamic supervisor for multiple instances
- Telemetry integration
- Basic filesystem utilities

### Features
- Port-based communication with Tailwind CSS CLI
- Binary downloading for different platforms
- Configuration file handling
- Basic error handling
- Process supervision

---

## Migration Guide from 0.1.x to 0.2.0

### Update Function Calls
```elixir
# Before (0.1.x)
result = TailwindPort.new(name, args)

# After (0.2.0)
{:ok, result} = TailwindPort.new(name, args)
# or with error handling
case TailwindPort.new(name, args) do
  {:ok, result} -> result
  {:error, reason} -> handle_error(reason)
end
```

### Replace Timing-Based Code
```elixir
# Before (0.1.x)
{:ok, pid} = TailwindPort.start_link(opts: opts)
Process.sleep(3000)  # Unreliable!

# After (0.2.0)
{:ok, pid} = TailwindPort.start_link(opts: opts)
:ok = TailwindPort.wait_until_ready(TailwindPort, 5000)  # Reliable!
```

### Add Error Handling
```elixir
# Before (0.1.x) - could crash
TailwindPort.start_link(name: "invalid", opts: "invalid")

# After (0.2.0) - graceful error handling
case TailwindPort.start_link(name: "invalid", opts: "invalid") do
  {:ok, pid} -> pid
  {:error, reason} -> Logger.error("Startup failed: #{inspect(reason)}")
end
```

### Use New Monitoring Features
```elixir
# New in 0.2.0 - Health monitoring
health = TailwindPort.health()
Logger.info("Port uptime: #{health.uptime_seconds}s, CSS builds: #{health.css_builds}")

# New in 0.2.0 - Port readiness
if TailwindPort.ready?() do
  # Port is ready for work
end

# New in 0.2.0 - Configuration management
:ok = Config.ensure_config("./tailwind.config.js")
config = Config.get_effective_config(opts)
```