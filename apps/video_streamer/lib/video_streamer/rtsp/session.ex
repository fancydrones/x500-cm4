defmodule VideoStreamer.RTSP.Session do
  @moduledoc """
  RTSP session handler - manages a single RTSP client session.

  Handles the RTSP state machine:
  - INIT -> OPTIONS -> DESCRIBE -> SETUP -> PLAY -> TEARDOWN

  Each client connection gets its own session process.
  """

  use GenServer
  require Logger

  alias VideoStreamer.RTSP.{Protocol, SDP}

  @session_timeout 60_000  # 60 seconds

  defmodule State do
    @moduledoc false
    defstruct [
      :socket,
      :session_id,
      :client_ip,
      :client_port_rtp,
      :client_port_rtcp,
      :server_port_rtp,
      :server_port_rtcp,
      :state,
      :stream_path,
      :buffer
    ]

    @type t :: %__MODULE__{
      socket: :gen_tcp.socket() | nil,
      session_id: String.t() | nil,
      client_ip: String.t(),
      client_port_rtp: integer() | nil,
      client_port_rtcp: integer() | nil,
      server_port_rtp: integer() | nil,
      server_port_rtcp: integer() | nil,
      state: :init | :ready | :playing,
      stream_path: String.t(),
      buffer: binary()
    }
  end

  ## Client API

  def start_link(socket, client_ip) do
    GenServer.start_link(__MODULE__, {socket, client_ip})
  end

  ## Server Callbacks

  @impl true
  def init({socket, client_ip}) do
    Logger.info("New RTSP session from #{client_ip}")

    # Set socket to active mode to receive messages
    :inet.setopts(socket, [{:active, true}, {:packet, :raw}])

    state = %State{
      socket: socket,
      session_id: nil,
      client_ip: client_ip,
      state: :init,
      stream_path: "/video",  # Default stream path
      buffer: ""
    }

    {:ok, state, @session_timeout}
  end

  @impl true
  def handle_info({:tcp, socket, data}, %State{socket: socket} = state) do
    # Append to buffer
    buffer = state.buffer <> data

    # Try to parse and handle complete requests
    case handle_buffer(buffer, state) do
      {:ok, new_buffer, new_state} ->
        {:noreply, %{new_state | buffer: new_buffer}, @session_timeout}

      {:error, reason} ->
        Logger.error("Error handling request: #{inspect(reason)}")
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info({:tcp_closed, socket}, %State{socket: socket} = state) do
    Logger.info("Client #{state.client_ip} disconnected")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:tcp_error, socket, reason}, %State{socket: socket} = state) do
    Logger.error("TCP error from #{state.client_ip}: #{inspect(reason)}")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.info("Session timeout for #{state.client_ip}")
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, %State{socket: socket}) when is_port(socket) do
    :gen_tcp.close(socket)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  ## Private Functions

  defp handle_buffer(buffer, state) do
    # Check if we have a complete RTSP request (ends with \r\n\r\n)
    case :binary.match(buffer, "\r\n\r\n") do
      {pos, _len} ->
        # Extract the complete request
        request_data = binary_part(buffer, 0, pos + 4)
        remaining = binary_part(buffer, pos + 4, byte_size(buffer) - pos - 4)

        case Protocol.parse_request(request_data) do
          {:ok, request} ->
            case handle_request(request, state) do
              {:ok, new_state} ->
                # Continue processing if there's more data
                handle_buffer(remaining, new_state)

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            Logger.error("Failed to parse request: #{inspect(reason)}")
            {:error, reason}
        end

      :nomatch ->
        # Incomplete request, keep buffering
        {:ok, buffer, state}
    end
  end

  defp handle_request(%{method: "OPTIONS"} = request, state) do
    Logger.debug("Handling OPTIONS request")
    cseq = Protocol.get_cseq(request)

    response = Protocol.build_options_response(cseq)
    send_response(response, state.socket)

    {:ok, state}
  end

  defp handle_request(%{method: "DESCRIBE"} = request, state) do
    Logger.debug("Handling DESCRIBE request")
    cseq = Protocol.get_cseq(request)

    # Get video configuration
    camera_config = Application.get_env(:video_streamer, :camera)
    video_config = %{
      width: camera_config[:width] || 1280,
      height: camera_config[:height] || 720,
      framerate: camera_config[:framerate] || 30
    }

    # Generate SDP
    server_ip = get_server_ip(state.socket)
    sdp_body = SDP.generate_sdp(server_ip, state.stream_path, video_config)

    response = Protocol.build_describe_response(cseq, sdp_body)
    send_response(response, state.socket)

    {:ok, %{state | state: :ready}}
  end

  defp handle_request(%{method: "SETUP"} = request, state) do
    Logger.debug("Handling SETUP request")
    cseq = Protocol.get_cseq(request)

    # Parse Transport header
    transport_header = Map.get(request.headers, "Transport", "")

    case Protocol.parse_transport_header(transport_header) do
      {:ok, transport_params} ->
        # Generate session ID if not exists
        session_id = state.session_id || generate_session_id()

        # Allocate server ports for RTP/RTCP (will be used in Phase 3)
        {server_port_rtp, server_port_rtcp} = allocate_server_ports()

        # Build transport response
        transport_response_params = %{
          client_port_rtp: transport_params[:client_port_rtp],
          client_port_rtcp: transport_params[:client_port_rtcp],
          server_port_rtp: server_port_rtp,
          server_port_rtcp: server_port_rtcp
        }

        response = Protocol.build_setup_response(cseq, session_id, transport_response_params)
        send_response(response, state.socket)

        new_state = %{state |
          session_id: session_id,
          client_port_rtp: transport_params[:client_port_rtp],
          client_port_rtcp: transport_params[:client_port_rtcp],
          server_port_rtp: server_port_rtp,
          server_port_rtcp: server_port_rtcp,
          state: :ready
        }

        {:ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to parse Transport header: #{inspect(reason)}")
        error_response = Protocol.build_error_response(cseq, 461, "Unsupported Transport")
        send_response(error_response, state.socket)
        {:error, :invalid_transport}
    end
  end

  defp handle_request(%{method: "PLAY"} = request, state) do
    Logger.debug("Handling PLAY request")
    cseq = Protocol.get_cseq(request)
    session_id = state.session_id

    if session_id do
      # TODO Phase 3: Notify pipeline manager to start RTP streaming
      # VideoStreamer.PipelineManager.add_client(...)

      response = Protocol.build_play_response(cseq, session_id)
      send_response(response, state.socket)

      Logger.info("Client #{state.client_ip} started playing (session: #{session_id})")
      {:ok, %{state | state: :playing}}
    else
      error_response = Protocol.build_error_response(cseq, 455, "Method Not Valid In This State")
      send_response(error_response, state.socket)
      {:error, :no_session}
    end
  end

  defp handle_request(%{method: "TEARDOWN"} = request, state) do
    Logger.debug("Handling TEARDOWN request")
    cseq = Protocol.get_cseq(request)
    session_id = state.session_id

    if session_id do
      # TODO Phase 3: Notify pipeline manager to stop RTP streaming
      # VideoStreamer.PipelineManager.remove_client(...)

      response = Protocol.build_teardown_response(cseq, session_id)
      send_response(response, state.socket)

      Logger.info("Client #{state.client_ip} teardown (session: #{session_id})")
      {:ok, state}
    else
      error_response = Protocol.build_error_response(cseq, 455, "Method Not Valid In This State")
      send_response(error_response, state.socket)
      {:ok, state}
    end
  end

  defp handle_request(%{method: method}, state) do
    Logger.warning("Unsupported method: #{method}")
    {:ok, state}
  end

  defp send_response(response, socket) do
    data = Protocol.serialize_response(response)
    Logger.debug("Sending response:\n#{data}")
    :gen_tcp.send(socket, data)
  end

  defp generate_session_id do
    # Generate random session ID
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end

  defp allocate_server_ports do
    # For Phase 2, use fixed ports (will be dynamic in Phase 3)
    # RTP port must be even, RTCP is RTP+1
    {50000, 50001}
  end

  defp get_server_ip(socket) do
    case :inet.sockname(socket) do
      {:ok, {ip, _port}} ->
        ip
        |> Tuple.to_list()
        |> Enum.join(".")

      _ ->
        "0.0.0.0"
    end
  end
end
