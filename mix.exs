defmodule PhoenixLens.MixProject do
  use Mix.Project

  @version "0.1.2"
  @source_url "https://github.com/oivoodoo/phoenix_lens"
  @docs_url "https://hexdocs.pm/phoenix_lens"
  @pages_url "https://oivoodoo.github.io/phoenix_lens"

  def project do
    [
      app: :phoenix_lens,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description:
        "Mountable SQL notebook for Phoenix. Point it at your Ecto Repo, save questions, pin dashboards, and mask PII/PHI in every output.",
      source_url: @source_url,
      homepage_url: @pages_url,
      docs: docs(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :crypto, :inets],
      mod: {PhoenixLens.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 0.20 or ~> 1.0"},
      {:plug, "~> 1.16"},
      {:jason, "~> 1.4"},
      {:postgrex, "~> 0.17"},
      {:ecto_sql, "~> 3.11"},
      {:bandit, "~> 1.5"},
      {:duckdbex, "~> 0.4", optional: true},
      {:plug_cowboy, "~> 2.6", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "phoenix_lens",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Guide" => @docs_url <> "/guide.html",
        "GitHub Pages" => @pages_url <> "/guide.html"
      },
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE.txt CHANGELOG.md docs)
    ]
  end

  defp docs do
    [
      main: "guide",
      extras: [
        "docs/Guide.md",
        "README.md",
        "CHANGELOG.md",
        "docs/Phoenix.md",
        "docs/Policy.md",
        "docs/Permissions.md",
        "docs/decisions/001-in-process-not-a-metabase-clone.md",
        "docs/decisions/002-field-policy-on-every-sink.md",
        "docs/decisions/003-postgres-read-replica-timeout.md",
        "docs/decisions/004-duckdb-engine.md"
      ],
      groups_for_extras: [
        Guides: [
          "docs/Guide.md",
          "docs/Phoenix.md",
          "docs/Policy.md",
          "docs/Permissions.md"
        ],
        Decisions: ~r{docs/decisions/}
      ],
      assets: %{"docs/images" => "images"},
      skip_undefined_reference_warnings_on: ["docs/Guide.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp aliases do
    [
      test: ["test"]
    ]
  end
end
