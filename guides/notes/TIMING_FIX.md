# TailwindPort: CSS Generation Timing Fix

## Problem Resolved

Fixed critical race condition where CSS was generated correctly but lost due to port termination timing. The port would exit before CSS could be extracted, resulting in `extract_css_with_fallbacks() => ""`.

## Root Cause Analysis

### Original Broken Flow
```
1. Pool.compile() → Standalone starts port
2. TailwindCSS generates CSS → Standalone stores in state
3. Port exits normally (:exit_status: 0)
4. Pool.extract_css_with_fallbacks() → Standalone process dead
5. Result: CSS = "" (empty)
```

### Issue Symptoms
- CSS visible in logs: `"/*! tailwindcss v4.1.13..."`
- Port exits successfully: `:exit_status: 0`
- Extraction fails: `extract_css_with_fallbacks() => ""`
- Final result: Empty CSS returned to callers

## Solution: Immediate CSS Callback System

### New Flow with Immediate Capture
```
1. Pool.compile() → register_css_listener()
2. Standalone generates CSS → notify_listeners() IMMEDIATELY
3. Pool receives CSS BEFORE port termination
4. Port exits (irrelevant - CSS already captured)
5. Result: CSS captured successfully
```

## Implementation Details

### Pool.ex Changes

#### New Primary Function
```elixir
defp run_tailwind_build_with_immediate_capture(port_info, working_paths, options, operation) do
  capture_ref = make_ref()

  # Register Pool as CSS listener
  register_css_listener(port_info.pid, self(), capture_ref, operation.id)

  # Wait for immediate CSS notification
  receive do
    {:css_generated, ^capture_ref, css_data} when is_binary(css_data) and css_data != "" ->
      {:ok, %{css: css_data, capture_method: :immediate}}
    {:css_generation_failed, ^capture_ref, reason} ->
      fallback_to_file_based_capture(port_info, working_paths, options)
  after timeout_ms ->
    fallback_to_file_based_capture(port_info, working_paths, options)
  end
end
```

#### Robust Fallback System
```elixir
defp fallback_to_file_based_capture(port_info, working_paths, options) do
  # Falls back to original file-based extraction
  # Then to degraded extraction methods
  # Maintains backward compatibility
end
```

### Standalone.ex Changes

#### Enhanced State
```elixir
%{
  # Existing fields...
  css_listeners: []  # New: List of registered Pool processes
}
```

#### Immediate CSS Notification
```elixir
def handle_info({port, {:data, data}}, %{port: port} = state) do
  if String.contains?(data, "{") or String.contains?(data, "}") do
    css_output = String.trim(data)

    # Store CSS in multiple places for resilience
    persistent_state = %{new_state |
      latest_output: css_output,
      last_css_output: css_output,
      preserved_css: css_output
    }

    # KEY FIX: Notify listeners IMMEDIATELY before port can terminate
    notify_css_listeners(persistent_state.css_listeners, css_output)

    {:noreply, persistent_state}
  end
end
```

#### CSS Listener Management
```elixir
# Register Pool processes as CSS listeners
def handle_info({:register_css_listener, listener_pid, capture_ref, operation_id}, state) do
  listener = %{
    pid: listener_pid,
    ref: capture_ref,
    operation_id: operation_id,
    registered_at: System.monotonic_time(:millisecond)
  }

  new_listeners = [listener | state.css_listeners]
  {:noreply, %{state | css_listeners: new_listeners}}
end

# Send CSS to all registered listeners
defp notify_css_listeners(listeners, css) when is_binary(css) and css != "" do
  Enum.each(listeners, fn listener ->
    send(listener.pid, {:css_generated, listener.ref, css})
  end)
end
```

## Benefits

### Timing Independence
- **Before**: CSS extraction dependent on port lifetime
- **After**: CSS captured immediately when generated, independent of port termination

### Resilience Layers
1. **Primary**: Immediate callback system (NEW)
2. **Secondary**: File-based extraction (existing)
3. **Tertiary**: Degraded state extraction (existing)
4. **Emergency**: Process dictionary fallback (existing)

### Performance Improvements
- ✅ Eliminates race conditions
- ✅ Reduces polling and timeouts
- ✅ Provides instant CSS capture
- ✅ Zero performance impact on existing flows

## API Compatibility

### Zero Breaking Changes
```elixir
# Existing API works exactly the same
{:ok, result} = TailwindPort.Pool.compile(opts, content)

# Enhanced result metadata (optional)
%{
  compiled_css: css_content,  # Now reliably non-empty
  capture_method: :immediate, # New optional field
  port: port,
  operation_id: ref
}
```

### Backward Compatibility
- All existing functions preserved
- Fallback to original methods if immediate capture fails
- No changes required in calling code

## Usage Examples

### Standard Usage (Unchanged)
```elixir
# Start pool
{:ok, _pid} = TailwindPort.Pool.start_link()

# Compile CSS - now reliably returns CSS
{:ok, result} = TailwindPort.Pool.compile([
  input: "app.css",
  output: "dist/app.css",
  content: "./lib/**/*.{ex,heex}"
], content)

# result.compiled_css is now reliably non-empty
assert byte_size(result.compiled_css) > 0
```

### Observability
```elixir
# Check capture method used
case result.capture_method do
  :immediate -> IO.puts("CSS captured immediately (optimal)")
  :file_based -> IO.puts("CSS captured from file (fallback)")
  :degraded_fallback -> IO.puts("CSS captured via degraded methods")
end
```

## Testing

### Verification Steps
1. Start pool and compile CSS
2. Verify CSS content is non-empty
3. Check logs for immediate capture success
4. Test fallback scenarios by introducing delays

### Performance Testing
```elixir
# Measure improvement in CSS capture reliability
{time, result} = :timer.tc(fn ->
  TailwindPort.Pool.compile(opts, content)
end)

assert byte_size(result.compiled_css) > 0
assert result.capture_method in [:immediate, :file_based, :degraded_fallback]
```

## Debugging

### Enhanced Logging
```elixir
# Pool side
[debug] Pool: Immediate CSS capture successful (15420 bytes)
[debug] Pool: Immediate CSS capture timeout, falling back to file-based

# Standalone side
[debug] Standalone: Registering CSS listener for operation
[debug] Standalone: Notifying 1 CSS listeners with 15420 bytes
[debug] Standalone: CSS sent to listener for operation
```

### Troubleshooting
- Monitor immediate vs fallback capture ratios
- Check CSS listener registration success
- Verify port timing and termination patterns

## Migration Guide

### For Existing Code
No changes required - the fix is transparent to existing callers.

### For New Code
```elixir
# Optional: Check capture method for monitoring
{:ok, result} = TailwindPort.Pool.compile(opts, content)

case Map.get(result, :capture_method) do
  :immediate -> :ok  # Optimal path
  :file_based -> Logger.info("Used file-based fallback")
  :degraded_fallback -> Logger.warning("Used degraded fallback")
  nil -> :ok  # Backward compatibility - no capture_method field
end
```

This fix resolves the fundamental timing issue while maintaining full compatibility and providing multiple resilience layers for robust CSS generation.