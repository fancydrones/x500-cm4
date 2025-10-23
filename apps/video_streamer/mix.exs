defmodule VideoStreamer.MixProject do
  use Mix.Project

  def project do
    [
      app: :video_streamer,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Documentation
      name: "VideoStreamer",
      source_url: "https://github.com/fancydrones/x500-cm4",
      homepage_url: "https://github.com/fancydrones/x500-cm4/tree/main/apps/video_streamer",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {VideoStreamer.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Membrane core
      {:membrane_core, "~> 1.0"},

      # Camera capture - internalized (see lib/membrane_rpicam/source.ex)
      # {:membrane_rpicam_plugin, "~> 0.1.5"},  # Removed - internalized with fixes

      # RTP/RTSP
      {:membrane_rtp_plugin, "~> 0.31.0"},
      {:membrane_rtp_h264_plugin, "~> 0.20.0"},
      {:membrane_rtsp, "~> 0.11.0"},

      # Network
      {:membrane_udp_plugin, "~> 0.14.0"},
      {:membrane_tcp_plugin, "~> 0.6.0"},

      # Utilities
      {:membrane_file_plugin, "~> 0.17.0"},  # Future recording
      {:membrane_tee_plugin, "~> 0.12.0"},   # Future multi-output
      {:membrane_h26x_plugin, "~> 0.10.5"},  # H.26x parser
      {:membrane_fake_plugin, "~> 0.11.0"},  # Fake sink for Phase 1 testing

      # Configuration & telemetry
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},

      # Documentation
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: nil,
      extras: [
        "README.md",
        "docs/architecture.md",
        "docs/operations.md",
        "docs/development.md"
      ],
      groups_for_extras: [
        Documentation: ~r/docs\/.*/
      ],
      groups_for_modules: [
        "RTSP Protocol": [
          VideoStreamer.RTSP.Server,
          VideoStreamer.RTSP.Protocol,
          VideoStreamer.RTSP.SDP
        ],
        "Pipeline Components": [
          VideoStreamer.Pipeline,
          VideoStreamer.PipelineManager,
          Membrane.Rpicam.Source
        ],
        Core: [
          VideoStreamer,
          VideoStreamer.Application,
          VideoStreamer.Telemetry
        ]
      ],
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  # Add some basic styling for the documentation
  defp before_closing_body_tag(:html) do
    """
    <style>
      .sidebar .sidebar-heading { color: #663399; }
      .content a { color: #663399; }
    </style>
    """
  end

  defp before_closing_body_tag(_), do: ""
end
