defmodule VideoStreamer.RTP.UDPSink do
  @moduledoc """
  Simple UDP sink for sending RTP packets to a single client.

  This is a simplified implementation for Phase 2 to get video flowing.
  Phase 3 will add multi-client support via Membrane.Tee.
  """

  use Membrane.Sink

  alias Membrane.{RemoteStream, RTP}

  def_input_pad :input,
    accepted_format: %RemoteStream{type: :packetized, content_format: RTP},
    flow_control: :auto

  def_options client_ip: [
                spec: String.t(),
                description: "Client IP address"
              ],
              client_port: [
                spec: pos_integer(),
                description: "Client RTP port"
              ]

  @impl true
  def handle_init(_ctx, options) do
    # Open UDP socket on port 50000 (server_port_rtp from RTSP SETUP)
    # This is critical - RTP must be sent from the port advertised in RTSP
    # Socket options optimized for streaming:
    # - sndbuf: 256KB send buffer to reduce packet loss
    # - recbuf: 64KB receive buffer
    # - priority: High priority for video packets
    socket_opts = [
      :binary,
      {:active, false},
      {:reuseaddr, true},
      {:sndbuf, 262_144},    # 256KB send buffer
      {:recbuf, 65_536},     # 64KB receive buffer
      {:priority, 6}         # High priority (0-7, higher = more important)
    ]

    case :gen_udp.open(50000, socket_opts) do
      {:ok, socket} ->
        # Parse IP address
        {:ok, ip_tuple} = :inet.parse_address(String.to_charlist(options.client_ip))

        Membrane.Logger.info("Opened UDP socket on port 50000, sending RTP to #{options.client_ip}:#{options.client_port}")

        state = %{
          socket: socket,
          client_ip: ip_tuple,
          client_port: options.client_port,
          packet_count: 0
        }

        {[], state}

      {:error, reason} ->
        Membrane.Logger.error("Failed to open UDP socket on port 50000: #{inspect(reason)}")
        raise "Cannot bind to port 50000: #{inspect(reason)}"
    end
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    # Send RTP packet to client
    :gen_udp.send(state.socket, state.client_ip, state.client_port, buffer.payload)

    new_state = %{state | packet_count: state.packet_count + 1}

    # Log every 100 packets
    if rem(new_state.packet_count, 100) == 0 do
      Membrane.Logger.debug("Sent #{new_state.packet_count} RTP packets to #{:inet.ntoa(state.client_ip)}:#{state.client_port}")
    end

    {[], new_state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    Membrane.Logger.info("End of stream, sent #{state.packet_count} packets")
    {[], state}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    if state.socket do
      :gen_udp.close(state.socket)
    end

    {[], state}
  end
end
