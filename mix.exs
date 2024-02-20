defmodule TailwindPort.MixProject do
  use Mix.Project

  @organization "defdo"

  def project do
    [
      app: :tailwind_port,
      version: "0.1.1",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      xref: [
        exclude: [:httpc, :public_key]
      ],
      description: "A port to use the tailwind cli with elixir.",
      package: package(),
      # exdocs
      name: "Defdo.Vault",
      source_url: "https://github.com/defdo-dev/tailwind_cli_port",
      homepage_url: "https://foss.defdo.ninja",
      docs: [
        # The main page in the docs
        # main: "Defdo.Tasks.Application",
        # logo: "logo.png",
        extras: ["README.md"]
      ]
    ]
  end

  defp package do
    [
      organization: @organization,
      licenses: ["Apache-2.0"],
      links: %{},
      exclude_patterns: ["priv/bin/tailwindcss"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TailwindPort.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:castore, ">= 0.0.0"},
      {:ex_doc, ">= 0.0.0", only: [:dev, :docs]}
    ]
  end
end
