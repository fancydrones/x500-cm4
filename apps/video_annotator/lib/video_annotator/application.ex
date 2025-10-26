defmodule VideoAnnotator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Set EXLA as the default backend for Nx
    # This enables JIT compilation with XLA for much faster tensor operations
    # Note: EMLX (Metal GPU) was tested but has kernel compilation issues with our operations
    Nx.global_default_backend(EXLA.Backend)

    children =
      [
        # Start web preview server in dev mode
        if(Mix.env() == :dev, do: {VideoAnnotator.WebPreview, 4001}, else: nil)
      ]
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: VideoAnnotator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
