defmodule TailwindPort.MixProject do
  @moduledoc false
  use Mix.Project

  @organization "defdo"

  def project do
    [
      app: :tailwind_port,
      version: "0.2.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      xref: [
        exclude: [:httpc, :public_key]
      ],
      description: "A robust, production-ready Elixir library for integrating Tailwind CSS CLI with comprehensive error handling, health monitoring, and synchronization features.",
      package: package(),
      # exdocs
      name: "Tailwind Port",
      description:
        "A robust, production-ready port for the Tailwind Command Line Interface with comprehensive error handling, health monitoring, port synchronization, and security features. Designed for reliable integration with the Elixir ecosystem.",
      source_url: "https://github.com/defdo-dev/tailwind_cli_port",
      homepage_url: "https://foss.defdo.ninja",
      docs: [
        # The main page in the docs
        main: "readme",
        # logo: "logo.png",
        extras: [
          "README.md",
          "guides/QUICK_START.md",
          "guides/DEVELOPER_GUIDE.md",
          "guides/USAGE.md",
          "guides/EXAMPLES.md",
          "guides/API_REFERENCE.md",
          "guides/MIGRATION_GUIDE.md",
          "CHANGELOG.md",
          "CLAUDE.md"
        ],
        groups_for_extras: [
          "Getting Started": ["README.md", "guides/QUICK_START.md"],
          "Guides": ["guides/DEVELOPER_GUIDE.md", "guides/USAGE.md", "guides/EXAMPLES.md"],
          "Reference": ["guides/API_REFERENCE.md", "guides/MIGRATION_GUIDE.md"],
          "Project Info": ["CHANGELOG.md", "CLAUDE.md"]
        ]
      ]
    ]
  end

  defp package do
    [
      organization: @organization,
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/defdo-dev/tailwind_cli_port",
        "Changelog" => "https://github.com/defdo-dev/tailwind_cli_port/blob/main/CHANGELOG.md",
        "Documentation" => "https://hexdocs.pm/tailwind_port"
      },
      maintainers: ["Defdo Team"],
      files: ~w(lib priv mix.exs README.md CHANGELOG.md LICENSE CLAUDE.md guides),
      exclude_patterns: ["priv/bin/tailwindcss"],  # Exclude the binary - will be downloaded
      keywords: [
        "tailwind",
        "tailwindcss", 
        "css",
        "frontend",
        "build-tools",
        "cli",
        "port",
        "genserver",
        "elixir",
        "phoenix"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [
        :logger,
        runtime_tools: :optional,
        inets: :optional,
        ssl: :optional
      ],
      mod: {TailwindPort.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 1.2"},
      {:castore, ">= 0.0.0"},
      {:ex_doc, ">= 0.0.0", only: [:dev, :docs]}
    ]
  end
end
