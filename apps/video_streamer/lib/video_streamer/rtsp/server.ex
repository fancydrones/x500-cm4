defmodule VideoStreamer.RTSP.Server do
  @moduledoc """
  RTSP server - listens for TCP connections and spawns session handlers.

  Manages:
  - TCP socket listening on configured port
  - Accepting new client connections
  - Spawning RTSP session handlers for each client
  - Tracking active sessions
  - Enforcing connection limits
  """

  use GenServer
  require Logger

  alias VideoStreamer.RTSP.Session

  @default_port 8554
  @max_clients 10

  defmodule State do
    @moduledoc false
    defstruct [
      :listen_socket,
      :port,
      :max_clients,
      :sessions
    ]

    @type t :: %__MODULE__{
      listen_socket: :gen_tcp.socket() | nil,
      port: integer(),
      max_clients: integer(),
      sessions: MapSet.t()
    }
  end

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get server status and active sessions count.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, get_configured_port())
    max_clients = Keyword.get(opts, :max_clients, @max_clients)

    Logger.info("Starting RTSP server on port #{port}")

    case :gen_tcp.listen(port, [
      :binary,
      {:packet, :raw},
      {:active, false},
      {:reuseaddr, true},
      {:backlog, 10}
    ]) do
      {:ok, listen_socket} ->
        Logger.info("RTSP server listening on port #{port}")

        state = %State{
          listen_socket: listen_socket,
          port: port,
          max_clients: max_clients,
          sessions: MapSet.new()
        }

        # Start accepting connections
        send(self(), :accept)

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start RTSP server: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:accept, state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, client_socket} ->
        # Get client IP
        {:ok, {client_ip, _port}} = :inet.peername(client_socket)
        client_ip_str = format_ip(client_ip)

        # Check connection limit
        if MapSet.size(state.sessions) >= state.max_clients do
          Logger.warning("Max clients reached, rejecting connection from #{client_ip_str}")
          :gen_tcp.close(client_socket)
          send(self(), :accept)
          {:noreply, state}
        else
          # Spawn session handler
          case Session.start_link(client_socket, client_ip_str) do
            {:ok, session_pid} ->
              # Transfer socket ownership to session
              :gen_tcp.controlling_process(client_socket, session_pid)

              # Monitor session
              Process.monitor(session_pid)

              new_sessions = MapSet.put(state.sessions, session_pid)
              Logger.info("Accepted connection from #{client_ip_str} (#{MapSet.size(new_sessions)}/#{state.max_clients})")

              # Continue accepting
              send(self(), :accept)
              {:noreply, %{state | sessions: new_sessions}}

            {:error, reason} ->
              Logger.error("Failed to start session handler: #{inspect(reason)}")
              :gen_tcp.close(client_socket)
              send(self(), :accept)
              {:noreply, state}
          end
        end

      {:error, :closed} ->
        Logger.info("Listen socket closed")
        {:stop, :normal, state}

      {:error, reason} ->
        Logger.error("Error accepting connection: #{inspect(reason)}")
        # Try again after a short delay
        Process.send_after(self(), :accept, 1000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Session process terminated
    new_sessions = MapSet.delete(state.sessions, pid)
    Logger.debug("Session terminated (#{MapSet.size(new_sessions)}/#{state.max_clients} active)")
    {:noreply, %{state | sessions: new_sessions}}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      port: state.port,
      active_sessions: MapSet.size(state.sessions),
      max_clients: state.max_clients
    }

    {:reply, status, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("RTSP server terminating: #{inspect(reason)}")

    if state.listen_socket do
      :gen_tcp.close(state.listen_socket)
    end

    :ok
  end

  ## Private Functions

  defp get_configured_port do
    rtsp_config = Application.get_env(:video_streamer, :rtsp, [])
    Keyword.get(rtsp_config, :port, @default_port)
  end

  defp format_ip({a, b, c, d}) do
    "#{a}.#{b}.#{c}.#{d}"
  end

  defp format_ip(_), do: "unknown"
end
