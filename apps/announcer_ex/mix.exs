defmodule AnnouncerEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :announcer_ex,
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
      mod: {AnnouncerEx.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:xmavlink, "~> 0.5.0"}
    ]
  end
end
