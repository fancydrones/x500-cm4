defmodule Companion.MixProject do
  use Mix.Project

  def project do
    [
      app: :companion,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Companion.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:xmavlink_util, "~> 0.4"},
      {:phoenix, "~> 1.7.6"},
      {:phoenix_html, "~> 4.0.0"},
      {:phoenix_live_reload, "~> 1.5.1", only: :dev},
      {:phoenix_live_view, "~> 0.20.5"},
      {:phoenix_view, "~> 2.0.2"},
      {:floki, ">= 0.34.3", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.1"},
      {:esbuild, "~> 0.8.1", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 0.6.1"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.24.0"},
      {:jason, "~> 1.4.1"},
      {:plug_cowboy, "~> 2.7.0"},
      {:k8s, "~> 2.5.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get"],
      "assets.deploy": ["esbuild default --minify", "phx.digest"]
    ]
  end
end
