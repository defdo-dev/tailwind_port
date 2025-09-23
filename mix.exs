defmodule TailwindPort.MixProject do
  @moduledoc false
  use Mix.Project

  @organization "defdo"

  def project do
    [
      app: :tailwind_port,
      version: "0.3.1",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      xref: [
        exclude: [:httpc, :public_key]
      ],
      description:
        "A robust, production-ready Elixir library for integrating Tailwind CSS CLI with comprehensive error handling, health monitoring, and synchronization features.",
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
          "guides/PERFORMANCE.md",
          "CHANGELOG.md"
        ],
        groups_for_extras: [
          "Getting Started": ["README.md", "guides/QUICK_START.md"],
          Guides: [
            "guides/DEVELOPER_GUIDE.md",
            "guides/USAGE.md",
            "guides/EXAMPLES.md",
            "guides/PERFORMANCE.md"
          ],
          Reference: ["guides/API_REFERENCE.md", "guides/MIGRATION_GUIDE.md"],
          "Project Info": ["CHANGELOG.md"]
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
      files: ~w(lib priv mix.exs README.md CHANGELOG.md LICENSE guides),
      # Exclude the binary - will be downloaded
      exclude_patterns: ["priv/bin/tailwindcss"],
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
      {:telemetry_metrics, "~> 1.0"},
      {:castore, ">= 0.0.0"},
      {:ex_doc, ">= 0.0.0", only: [:dev, :docs]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mock, "~> 0.3.0", only: :test}
    ]
  end
end
