# Quick Start Guide - TailwindPort

Welcome to TailwindPort! This guide will help you integrate Tailwind CSS into your Elixir project in less than 5 minutes.

## 📋 Prerequisites

- Elixir 1.16 or higher
- Mix (included with Elixir)
- Internet access (to download the Tailwind CSS binary)

## 🚀 Installation

### 1. Add the dependency

Add `tailwind_port` to your `mix.exs` file:

```elixir
def deps do
  [
    {:tailwind_port, "~> 0.2.0", organization: "defdo"}
  ]
end
```

### 2. Install dependencies

```bash
mix deps.get
```

### 3. Compile the project

```bash
mix compile
```

## ⚡ Basic Usage

### Minimal Example

```elixir
# Start TailwindPort
{:ok, _pid} = Defdo.TailwindPort.start_link([
  opts: [
    "-i", "./assets/css/app.css",
    "-o", "./priv/static/css/app.css",
    "--content", "./lib/**/*.{ex,heex}"
  ]
])

# Wait until ready
:ok = Defdo.TailwindPort.wait_until_ready()

IO.puts("CSS generated successfully!")
```

### Watch Mode for Development

```elixir
# Start in watch mode (rebuilds automatically)
{:ok, _pid} = Defdo.TailwindPort.start_link([
  name: :dev_watcher,
  opts: [
    "-i", "./assets/css/app.css",
    "-o", "./priv/static/css/app.css", 
    "--content", "./lib/**/*.{ex,heex}",
    "--watch"
  ]
])

# Verify it's working
case Defdo.TailwindPort.wait_until_ready(:dev_watcher, 10_000) do
  :ok -> IO.puts("🎨 Tailwind is watching for changes!")
  {:error, :timeout} -> IO.puts("❌ Failed to start watcher")
end
```

## 📁 Recommended File Structure

```
your_project/
├── assets/
│   ├── css/
│   │   └── app.css          # Your main CSS file
│   └── tailwind.config.js   # Tailwind configuration
├── lib/
│   └── your_app/            # Your Elixir code
├── priv/
│   └── static/
│       └── css/
│           └── app.css      # Generated CSS (output)
└── mix.exs
```

## 🎨 Basic Tailwind Configuration

Create `assets/tailwind.config.js`:

```javascript
module.exports = {
  content: [
    "./lib/**/*.{ex,heex,js}",
    "./priv/static/**/*.{html,js}"
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
```

Create `assets/css/app.css`:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

/* Your custom styles here */
```

## 🔧 Phoenix Integration

### In your Application

```elixir
defmodule YourApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # ... other processes
      
      # Add TailwindPort for development
      {YourApp.TailwindManager, []}
    ]

    opts = [strategy: :one_for_one, name: YourApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Custom Manager

```elixir
defmodule YourApp.TailwindManager do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    if Mix.env() == :dev do
      start_development_watcher()
    end
    {:ok, %{}}
  end

  defp start_development_watcher do
    opts = [
      name: :phoenix_tailwind,
      opts: [
        "-i", "./assets/css/app.css",
        "-o", "./priv/static/css/app.css",
        "--content", "./lib/**/*.{ex,heex}",
        "--watch"
      ]
    ]
    
    case Defdo.TailwindPort.start_link(opts) do
      {:ok, _pid} ->
        Logger.info("🎨 Starting Tailwind CSS watcher...")
        
        Task.start(fn ->
          case Defdo.TailwindPort.wait_until_ready(:phoenix_tailwind, 15_000) do
            :ok -> 
              Logger.info("✅ Tailwind CSS watcher ready!")
            {:error, :timeout} ->
              Logger.error("❌ Failed to start watcher")
          end
        end)
        
      {:error, reason} ->
        Logger.error("Failed to start Tailwind: #{inspect(reason)}")
    end
  end
end
```

## 🏗️ Production Build

```elixir
# Script for production build
defmodule YourApp.BuildAssets do
  def build_production do
    {:ok, _pid} = Defdo.TailwindPort.start_link([
      name: :prod_build,
      opts: [
        "-i", "./assets/css/app.css",
        "-o", "./priv/static/css/app.css",
        "--content", "./lib/**/*.{ex,heex}",
        "--minify"  # Minify for production
      ]
    ])
    
    :ok = Defdo.TailwindPort.wait_until_ready(:prod_build, 30_000)
    IO.puts("✅ Production CSS generated!")
  end
end
```

Run with:

```bash
mix run -e "YourApp.BuildAssets.build_production()"
```

## 🔍 Monitoring and Debugging

### Check process status

```elixir
# Check if ready
if Defdo.TailwindPort.ready?() do
  IO.puts("Port ready to process CSS")
end

# Get health metrics
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

### Error handling

```elixir
case Defdo.TailwindPort.start_link(opts) do
  {:ok, pid} -> 
    IO.puts("Port created successfully!")
  {:error, :max_retries_exceeded} -> 
    IO.puts("Error: Maximum retries exceeded")
  {:error, reason} -> 
    IO.puts("Error: #{inspect(reason)}")
end
```

## 🆘 Common Troubleshooting

### Error: "Binary not found"

```bash
# The binary downloads automatically, but if there are issues:
mix run -e "Defdo.TailwindDownload.install()"
```

### Error: "Port timeout"

```elixir
# Increase the timeout
:ok = Defdo.TailwindPort.wait_until_ready(:my_port, 30_000)  # 30 seconds
```

### CSS not updating

1. Verify that watch mode is active
2. Check that content paths are correct
3. Ensure the output CSS file has write permissions

## 📚 Next Steps

- Read the [Complete Usage Guide](./USAGE.md)
- Check out [Advanced Examples](./EXAMPLES.md)
- Browse the [API Documentation](https://hexdocs.pm/tailwind_port)
- See the [CHANGELOG](../CHANGELOG.md) for latest features

## 🤝 Support

- **GitHub Issues**: [Report problems](https://github.com/defdo-dev/tailwind_cli_port/issues)
- **Documentation**: [HexDocs](https://hexdocs.pm/tailwind_port)
- **Changelog**: [View changes](../CHANGELOG.md)

Happy coding with TailwindPort! 🎉