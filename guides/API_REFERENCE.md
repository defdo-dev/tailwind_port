# TailwindPort API Reference

This document provides comprehensive API documentation for all TailwindPort modules and functions.

## Table of Contents

- [Defdo.TailwindPort](#defdotailwindport)
- [Defdo.TailwindDownload](#defdotailwinddownload)
- [Defdo.TailwindPort.Config](#defdotailwindportconfig)
- [Defdo.TailwindPort.FS](#defdotailwindportfs)
- [TailwindPort.Application](#tailwindportapplication)
- [Error Types](#error-types)
- [Telemetry Events](#telemetry-events)

## Defdo.TailwindPort

The main GenServer module for managing Tailwind CSS CLI processes.

### Functions

#### start_link/1

Starts a new TailwindPort GenServer process.

```elixir
@spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
```

**Parameters:**
- `opts` - Keyword list of options
  - `:name` - Process name (atom, default: `TailwindPort`)
  - `:opts` - List of Tailwind CLI arguments
  - `:cmd` - Custom Tailwind binary path (optional)
  - `:timeout` - Startup timeout in milliseconds (default: 10_000)

**Returns:**
- `{:ok, pid()}` - Success with process PID
- `{:error, reason}` - Failure with error reason

**Examples:**
```elixir
# Basic usage
{:ok, pid} = Defdo.TailwindPort.start_link([
  opts: ["-i", "input.css", "-o", "output.css"]
])

# Named process
{:ok, pid} = Defdo.TailwindPort.start_link([
  name: :my_tailwind,
  opts: ["-i", "input.css", "-o", "output.css", "--watch"]
])

# Custom binary
{:ok, pid} = Defdo.TailwindPort.start_link([
  cmd: "/custom/path/to/tailwindcss",
  opts: ["-i", "input.css", "-o", "output.css"]
])
```

#### new/2

Creates a new TailwindPort state without starting a GenServer.

```elixir
@spec new(atom(), keyword()) :: {:ok, map()} | {:error, term()}
```

**Parameters:**
- `name` - Process name (atom)
- `opts` - Keyword list of options (same as `start_link/1`)

**Returns:**
- `{:ok, state}` - Success with initial state
- `{:error, reason}` - Failure with error reason

#### ready?/2

Checks if a TailwindPort process is ready to handle requests.

```elixir
@spec ready?(atom(), non_neg_integer()) :: boolean()
```

**Parameters:**
- `name` - Process name (default: `TailwindPort`)
- `timeout` - Timeout in milliseconds (default: 5_000)

**Returns:**
- `true` - Port is ready
- `false` - Port is not ready or doesn't exist

**Examples:**
```elixir
# Check default process
if Defdo.TailwindPort.Standalone.ready?() do
  IO.puts("Ready to process CSS!")
end

# Check named process with custom timeout
if Defdo.TailwindPort.Standalone.ready?(:my_tailwind, 10_000) do
  IO.puts("My Tailwind process is ready!")
end
```

#### wait_until_ready/2

Waits until a TailwindPort process is ready, with timeout.

```elixir
@spec wait_until_ready(atom(), non_neg_integer()) :: :ok | {:error, :timeout}
```

**Parameters:**
- `name` - Process name (default: `TailwindPort`)
- `timeout` - Maximum wait time in milliseconds (default: 10_000)

**Returns:**
- `:ok` - Port became ready within timeout
- `{:error, :timeout}` - Timeout exceeded

**Examples:**
```elixir
# Wait for default process
case Defdo.TailwindPort.Standalone.wait_until_ready() do
  :ok -> IO.puts("Ready!")
  {:error, :timeout} -> IO.puts("Timed out")
end

# Wait for named process with custom timeout
:ok = Defdo.TailwindPort.Standalone.wait_until_ready(:my_tailwind, 30_000)
```

#### health/1

Retrieves health metrics and status information for a TailwindPort process.

```elixir
@spec health(atom()) :: {:ok, map()} | {:error, term()}
```

**Parameters:**
- `name` - Process name (default: `TailwindPort`)

**Returns:**
- `{:ok, health_map}` - Success with health information
- `{:error, reason}` - Process not found or error

**Health Map Structure:**
```elixir
%{
  created_at: integer(),              # Process creation timestamp (nanoseconds)
  last_activity: integer(),           # Last activity timestamp (nanoseconds)
  total_outputs: non_neg_integer(),   # Total port outputs received
  css_builds: non_neg_integer(),      # Number of CSS builds completed
  errors: non_neg_integer(),          # Number of errors encountered
  uptime_seconds: float(),            # Process uptime in seconds
  port_active: boolean(),             # Whether port is active
  port_ready: boolean(),              # Whether port is ready
  last_activity_seconds_ago: float()  # Seconds since last activity
}
```

**Examples:**
```elixir
# Get health for default process
{:ok, health} = Defdo.TailwindPort.Standalone.health()
IO.puts("Uptime: #{health.uptime_seconds}s")
IO.puts("CSS builds: #{health.css_builds}")
IO.puts("Errors: #{health.errors}")

# Get health for named process
case Defdo.TailwindPort.Standalone.health(:my_tailwind) do
  {:ok, health} -> 
    IO.inspect(health)
  {:error, :not_found} -> 
    IO.puts("Process not found")
end
```

#### terminate/1

Gracefully terminates a TailwindPort process.

```elixir
@spec terminate(atom()) :: :ok
```

**Parameters:**
- `name` - Process name (default: `TailwindPort`)

**Returns:**
- `:ok` - Always returns `:ok`

**Examples:**
```elixir
# Terminate default process
Defdo.TailwindPort.terminate()

# Terminate named process
Defdo.TailwindPort.terminate(:my_tailwind)
```

## Defdo.TailwindDownload

Handles downloading and installing Tailwind CSS binaries.

### Functions

#### install/2

Downloads and installs the Tailwind CSS binary for the current platform.

```elixir
@spec install(keyword(), keyword()) :: :ok | {:error, term()}
```

**Parameters:**
- `opts` - Download options (optional)
  - `:version` - Tailwind CSS version (default: from config)
  - `:target` - Target platform (default: auto-detected)
  - `:force` - Force re-download (default: false)
- `config` - Configuration options (optional)

**Returns:**
- `:ok` - Installation successful
- `{:error, reason}` - Installation failed

**Examples:**
```elixir
# Install with defaults
:ok = Defdo.TailwindDownload.install()

# Install specific version
:ok = Defdo.TailwindDownload.install(version: "3.4.0")

# Force reinstall
:ok = Defdo.TailwindDownload.install(force: true)
```

#### download/2

Downloads the Tailwind CSS binary without installing.

```elixir
@spec download(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
```

**Parameters:**
- `url` - Download URL
- `opts` - Download options
  - `:timeout` - Download timeout (default: 30_000)
  - `:verify` - Verify download (default: true)

**Returns:**
- `{:ok, binary_data}` - Download successful
- `{:error, reason}` - Download failed

#### get_target/0

Detects the current platform target for binary selection.

```elixir
@spec get_target() :: binary()
```

**Returns:**
- Platform string (e.g., "linux-x64", "macos-arm64", "windows-x64")

**Examples:**
```elixir
target = Defdo.TailwindDownload.get_target()
IO.puts("Platform: #{target}")
# Output: "Platform: macos-arm64"
```

#### binary_path/0

Returns the path to the installed Tailwind CSS binary.

```elixir
@spec binary_path() :: binary()
```

**Returns:**
- Absolute path to the binary

**Examples:**
```elixir
path = Defdo.TailwindDownload.binary_path()
IO.puts("Binary at: #{path}")
# Output: "Binary at: /path/to/priv/bin/tailwindcss"
```

## Defdo.TailwindPort.Config

Utilities for managing Tailwind CSS configuration files.

### Functions

#### validate_config/1

Validates a Tailwind CSS configuration file.

```elixir
@spec validate_config(binary()) :: :ok | {:error, term()}
```

**Parameters:**
- `config_path` - Path to the configuration file

**Returns:**
- `:ok` - Configuration is valid
- `{:error, reason}` - Configuration is invalid or file not found

**Examples:**
```elixir
# Validate existing config
case Defdo.TailwindPort.Config.validate_config("./tailwind.config.js") do
  :ok -> IO.puts("Config is valid!")
  {:error, :file_not_found} -> IO.puts("Config file not found")
  {:error, reason} -> IO.puts("Invalid config: #{inspect(reason)}")
end
```

#### ensure_config/1

Ensures a Tailwind CSS configuration file exists, creating a default one if needed.

```elixir
@spec ensure_config(binary()) :: :ok | {:error, term()}
```

**Parameters:**
- `config_path` - Path where the configuration should exist

**Returns:**
- `:ok` - Configuration exists or was created
- `{:error, reason}` - Failed to create configuration

**Examples:**
```elixir
# Ensure config exists
:ok = Defdo.TailwindPort.Config.ensure_config("./tailwind.config.js")

# Custom path
:ok = Defdo.TailwindPort.Config.ensure_config("./assets/tailwind.config.js")
```

#### get_effective_config/1

Resolves the effective configuration from various sources.

```elixir
@spec get_effective_config(keyword()) :: map()
```

**Parameters:**
- `opts` - Options that may affect configuration

**Returns:**
- Map containing the resolved configuration

**Examples:**
```elixir
# Get effective config
config = Defdo.TailwindPort.Config.get_effective_config([
  config_file: "./tailwind.config.js",
  watch: true,
  minify: false
])

IO.inspect(config)
# %{watch_mode: true, minify: false, content_paths: [...], ...}
```

#### create_default_config/1

Creates a default Tailwind CSS configuration file.

```elixir
@spec create_default_config(binary()) :: :ok | {:error, term()}
```

**Parameters:**
- `config_path` - Path where the configuration should be created

**Returns:**
- `:ok` - Configuration created successfully
- `{:error, reason}` - Failed to create configuration

## Defdo.TailwindPort.FS

Filesystem utilities for TailwindPort operations.

### Functions

#### ensure_directory/1

Ensures a directory exists, creating it if necessary.

```elixir
@spec ensure_directory(binary()) :: :ok | {:error, term()}
```

#### temp_directory/0

Returns a temporary directory path for TailwindPort operations.

```elixir
@spec temp_directory() :: binary()
```

#### clean_temp_files/0

Cleans up temporary files created by TailwindPort.

```elixir
@spec clean_temp_files() :: :ok
```

## TailwindPort.Application

OTP Application module that manages the TailwindPort supervisor tree.

### Functions

#### start/2

Starts the TailwindPort application.

```elixir
@spec start(term(), term()) :: {:ok, pid()} | {:error, term()}
```

#### stop/1

Stops the TailwindPort application.

```elixir
@spec stop(term()) :: :ok
```

## Error Types

TailwindPort uses consistent error tuples throughout the API:

### Common Error Reasons

- `:not_found` - Process or resource not found
- `:timeout` - Operation timed out
- `:max_retries_exceeded` - Maximum retry attempts exceeded
- `:invalid_args` - Invalid arguments provided
- `:invalid_config` - Invalid configuration
- `:file_not_found` - Required file not found
- `:permission_denied` - Insufficient permissions
- `:network_error` - Network-related error
- `:binary_not_found` - Tailwind binary not found
- `:port_creation_failed` - Failed to create Elixir port
- `:download_failed` - Binary download failed
- `:verification_failed` - Binary verification failed

### Error Examples

```elixir
# Process not found
{:error, :not_found} = Defdo.TailwindPort.Standalone.health(:nonexistent)

# Timeout
{:error, :timeout} = Defdo.TailwindPort.Standalone.wait_until_ready(:slow_process, 1000)

# Invalid arguments
{:error, :invalid_args} = Defdo.TailwindPort.start_link(opts: "invalid")

# File not found
{:error, :file_not_found} = Defdo.TailwindPort.Config.validate_config("/nonexistent/config.js")
```

## Telemetry Events

TailwindPort emits telemetry events for monitoring and observability:

### Event Types

#### `[:tailwind_port, :css, :done]`

Emitted when a CSS build completes successfully.

**Measurements:**
- `duration` - Build duration in nanoseconds

**Metadata:**
- `port_name` - Name of the TailwindPort process
- `timestamp` - Event timestamp
- `output_size` - Size of generated CSS (if available)

#### `[:tailwind_port, :other, :done]`

Emitted for other port outputs (non-CSS builds).

**Measurements:**
- `duration` - Processing duration in nanoseconds

**Metadata:**
- `port_name` - Name of the TailwindPort process
- `timestamp` - Event timestamp
- `output_type` - Type of output

#### `[:tailwind_port, :error, :occurred]`

Emitted when an error occurs.

**Measurements:**
- `count` - Error count (always 1)

**Metadata:**
- `port_name` - Name of the TailwindPort process
- `error_type` - Type of error
- `timestamp` - Event timestamp

### Telemetry Usage Examples

```elixir
# Attach to CSS build events
:telemetry.attach(
  "my-css-builds",
  [:tailwind_port, :css, :done],
  fn event, measurements, metadata, config ->
    IO.puts("CSS build completed in #{measurements.duration / 1_000_000}ms")
  end,
  %{}
)

# Attach to error events
:telemetry.attach(
  "my-tailwind-errors",
  [:tailwind_port, :error, :occurred],
  fn event, measurements, metadata, config ->
    Logger.error("Tailwind error: #{metadata.error_type}")
  end,
  %{}
)

# Attach to all events with pattern matching
:telemetry.attach_many(
  "my-tailwind-monitor",
  [
    [:tailwind_port, :css, :done],
    [:tailwind_port, :other, :done],
    [:tailwind_port, :error, :occurred]
  ],
  fn
    [:tailwind_port, :css, :done], measurements, metadata, config ->
      # Handle CSS builds
      
    [:tailwind_port, :other, :done], measurements, metadata, config ->
      # Handle other outputs
      
    [:tailwind_port, :error, :occurred], measurements, metadata, config ->
      # Handle errors
  end,
  %{}
)
```

## Configuration

TailwindPort can be configured via application environment:

```elixir
# config/config.exs
config :tailwind_port,
  # Tailwind CSS version to download
  version: "3.4.0",
  
  # Download URL template
  download_url: "https://github.com/tailwindlabs/tailwindcss/releases/download/v$version/tailwindcss-$target",
  
  # Default timeout for operations
  default_timeout: 10_000,
  
  # Binary installation path
  bin_path: "priv/bin",
  
  # Enable/disable telemetry
  telemetry: true
```

## Type Specifications

TailwindPort includes comprehensive type specifications for better development experience:

```elixir
@type port_name :: atom()
@type tailwind_opts :: [binary()]
@type health_info :: %{
  created_at: integer(),
  last_activity: integer(),
  total_outputs: non_neg_integer(),
  css_builds: non_neg_integer(),
  errors: non_neg_integer(),
  uptime_seconds: float(),
  port_active: boolean(),
  port_ready: boolean(),
  last_activity_seconds_ago: float()
}
@type error_reason :: atom() | {atom(), term()}
```

These types can be used in your own code for better type safety and documentation.