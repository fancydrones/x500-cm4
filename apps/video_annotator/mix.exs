defmodule VideoAnnotator.MixProject do
  use Mix.Project

  def project do
    [
      app: :video_annotator,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {VideoAnnotator.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Neural network inference
      {:yolo, ">= 0.2.0"},
      {:nx, "~> 0.7"},
      {:exla, "~> 0.9"},
      {:emlx, "~> 0.2", only: :dev},  # Metal GPU acceleration for macOS development

      # Image processing
      {:evision, "~> 0.2"},

      # Video processing (for Phase 0 local development)
      {:membrane_camera_capture_plugin, "~> 0.7"},
      {:membrane_h264_ffmpeg_plugin, "~> 0.32"},
      {:membrane_core, "~> 1.1"},
      {:membrane_fake_plugin, "~> 0.11"},
      {:membrane_sdl_plugin, "~> 0.18"},

      # Web-based preview (for development)
      {:plug, "~> 1.15", only: :dev},
      {:bandit, "~> 1.0", only: :dev}
    ]
  end
end
