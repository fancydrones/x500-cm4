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
      main: "RouterEx",
      logo: nil,
      extras: [
        "README.md": [title: "Overview"],
        "docs/operations.md": [title: "Operations Guide"],
        "../../PRDs/004-router-ex/README.md": [title: "PRD"],
        "../../PRDs/004-router-ex/phase5-completion-summary.md": [title: "Testing Summary"]
      ],
      groups_for_extras: [
        Guides: ~r/docs\/.*/,
        PRDs: ~r/PRDs\/.*/
      ],
      groups_for_modules: [
        Core: [
          RouterEx,
          RouterEx.Application,
          RouterEx.ConfigManager,
          RouterEx.RouterCore,
          RouterEx.Telemetry,
          RouterEx.HealthMonitor
        ],
        Endpoints: [
          RouterEx.Endpoint.Supervisor,
          RouterEx.Endpoint.Serial,
          RouterEx.Endpoint.Serial.State,
          RouterEx.Endpoint.UdpServer,
          RouterEx.Endpoint.UdpServer.State,
          RouterEx.Endpoint.UdpServer.Client,
          RouterEx.Endpoint.UdpClient,
          RouterEx.Endpoint.UdpClient.State,
          RouterEx.Endpoint.TcpServer,
          RouterEx.Endpoint.TcpServer.State,
          RouterEx.Endpoint.TcpClient,
          RouterEx.Endpoint.TcpClient.State
        ],
        "MAVLink Protocol": [
          RouterEx.MAVLink.Parser
        ]
      ],
      # Add custom sections
      before_closing_head_tag: &before_closing_head_tag/1,
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  defp before_closing_head_tag(:html) do
    """
    <style>
      .sidebar-listNav { max-height: calc(100vh - 100px); }
    </style>
    """
  end

  defp before_closing_head_tag(_), do: ""

  defp before_closing_body_tag(:html) do
    """
    <script>
      // Custom JavaScript for docs if needed
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""
end
