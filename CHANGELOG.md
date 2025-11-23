# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.3] - 2025-11-23

### 🚨 Major Bug Fixes
- **Tailwind CLI Version Compatibility**: Fixed critical port creation failures when using TailwindCSS v4.x.x
  - **Root Cause**: `build_start_args/1` was passing v3-specific CLI options (`--content`, `--config`, `--postcss`) to v4, which rejects them
  - **Solution**: Implemented `Defdo.TailwindPort.CliCompatibility` module with automatic version detection and option filtering
  - **Impact**: Eliminates "invalid option in list" errors and enables seamless v3/v4 coexistence

- **Keyword Processing Bug**: Fixed `FunctionClauseError` in `Keyword.do_reject/2` due to type mismatch
  - **Root Cause**: Passing string lists to functions expecting keyword lists
  - **Solution**: Clean refactor with proper type handling and conversion
  - **Impact**: Restores all pool functionality and eliminates crashes

### ✨ Major Architecture Improvements
- **New CLI Compatibility Module**: `Defdo.TailwindPort.CliCompatibility`
  - Automatic detection of TailwindCSS version from configuration
  - Version-aware filtering of CLI arguments (v3-only vs v4-only options)
  - Helper functions for option validation and migration
  - Complete backward compatibility while supporting v4 new features

- **Enhanced PortManager Support**: Added TailwindCSS v4 CLI options
  - `--cwd`: Working directory specification for v4 auto-content-detection
  - `--optimize`: Performance optimization without minification
  - `--map`: Source map generation support
  - Maintains full backward compatibility with v3 options

### 🔧 Code Quality & Performance
- **Pool.ex Refactor**: Complete cleanup of `build_start_args/1` function
  - **Before**: 40+ lines with redundant variable extraction and complex conversions
  - **After**: 25 lines with clear extraction → filtering → conversion flow
  - **Benefits**: -37.5% code reduction, improved readability, enhanced maintainability
  - Eliminates redundant keyword list reconstruction and unnecessary temporary variables

- **Telemetry Performance Fix**: Resolved telemetry handler performance warning
  - **Root Cause**: Using local function capture `&handle_default_event/4` which causes runtime performance penalty
  - **Solution**: Changed to module capture `&__MODULE__.handle_default_event/4` and made function public
  - **Impact**: Eliminates performance warning and improves telemetry handler efficiency

- **Enhanced Telemetry**: Increased slow compilation threshold from 5s to 15s
  - **Rationale**: TailwindCSS v4+ with plugins (DaisyUI) legitimately takes 1-3s for complex builds
  - **Impact**: Reduces false positive alerts while maintaining meaningful performance monitoring

### 📚 Documentation & Developer Experience
- **Comprehensive v4 Compatibility Guide**: `guides/TAILWIND_VERSION_COMPATIBILITY.md`
  - Complete CLI option matrix for v3 vs v4
  - Migration strategies and best practices
  - Troubleshooting guide for common version conflicts
  - Real-world examples and configuration patterns

- **Enhanced Testing Suite**: Added 21 new CLI compatibility tests
  - Version detection accuracy across scenarios
  - Option filtering validation for both versions
  - Edge case handling for malformed inputs
  - Integration tests maintaining full backward compatibility

### 🔄 API Changes (Non-Breaking)
- **TailwindPort.compile/2**: Enhanced to automatically filter incompatible options
- **Pool Telemetry**: New `slow_compilation` threshold configuration
- **CLI Filtering**: New `Defdo.TailwindPort.CliCompatibility` public API for advanced use cases

### 🧪 Testing & Reliability
- **100% Test Suite Pass Rate**: All 44 TailwindPort tests + 21 CLI compatibility tests
- **Theme Project Integration**: Verified end-to-end compilation with v4.1.16
- **Performance Validation**: Confirmed <1s compilation times for typical usage
- **Memory Efficiency**: Eliminated redundant object allocations in argument processing

### 📊 Version Compatibility Matrix
| TailwindCSS Version | Status | Supported Options |
|---------------------|--------|------------------|
| 3.x.x | ✅ Fully Supported | All legacy options |
| 4.x.x | ✅ Fully Supported | v4 new options + auto-filtering |
| Mixed Environments | ✅ Supported | Automatic detection and adaptation |

### 🚀 Performance Impact
- **Zero Breaking Changes**: All existing code continues to work unchanged
- **Improved Startup Time**: Faster pool initialization with cleaner argument processing
- **Reduced Memory Usage**: Eliminated redundant temporary keyword list construction
- **Enhanced Error Recovery**: Better handling of version mismatches with graceful degradation

## [0.3.2] - 2024-09-28

### 🔧 Critical Fixes
- **CSS Generation Timing Fix**: Resolved critical race condition where CSS was generated correctly but lost due to port termination timing
  - **Pool.ex**: Implemented `run_tailwind_build_with_immediate_capture/4` with CSS listener registration
  - **Pool.ex**: Added comprehensive `extract_css_with_fallbacks/2` with 4-layer fallback strategy
  - **Pool.ex**: Enhanced fallback methods: immediate → file-based → process state → port inspection → force regeneration
  - **Standalone.ex**: Added CSS listener management with `css_listeners` state and immediate notification system
  - **Standalone.ex**: Enhanced CSS storage: `latest_output`, `last_css_output`, `preserved_css` + process dictionary
  - **Standalone.ex**: Implemented ping/force regeneration handlers for degraded scenarios
  - Eliminates race conditions where `extract_css_with_fallbacks() => ""` despite successful CSS generation
  - Zero breaking changes - fully backward compatible API
  - Enhanced observability with `capture_method` metadata (`:immediate`, `:file_based`, `:degraded_fallback`)

### ✨ Code Quality Improvements
- **ConfigManager.ex**: Code formatting improvements and trailing whitespace cleanup
- **Pool.ex**: Major refactoring for better maintainability and reliability
  - Extracted complex nested functions into focused helper functions (`process_operation_group/4`, `handle_file_read_result/3`)
  - Added comprehensive logging and debugging capabilities
  - Enhanced error handling and recovery mechanisms
- **Standalone.ex**: Enhanced robustness and CSS handling capabilities
  - Improved code formatting and documentation examples
  - Added multiple CSS storage mechanisms for reliability
  - Enhanced message handling for immediate CSS capture
- Fixed all Credo strict compliance issues:
  - Converted explicit try statements to implicit try
  - Reduced function cyclomatic complexity by extracting helper functions
  - Fixed function nesting depth issues with focused helper functions
  - Replaced inefficient `cond` statements with `if/else` where appropriate
  - Optimized expensive `length/1` operations to use `Enum.empty?/1`

### 🧪 Enhanced Testing
- Fixed integration tests to support both Tailwind CSS v3 and v4 compatibility
- Split complex integration test into smaller, focused helper functions
- Added explicit test cases for both Tailwind v3 and v4 syntax
- Improved test reliability with automatic fallback mechanisms
- All 390 tests continue to pass with enhanced test structure

### 🔧 Technical Implementation Details

#### Pool.ex - Advanced CSS Capture System
- `run_tailwind_build_with_immediate_capture/4`: New primary capture method with listener registration
- `fallback_to_file_based_capture/3`: Robust fallback when immediate capture fails
- `extract_css_with_fallbacks/2`: Multi-strategy CSS extraction with 4 fallback layers
- `extract_css_alternative_methods/2`: Process state and port inspection methods
- `force_css_regeneration/2`: Emergency CSS regeneration for degraded ports
- Enhanced `fetch_latest_output/1`: Multiple CSS source checking (`latest_output`, `preserved_css`, `last_css_output`)

#### Standalone.ex - Enhanced CSS Management
- New state fields: `last_css_output`, `preserved_css`, `css_listeners`
- Immediate CSS notification via `notify_css_listeners/2`
- Process dictionary CSS storage for emergency fallback
- Enhanced port data handling with multi-location CSS persistence
- New message handlers: `:ping_for_css`, `:force_regenerate`, `:register_css_listener`, `:trigger_css_generation`
- `get_available_css/1`: Intelligent CSS source selection

#### ConfigManager.ex - Code Quality
- Trailing whitespace cleanup across documentation examples
- Improved code formatting consistency

### 📚 Documentation
- Added comprehensive timing fix documentation in `guides/notes/TIMING_FIX.md`
- Updated CLAUDE.md with latest architectural improvements
- Enhanced code readability and maintainability

## [0.3.1] - 2024-09-21

### 🔧 Maintenance
- Dependency updates and build improvements

## [0.3.0] - 2024-02-28

### 🚀 Breaking Changes
- The pooled Tailwind manager is now the primary `Defdo.TailwindPort` API
- The original single-port GenServer lives on as `Defdo.TailwindPort.Standalone`
- Telemetry prefixes migrate from `tailwind_port_optimized` to `tailwind_port_pool`

### ✨ Added
- `Defdo.TailwindPort.Pool` with real pooled compilation, filesystem wiring, and graceful degradation
- `Defdo.TailwindPort.PoolTelemetry` and `Defdo.TailwindPort.Metrics` for ready-to-export KPI gauges
- Real Tailwind integration test that validates HTML→CSS reuse against the CLI

### 🔄 Updated
- README and guides now showcase the pooled API while documenting `Standalone`
- All tests and examples use the new naming (`Pool`/`Standalone`)
- Added `telemetry_metrics` dependency for easy Prometheus/StatsD integration


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
