# TailwindCSS Version Compatibility Guide

This guide explains the differences between TailwindCSS v3 and v4 and how tailwind_port handles compatibility between versions.

## Overview

TailwindCSS v4 introduced significant changes to its architecture and CLI interface. This library provides backward compatibility while supporting both versions seamlessly.

## CLI Differences

### TailwindCSS v3 (3.x.x)

```bash
tailwindcss build [options]

Options:
  -i, --input              Input file
  -o, --output             Output file
  -w, --watch              Watch for changes and rebuild as needed
  -p, --poll               Use polling instead of filesystem events when watching
      --content            Content paths to use for removing unused classes
      --postcss            Load custom PostCSS configuration
  -m, --minify             Minify the output
  -c, --config             Path to a custom config file
      --no-autoprefixer    Disable autoprefixer
```

### TailwindCSS v4 (4.x.x)

```bash
tailwindcss [--input input.css] [--output output.css] [--watch] [options…]

Options:
  -i, --input ················· Input file
  -o, --output ················ Output file [default: `-`]
  -w, --watch[=always] ········ Watch for changes and rebuild as needed
  -m, --minify ················ Optimize and minify the output
      --optimize ·············· Optimize the output without minifying
      --cwd ··················· The current working directory [default: `.`]
      --map ··················· Generate a source map [default: `false]
```

## Key Differences

| Feature | v3 | v4 |
|---------|----|----|
| **Configuration** | `tailwind.config.js` (JavaScript) | CSS-first via `@theme` directive |
| **Content Scanning** | Manual with `--content` option | Automatic detection |
| **PostCSS** | Separate with `--postcss` option | Integrated |
| **Config File** | `-c, --config` option | Optional via `@config` directive |
| **Polling** | `--poll` option | Not available |
| **Optimization** | `--minify` only | `--minify` and `--optimize` |
| **Source Maps** | Limited support | Native with `--map` |

## Migration Guide

### From v3 to v4

1. **Remove incompatible CLI options:**
   ```elixir
   # v3 options - REMOVE for v4
   content: ["src/**/*.{heex,ex}"],
   config: "tailwind.config.js",
   postcss: true,
   poll: true
   ```

2. **Update CSS configuration:**
   ```css
   /* tailwind.config.js - v3 */
   module.exports = {
     content: ["src/**/*.{heex,ex}"],
     theme: {
       extend: {
         colors: {
           avocado: '#568203'
         }
       }
     }
   }

   /* app.css - v4 */
   @import "tailwindcss";

   @theme {
     --color-avocado-500: oklch(0.84 0.18 117.33);
   }
   ```

3. **Legacy config support (optional):**
   ```css
   /* app.css - v4 with legacy config */
   @config "./tailwind.config.js";
   @import "tailwindcss";
   ```

### Using tailwind_port

The library automatically detects your TailwindCSS version and filters incompatible options:

```elixir
# This works for both v3 and v4
options = [
  input: "input.css",
  output: "output.css",
  content: ["src/**/*.{heex,ex}"],  # Filtered out for v4
  config: "tailwind.config.js",     # Filtered out for v4
  minify: true
]

{:ok, result} = Defdo.TailwindPort.compile(options)
```

## Library Features

### Version Detection

```elixir
# Automatic version detection
version = Defdo.TailwindPort.CliCompatibility.detect_version()
# => :v4 or :v3
```

### Option Filtering

```elixir
# Filter for specific version
v4_options = Defdo.TailwindPort.CliCompatibility.filter_args_for_version(
  [content: "*.html", config: "config.js", minify: true],
  :v4
)
# => [minify: true]

# Check option support
Defdo.TailwindPort.CliCompatibility.option_supported?(:content, :v4)
# => false

Defdo.TailwindPort.CliCompatibility.option_supported?(:optimize, :v4)
# => true
```

### Migration Helpers

```elixir
# See what options will be removed in v4
removed = Defdo.TailwindPort.CliCompatibility.removed_in_v4([
  content: "*.html",
  config: "tailwind.config.js",
  postcss: true
])
# => [content: "*.html", config: "tailwind.config.js", postcss: true]

# See new options in v4
new = Defdo.TailwindPort.CliCompatibility.new_in_v4()
# => [optimize: nil, cwd: nil, map: nil]
```

## Configuration Examples

### Elixir Application

```elixir
# config/config.exs
config :tailwind_port, version: "4.1.16"  # or "3.4.17"
```

### Phoenix Integration

```elixir
# lib/my_app_web/tailwind.ex
defmodule MyAppWeb.Tailwind do
  def compile do
    options = [
      input: "assets/css/app.css",
      output: "priv/static/assets/app.css",
      # content and config are automatically filtered based on version
      minify: Mix.env() == :prod
    ]

    case Defdo.TailwindPort.compile(options) do
      {:ok, result} ->
        Logger.info("Tailwind compilation successful")
      {:error, reason} ->
        Logger.error("Tailwind compilation failed: #{inspect(reason)}")
    end
  end
end
```

## Troubleshooting

### Common Issues

1. **"invalid option in list" error**
   - Cause: Using v3-specific options with TailwindCSS v4
   - Solution: Remove `content`, `config`, `postcss`, and `poll` options

2. **Empty CSS output**
   - Cause: TailwindCSS v4 not finding content or incorrect CSS format
   - Solution: Use `@import "tailwindcss";` and `@theme` directives

3. **Version detection issues**
   - Cause: Incorrect version configuration
   - Solution: Set correct version in config: `config :tailwind_port, version: "4.1.16"`

### Debug Commands

```elixir
# Check detected version
Defdo.TailwindPort.CliCompatibility.detect_version()

# See supported options for your version
Defdo.TailwindPort.CliCompatibility.supported_options(:v4)

# Filter your current options
current_options = [input: "a.css", content: "*.html", config: "config.js"]
filtered = Defdo.TailwindPort.CliCompatibility.filter_args_for_current_version(current_options)
```

## Testing

The library includes comprehensive tests for both versions:

```bash
# Run all compatibility tests
mix test test/cli_compatibility_test.exs

# Run integration tests for both versions
mix test --include integration
```

## Version Support Matrix

| TailwindCSS Version | Status | CLI Options | Config Method |
|---------------------|--------|-------------|---------------|
| 3.x.x | ✅ Supported | Full v3 options | tailwind.config.js |
| 4.x.x | ✅ Supported | v4 options only | CSS @theme directive |

## Future Compatibility

As TailwindCSS evolves, this library will continue to provide:
- Automatic version detection
- Backward compatibility when possible
- Clear migration paths
- Comprehensive documentation

For more information, see the [TailwindCSS v4 upgrade guide](https://tailwindcss.com/docs/v4-beta/upgrading).