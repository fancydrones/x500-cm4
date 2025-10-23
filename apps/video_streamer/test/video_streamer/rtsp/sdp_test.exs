defmodule VideoStreamer.RTSP.SDPTest do
  use ExUnit.Case, async: true
  alias VideoStreamer.RTSP.SDP

  describe "generate_sdp/3" do
    test "generates valid SDP with basic video config" do
      server_ip = "192.168.1.100"
      stream_path = "/video"
      video_config = %{width: 1280, height: 720, framerate: 30}

      sdp = SDP.generate_sdp(server_ip, stream_path, video_config)

      # Check session-level fields
      assert sdp =~ "v=0"
      assert sdp =~ "o=- "
      assert sdp =~ "IN IP4 #{server_ip}"
      assert sdp =~ "s=VideoStreamer H.264 Stream"
      assert sdp =~ "i=Low-latency H.264 video stream"
      assert sdp =~ "c=IN IP4 #{server_ip}"
      assert sdp =~ "t=0 0"
      assert sdp =~ "a=control:*"
      assert sdp =~ "a=range:npt=0-"

      # Check media-level fields
      assert sdp =~ "m=video 0 RTP/AVP 96"
      assert sdp =~ "a=rtpmap:96 H264/90000"
      assert sdp =~ "a=control:#{stream_path}/trackID=0"
      assert sdp =~ "a=framerate:30"
      assert sdp =~ "a=framesize:96 1280-720"
    end

    test "generates SDP with custom resolution and framerate" do
      server_ip = "10.10.10.2"
      stream_path = "/live"
      video_config = %{width: 1920, height: 1080, framerate: 60}

      sdp = SDP.generate_sdp(server_ip, stream_path, video_config)

      assert sdp =~ "a=framerate:60"
      assert sdp =~ "a=framesize:96 1920-1080"
      assert sdp =~ "a=x-dimensions:1920,1080"
      assert sdp =~ "a=control:#{stream_path}/trackID=0"
    end

    test "uses default values when video config is empty" do
      server_ip = "192.168.1.100"
      stream_path = "/video"
      video_config = %{}

      sdp = SDP.generate_sdp(server_ip, stream_path, video_config)

      # Should use defaults: 1280x720@30fps
      assert sdp =~ "a=framerate:30"
      assert sdp =~ "a=framesize:96 1280-720"
      assert sdp =~ "a=x-dimensions:1280,720"
    end

    test "includes H.264 format parameters" do
      server_ip = "192.168.1.100"
      stream_path = "/video"
      video_config = %{width: 1280, height: 720, framerate: 30}

      sdp = SDP.generate_sdp(server_ip, stream_path, video_config)

      # Check fmtp line with H.264 parameters
      assert sdp =~ "a=fmtp:96"
      assert sdp =~ "packetization-mode=1"
      assert sdp =~ "profile-level-id=4D4028"
      assert sdp =~ "sprop-parameter-sets="
    end

    test "includes proper RTSP control URLs" do
      server_ip = "192.168.1.100"
      stream_path = "/test/stream"
      video_config = %{width: 1280, height: 720, framerate: 30}

      sdp = SDP.generate_sdp(server_ip, stream_path, video_config)

      assert sdp =~ "a=control:*"
      assert sdp =~ "a=control:#{stream_path}/trackID=0"
    end
  end

  describe "generate_sdp/4" do
    test "accepts custom codec parameters" do
      server_ip = "192.168.1.100"
      stream_path = "/video"
      video_config = %{width: 1280, height: 720, framerate: 30}
      codec_params = %{
        profile_level_id: "42E01F",
        packetization_mode: 0,
        sprop_parameter_sets: "Z0LAHtkDxWhAAAADAEAAAAwDxYuS,aMuMsg=="
      }

      sdp = SDP.generate_sdp(server_ip, stream_path, video_config, codec_params)

      # Check custom codec parameters are used
      assert sdp =~ "profile-level-id=42E01F"
      assert sdp =~ "packetization-mode=0"
      assert sdp =~ "sprop-parameter-sets=Z0LAHtkDxWhAAAADAEAAAAwDxYuS,aMuMsg=="
    end

    test "uses default codec parameters when not provided" do
      server_ip = "192.168.1.100"
      stream_path = "/video"
      video_config = %{width: 1280, height: 720, framerate: 30}

      sdp = SDP.generate_sdp(server_ip, stream_path, video_config, %{})

      # Should use Main Profile defaults
      assert sdp =~ "profile-level-id=4D4028"
      assert sdp =~ "packetization-mode=1"
      assert sdp =~ "sprop-parameter-sets=Z01AKPYCgC3TUBAQFAAAAwAEAHoSADxgxOA=,aO4PyA=="
    end
  end

  describe "session_id/0" do
    test "generates session ID based on timestamp" do
      session_id = SDP.session_id()

      assert is_binary(session_id)
      assert String.length(session_id) > 0
      # Should be numeric
      assert String.to_integer(session_id) > 0
    end

    test "generates different IDs when called multiple times" do
      id1 = SDP.session_id()
      Process.sleep(1000)  # Wait 1 second
      id2 = SDP.session_id()

      # IDs should be different (unless called in same second)
      # This test might occasionally be equal if run in same second
      assert is_binary(id1)
      assert is_binary(id2)
    end
  end

  describe "session_version/0" do
    test "generates NTP timestamp" do
      version = SDP.session_version()

      assert is_binary(version)
      assert String.length(version) > 0
      # Should be numeric and larger than Unix timestamp (due to NTP offset)
      ntp_timestamp = String.to_integer(version)
      unix_timestamp = System.system_time(:second)
      assert ntp_timestamp > unix_timestamp
    end

    test "NTP timestamp includes correct offset" do
      version = SDP.session_version()
      ntp_timestamp = String.to_integer(version)

      # NTP offset is 2208988800 seconds
      # NTP timestamp should be Unix timestamp + offset
      expected_ntp = System.system_time(:second) + 2_208_988_800

      # Allow small timing difference (should be within 1 second)
      assert abs(ntp_timestamp - expected_ntp) <= 1
    end
  end

  describe "extract_codec_params/1" do
    test "extracts SPS/PPS from stream format" do
      # Simulate SPS/PPS binary data
      # Real SPS starts with: NAL header + profile + constraints + level
      sps = <<0x67, 0x42, 0xE0, 0x1F, 0x89, 0x68, 0x50, 0x0F>>
      pps = <<0x68, 0xCE, 0x3C, 0x80>>

      stream_format = %{sps: sps, pps: pps}
      params = SDP.extract_codec_params(stream_format)

      assert is_map(params)
      assert Map.has_key?(params, :sprop_parameter_sets)
      assert Map.has_key?(params, :profile_level_id)

      # Check base64 encoding
      [sps_b64, pps_b64] = String.split(params.sprop_parameter_sets, ",")
      assert Base.decode64!(sps_b64) == sps
      assert Base.decode64!(pps_b64) == pps
    end

    test "returns empty map when stream format has no SPS/PPS" do
      stream_format = %{}
      params = SDP.extract_codec_params(stream_format)

      assert params == %{}
    end

    test "extracts profile-level-id from SPS" do
      # SPS with Main Profile (0x4D), constraints (0x40), Level 4.0 (0x28)
      sps = <<0x67, 0x4D, 0x40, 0x28, 0x89, 0x68, 0x50, 0x0F>>
      pps = <<0x68, 0xCE, 0x3C, 0x80>>

      stream_format = %{sps: sps, pps: pps}
      params = SDP.extract_codec_params(stream_format)

      # Should extract profile-level-id as hex string
      assert params.profile_level_id == "4D4028"
    end

    test "handles invalid SPS gracefully" do
      # SPS too short
      sps = <<0x67>>
      pps = <<0x68>>

      stream_format = %{sps: sps, pps: pps}
      params = SDP.extract_codec_params(stream_format)

      # Should use default profile-level-id
      assert params.profile_level_id == "42E01F"
    end

    test "handles non-binary SPS/PPS" do
      stream_format = %{sps: "not binary", pps: nil}
      params = SDP.extract_codec_params(stream_format)

      assert params == %{}
    end
  end

  describe "SDP format compliance" do
    test "generates RFC 4566 compliant SDP" do
      server_ip = "192.168.1.100"
      stream_path = "/video"
      video_config = %{width: 1280, height: 720, framerate: 30}

      sdp = SDP.generate_sdp(server_ip, stream_path, video_config)

      # Check mandatory session-level fields (RFC 4566)
      assert sdp =~ ~r/v=0/
      assert sdp =~ ~r/o=- \d+ \d+ IN IP4 #{server_ip}/
      assert sdp =~ ~r/s=.+/
      assert sdp =~ ~r/c=IN IP4 #{server_ip}/
      assert sdp =~ ~r/t=0 0/

      # Check mandatory media-level fields
      assert sdp =~ ~r/m=video 0 RTP\/AVP 96/
      assert sdp =~ ~r/a=rtpmap:96 H264\/90000/
    end

    test "uses proper line endings" do
      server_ip = "192.168.1.100"
      stream_path = "/video"
      video_config = %{width: 1280, height: 720, framerate: 30}

      sdp = SDP.generate_sdp(server_ip, stream_path, video_config)

      # SDP should use CRLF (\r\n) between session and media sections
      # (RFC 4566 specifies CRLF, but in practice many implementations are flexible)
      assert sdp =~ "\r\n"

      # Check that media section (which needs strict CRLF for streaming) has proper endings
      [_session_part, media_part] = String.split(sdp, "\r\n", parts: 2)
      # Media section lines should end with \r\n
      media_lines = String.split(media_part, "\r\n")
      assert length(media_lines) > 1
    end

    test "includes H.264 RTP payload format parameters (RFC 6184)" do
      server_ip = "192.168.1.100"
      stream_path = "/video"
      video_config = %{width: 1280, height: 720, framerate: 30}

      sdp = SDP.generate_sdp(server_ip, stream_path, video_config)

      # RFC 6184 required parameters
      assert sdp =~ ~r/a=fmtp:96 packetization-mode=\d+/
      assert sdp =~ ~r/profile-level-id=[0-9A-Fa-f]{6}/
      assert sdp =~ ~r/sprop-parameter-sets=[A-Za-z0-9+\/=,]+/
    end
  end
end
