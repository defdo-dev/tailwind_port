defmodule TailwindPort.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Names the CLI processes the pool starts, without minting an atom per
      # process, and lets a restarted pool find ports its predecessor left.
      {Registry, keys: :unique, name: TailwindPort.PoolRegistry},
      # Initialize a dynamic supervisor in order to allow dynamic instances.
      {DynamicSupervisor, name: TailwindPort.DynamicSupervisor, strategy: :one_for_one}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TailwindPort.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
