defmodule VideoStreamer.RTSP.SDP do
  @moduledoc """
  Session Description Protocol (SDP) generator for H.264 video streaming.
  Implements RFC 4566 (SDP) and RFC 6184 (RTP Payload Format for H.264).

  SDP describes the media session including codec, format, and connection details.
  """

  @doc """
  Generate SDP for H.264 video stream.

  ## Parameters
    - server_ip: IP address of the RTSP server
    - stream_path: RTSP stream path (e.g., "/video")
    - video_config: Map with :width, :height, :framerate
    - codec_params: Optional H.264 codec parameters (SPS/PPS)

  ## Example

      generate_sdp("192.168.1.100", "/video", %{
        width: 1280,
        height: 720,
        framerate: 30
      })
  """
  @spec generate_sdp(String.t(), String.t(), map(), map()) :: String.t()
  def generate_sdp(server_ip, stream_path, video_config, codec_params \\ %{}) do
    width = video_config[:width] || 1280
    height = video_config[:height] || 720
    framerate = video_config[:framerate] || 30

    # Session-level description
    session_section = """
    v=0
    o=- #{session_id()} #{session_version()} IN IP4 #{server_ip}
    s=VideoStreamer H.264 Stream
    i=Low-latency H.264 video stream
    c=IN IP4 #{server_ip}
    t=0 0
    a=control:*
    a=range:npt=0-
    """

    # Media-level description
    media_section = generate_media_section(stream_path, width, height, framerate, codec_params)

    String.trim(session_section) <> "\r\n" <> media_section
  end

  defp generate_media_section(stream_path, width, height, framerate, codec_params) do
    # RTP payload type 96 is dynamic for H.264
    payload_type = 96

    # Calculate clock rate (always 90000 for H.264)
    clock_rate = 90_000

    media_line = "m=video 0 RTP/AVP #{payload_type}"

    # rtpmap: payload type, codec name, clock rate
    rtpmap = "a=rtpmap:#{payload_type} H264/#{clock_rate}"

    # fmtp: format parameters for H.264
    fmtp = build_fmtp_line(payload_type, width, height, framerate, codec_params)

    # control: URL for this media track
    control = "a=control:#{stream_path}/trackID=0"

    # Additional attributes for better client compatibility (especially mobile clients)
    attrs = [
      "a=framerate:#{framerate}",
      "a=framesize:#{payload_type} #{width}-#{height}",
      # Add media type to help clients identify this as video
      "a=type:broadcast",
      # Specify this is a video stream (helps some mobile clients)
      "a=x-dimensions:#{width},#{height}"
    ]

    lines = [media_line, rtpmap, fmtp, control] ++ attrs
    Enum.join(lines, "\r\n")
  end

  defp build_fmtp_line(payload_type, _width, _height, _framerate, codec_params) do
    # H.264 profile-level-id
    # Baseline Profile (42 = 0x42), Constrained (E0), Level 3.1 (1F)
    # Changed from High Profile (64001F) to Baseline (42E01F) for iOS/mobile compatibility
    # Format: profile_idc (42) + constraint_flags (E0) + level_idc (1F)
    # 42E01F = Baseline Profile, widely supported on mobile devices including iOS
    profile_level_id = Map.get(codec_params, :profile_level_id, "42E01F")

    # packetization-mode: 1 = Non-interleaved mode (most common)
    packetization_mode = Map.get(codec_params, :packetization_mode, 1)

    fmtp_params = [
      "packetization-mode=#{packetization_mode}",
      "profile-level-id=#{profile_level_id}"
    ]

    # Add SPS/PPS if available (base64 encoded)
    fmtp_params =
      if codec_params[:sprop_parameter_sets] do
        fmtp_params ++ ["sprop-parameter-sets=#{codec_params[:sprop_parameter_sets]}"]
      else
        fmtp_params
      end

    "a=fmtp:#{payload_type} " <> Enum.join(fmtp_params, ";")
  end

  @doc """
  Generate unique session ID based on timestamp.
  """
  @spec session_id() :: String.t()
  def session_id do
    System.system_time(:second) |> to_string()
  end

  @doc """
  Generate session version (NTP timestamp).
  """
  @spec session_version() :: String.t()
  def session_version do
    # NTP epoch is Jan 1, 1900
    # Unix epoch is Jan 1, 1970
    # Difference: 2208988800 seconds
    ntp_offset = 2_208_988_800
    unix_time = System.system_time(:second)
    (unix_time + ntp_offset) |> to_string()
  end

  @doc """
  Extract H.264 codec parameters from stream format.

  This will be used in Phase 3 when we have access to actual SPS/PPS from the H.264 stream.
  For now, we use sensible defaults.
  """
  @spec extract_codec_params(map()) :: map()
  def extract_codec_params(stream_format) do
    # In Phase 3, extract SPS/PPS from Membrane.H264 format
    # For now, return empty map (will use defaults)
    case stream_format do
      %{sps: sps, pps: pps} when is_binary(sps) and is_binary(pps) ->
        # Base64 encode SPS,PPS for sprop-parameter-sets
        sps_b64 = Base.encode64(sps)
        pps_b64 = Base.encode64(pps)

        %{
          sprop_parameter_sets: "#{sps_b64},#{pps_b64}",
          profile_level_id: extract_profile_level_id(sps)
        }

      _ ->
        # Use defaults for Phase 2
        %{}
    end
  end

  # Extract profile-level-id from SPS NAL unit
  # SPS structure: NAL header (1 byte) + profile_idc (1 byte) + constraints (1 byte) + level_idc (1 byte)
  defp extract_profile_level_id(sps) when byte_size(sps) >= 4 do
    <<_nal_header::8, profile::8, constraints::8, level::8, _rest::binary>> = sps

    # Convert to hex string
    profile_hex = Integer.to_string(profile, 16) |> String.pad_leading(2, "0")
    constraints_hex = Integer.to_string(constraints, 16) |> String.pad_leading(2, "0")
    level_hex = Integer.to_string(level, 16) |> String.pad_leading(2, "0")

    "#{profile_hex}#{constraints_hex}#{level_hex}"
  end

  defp extract_profile_level_id(_), do: "42E01F"  # Default: Baseline level 3.1
end
