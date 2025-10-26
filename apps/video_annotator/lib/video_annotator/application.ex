defmodule VideoAnnotator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Use EMLX (Metal GPU) on macOS for 1.8x speedup, EXLA (CPU) elsewhere
    # Benchmark: EMLX 57.4ms vs EXLA 103.3ms (80% faster!)
    backend = select_backend()
    Nx.global_default_backend(backend)
    IO.puts("Using Nx backend: #{inspect(backend)}")

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

  # Select best backend for platform
  # Runtime detection with optional config override
  defp select_backend do
    # Check if backend explicitly configured
    case Application.get_env(:video_annotator, :nx_backend) do
      nil ->
        # Auto-detect based on OS (recommended)
        case :os.type() do
          {:unix, :darwin} ->
            # macOS - use Metal GPU acceleration (1.8x faster)
            EMLX.Backend

          _ ->
            # Linux (Raspberry Pi) - use CPU
            EXLA.Backend
        end

      backend when is_atom(backend) ->
        # Use explicitly configured backend
        backend
    end
  end
end
