defmodule RouterEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :router_ex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Documentation
      name: "RouterEx",
      source_url: "https://github.com/fancydrones/x500-cm4",
      homepage_url: "https://github.com/fancydrones/x500-cm4/tree/main/apps/router_ex",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {RouterEx.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # MAVLink library
      {:xmavlink, "~> 0.5.0"},

      # Serial communication
      {:circuits_uart, "~> 1.5"},

      # Configuration parsing (optional - for backward compatibility)
      # YAML support
      {:yaml_elixir, "~> 2.9", optional: true},
      # TOML support
      {:toml, "~> 0.7", optional: true},

      # Telemetry
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},

      # Testing
      {:stream_data, "~> 1.0", only: :test},

      # Documentation
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: nil,
      extras: [
        "README.md"
      ],
      groups_for_modules: [
        Core: [
          RouterEx,
          RouterEx.Application,
          RouterEx.ConfigManager,
          RouterEx.RouterCore,
          RouterEx.Telemetry
        ],
        Endpoints: [
          RouterEx.Endpoint.Supervisor,
          RouterEx.Endpoint.Serial,
          RouterEx.Endpoint.UDPServer,
          RouterEx.Endpoint.UDPClient,
          RouterEx.Endpoint.TCPServer
        ],
        Configuration: [
          RouterEx.Config.Schema,
          RouterEx.Config.Validator
        ],
        Utilities: [
          RouterEx.MessageParser,
          RouterEx.MessageFilter
        ]
      ]
    ]
  end
end
