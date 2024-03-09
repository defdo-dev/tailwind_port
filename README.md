# TailwindPort

The `Defdo.TailwindPort` module provides an interface to interact with an Elixir port, enabling communication with the Tailwind CSS CLI. 
This allows the integration of Tailwind CSS build processes into Elixir applications.

## Installation

If [available in Hex](https://defdo.hexdocs.pm/tailwind_port), the package can be installed
by adding `tailwind_port` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tailwind_port, "~> 0.1.3", organization: "defdo"}
  ]
end
```

Then, run:

```sh
mix deps.get
```

## Usage

  To use this module, start the it using `start_link/1`:

      iex> {:ok, pid} = Defdo.TailwindPort.start_link [opts: ["-i", "./assets/css/app.css", "--content", "./priv/static/html/**/*.{html,js}", "-c", "./assets/tailwind.config.js", "--watch"]]


## License
  This project is licensed under the Apache License, Version 2.0.