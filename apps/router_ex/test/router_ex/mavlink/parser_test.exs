defmodule RouterEx.MAVLink.ParserTest do
  use ExUnit.Case, async: true

  alias RouterEx.MAVLink.Parser

  @moduletag :mavlink_parser

  describe "MAVLink v1 frame parsing" do
    test "parses valid MAVLink v1 HEARTBEAT frame" do
      # MAVLink v1 HEARTBEAT (msgid=0) frame
      # STX=0xFE, len=9, seq=0, sysid=1, compid=1, msgid=0
      # payload=9 bytes of zeros
      payload = <<0::72>>
      crc = Parser.calculate_crc(<<9, 0, 1, 1, 0, payload::binary>>, 0xFFFF)

      frame_data = <<0xFE, 9, 0, 1, 1, 0, payload::binary, crc::16-little>>

      {frames, remaining} = Parser.parse_frames(frame_data)

      assert length(frames) == 1
      assert remaining == <<>>

      frame = hd(frames)
      assert frame.version == 1
      assert frame.payload_length == 9
      assert frame.sequence == 0
      assert frame.source_system == 1
      assert frame.source_component == 1
      assert frame.message_id == 0
      assert frame.payload == payload
      assert frame.raw == frame_data
    end

    test "parses MAVLink v1 frame with non-zero sequence" do
      payload = <<1, 2, 3, 4, 5>>
      payload_len = byte_size(payload)

      crc = Parser.calculate_crc(<<payload_len, 42, 1, 1, 33, payload::binary>>, 0xFFFF)
      frame_data = <<0xFE, payload_len, 42, 1, 1, 33, payload::binary, crc::16-little>>

      {frames, remaining} = Parser.parse_frames(frame_data)

      assert length(frames) == 1
      assert remaining == <<>>

      frame = hd(frames)
      assert frame.version == 1
      assert frame.sequence == 42
      assert frame.message_id == 33
    end

    test "handles partial MAVLink v1 frame (incomplete)" do
      # Only first 5 bytes of frame
      partial_data = <<0xFE, 9, 0, 1, 1>>

      {frames, remaining} = Parser.parse_frames(partial_data)

      assert frames == []
      assert remaining == partial_data
    end

    test "parses multiple MAVLink v1 frames in sequence" do
      # Frame 1
      payload1 = <<1, 2, 3>>
      crc1 = Parser.calculate_crc(<<3, 0, 1, 1, 0, payload1::binary>>, 0xFFFF)
      frame1 = <<0xFE, 3, 0, 1, 1, 0, payload1::binary, crc1::16-little>>

      # Frame 2
      payload2 = <<4, 5, 6, 7>>
      crc2 = Parser.calculate_crc(<<4, 1, 2, 2, 1, payload2::binary>>, 0xFFFF)
      frame2 = <<0xFE, 4, 1, 2, 2, 1, payload2::binary, crc2::16-little>>

      combined = <<frame1::binary, frame2::binary>>

      {frames, remaining} = Parser.parse_frames(combined)

      assert length(frames) == 2
      assert remaining == <<>>

      [f1, f2] = frames
      assert f1.sequence == 0
      assert f1.message_id == 0
      assert f2.sequence == 1
      assert f2.message_id == 1
    end

    test "recovers from garbage data before valid frame" do
      payload = <<1, 2, 3>>
      crc = Parser.calculate_crc(<<3, 0, 1, 1, 0, payload::binary>>, 0xFFFF)
      valid_frame = <<0xFE, 3, 0, 1, 1, 0, payload::binary, crc::16-little>>

      # Garbage data followed by valid frame
      data = <<0xFF, 0xAA, 0xBB, 0xCC, valid_frame::binary>>

      {frames, remaining} = Parser.parse_frames(data)

      assert length(frames) == 1
      assert remaining == <<>>

      frame = hd(frames)
      assert frame.version == 1
    end
  end

  describe "MAVLink v2 frame parsing" do
    test "parses valid MAVLink v2 HEARTBEAT frame" do
      # MAVLink v2 HEARTBEAT (msgid=0) frame
      # STX=0xFD, len=9, incompat=0, compat=0, seq=0, sysid=1, compid=1, msgid=0
      payload = <<0::72>>

      crc =
        Parser.calculate_crc(<<9, 0, 0, 0, 1, 1, 0::24-little, payload::binary>>, 0xFFFF)

      frame_data = <<0xFD, 9, 0, 0, 0, 1, 1, 0::24-little, payload::binary, crc::16-little>>

      {frames, remaining} = Parser.parse_frames(frame_data)

      assert length(frames) == 1
      assert remaining == <<>>

      frame = hd(frames)
      assert frame.version == 2
      assert frame.payload_length == 9
      assert frame.incompatibility_flags == 0
      assert frame.compatibility_flags == 0
      assert frame.sequence == 0
      assert frame.source_system == 1
      assert frame.source_component == 1
      assert frame.message_id == 0
      assert frame.payload == payload
      assert byte_size(frame.raw) == 21
    end

    test "parses MAVLink v2 frame with 24-bit message ID" do
      # Test with larger message ID (e.g., 322 = 0x0142)
      payload = <<1, 2, 3, 4>>
      msg_id = 322

      crc =
        Parser.calculate_crc(<<4, 0, 0, 5, 1, 1, msg_id::24-little, payload::binary>>, 0xFFFF)

      frame_data = <<0xFD, 4, 0, 0, 5, 1, 1, msg_id::24-little, payload::binary, crc::16-little>>

      {frames, _remaining} = Parser.parse_frames(frame_data)

      assert length(frames) == 1
      frame = hd(frames)
      assert frame.message_id == 322
      assert frame.sequence == 5
    end

    test "handles partial MAVLink v2 frame (incomplete)" do
      # Only first 10 bytes of frame (needs at least 12 + payload_len)
      partial_data = <<0xFD, 9, 0, 0, 0, 1, 1, 0::24-little>>

      {frames, remaining} = Parser.parse_frames(partial_data)

      assert frames == []
      assert remaining == partial_data
    end

    test "parses multiple MAVLink v2 frames in sequence" do
      # Frame 1
      payload1 = <<1, 2>>
      crc1 = Parser.calculate_crc(<<2, 0, 0, 0, 1, 1, 0::24-little, payload1::binary>>, 0xFFFF)
      frame1 = <<0xFD, 2, 0, 0, 0, 1, 1, 0::24-little, payload1::binary, crc1::16-little>>

      # Frame 2
      payload2 = <<3, 4, 5>>
      crc2 = Parser.calculate_crc(<<3, 0, 0, 1, 2, 2, 1::24-little, payload2::binary>>, 0xFFFF)
      frame2 = <<0xFD, 3, 0, 0, 1, 2, 2, 1::24-little, payload2::binary, crc2::16-little>>

      combined = <<frame1::binary, frame2::binary>>

      {frames, remaining} = Parser.parse_frames(combined)

      assert length(frames) == 2
      assert remaining == <<>>

      [f1, f2] = frames
      assert f1.message_id == 0
      assert f2.message_id == 1
    end

    test "recovers from garbage data before valid MAVLink v2 frame" do
      payload = <<1, 2, 3>>
      crc = Parser.calculate_crc(<<3, 0, 0, 0, 1, 1, 0::24-little, payload::binary>>, 0xFFFF)
      valid_frame = <<0xFD, 3, 0, 0, 0, 1, 1, 0::24-little, payload::binary, crc::16-little>>

      # Garbage data followed by valid frame
      data = <<0xFF, 0xAA, 0xBB, 0xCC, valid_frame::binary>>

      {frames, _remaining} = Parser.parse_frames(data)

      assert length(frames) == 1
      frame = hd(frames)
      assert frame.version == 2
    end
  end

  describe "mixed v1 and v2 frame parsing" do
    test "parses mix of MAVLink v1 and v2 frames" do
      # V1 frame
      payload_v1 = <<1, 2>>
      crc_v1 = Parser.calculate_crc(<<2, 0, 1, 1, 0, payload_v1::binary>>, 0xFFFF)
      frame_v1 = <<0xFE, 2, 0, 1, 1, 0, payload_v1::binary, crc_v1::16-little>>

      # V2 frame
      payload_v2 = <<3, 4>>
      crc_v2 = Parser.calculate_crc(<<2, 0, 0, 1, 2, 2, 1::24-little, payload_v2::binary>>, 0xFFFF)
      frame_v2 = <<0xFD, 2, 0, 0, 1, 2, 2, 1::24-little, payload_v2::binary, crc_v2::16-little>>

      combined = <<frame_v1::binary, frame_v2::binary>>

      {frames, remaining} = Parser.parse_frames(combined)

      assert length(frames) == 2
      assert remaining == <<>>

      [f1, f2] = frames
      assert f1.version == 1
      assert f2.version == 2
    end
  end

  describe "frame serialization" do
    test "serializes MAVLink v1 frame using raw field" do
      payload = <<1, 2, 3>>
      crc = Parser.calculate_crc(<<3, 0, 1, 1, 0, payload::binary>>, 0xFFFF)
      raw_data = <<0xFE, 3, 0, 1, 1, 0, payload::binary, crc::16-little>>

      frame = %{
        version: 1,
        payload_length: 3,
        sequence: 0,
        source_system: 1,
        source_component: 1,
        message_id: 0,
        payload: payload,
        raw: raw_data
      }

      assert {:ok, raw_data} == Parser.serialize_frame(frame)
    end

    test "serializes MAVLink v2 frame using raw field" do
      payload = <<1, 2, 3>>
      crc = Parser.calculate_crc(<<3, 0, 0, 0, 1, 1, 0::24-little, payload::binary>>, 0xFFFF)
      raw_data = <<0xFD, 3, 0, 0, 0, 1, 1, 0::24-little, payload::binary, crc::16-little>>

      frame = %{
        version: 2,
        payload_length: 3,
        incompatibility_flags: 0,
        compatibility_flags: 0,
        sequence: 0,
        source_system: 1,
        source_component: 1,
        message_id: 0,
        payload: payload,
        raw: raw_data
      }

      assert {:ok, raw_data} == Parser.serialize_frame(frame)
    end

    test "rebuilds MAVLink v1 frame from components" do
      frame = %{
        version: 1,
        sequence: 5,
        source_system: 1,
        source_component: 1,
        message_id: 0,
        payload: <<1, 2, 3>>
      }

      assert {:ok, binary} = Parser.serialize_frame(frame)

      # Parse it back
      {frames, _} = Parser.parse_frames(binary)
      assert length(frames) == 1

      parsed_frame = hd(frames)
      assert parsed_frame.version == 1
      assert parsed_frame.sequence == 5
      assert parsed_frame.message_id == 0
    end

    test "rebuilds MAVLink v2 frame from components" do
      frame = %{
        version: 2,
        sequence: 10,
        source_system: 2,
        source_component: 1,
        message_id: 322,
        payload: <<1, 2, 3, 4>>
      }

      assert {:ok, binary} = Parser.serialize_frame(frame)

      # Parse it back
      {frames, _} = Parser.parse_frames(binary)
      assert length(frames) == 1

      parsed_frame = hd(frames)
      assert parsed_frame.version == 2
      assert parsed_frame.sequence == 10
      assert parsed_frame.message_id == 322
    end

    test "returns error for invalid frame format" do
      frame = %{invalid: :frame}

      assert {:error, :invalid_frame_format} == Parser.serialize_frame(frame)
    end
  end

  describe "CRC calculation" do
    test "calculates X.25 CRC-16-CCITT correctly" do
      # Test with known data
      data = <<1, 2, 3, 4, 5>>
      crc = Parser.calculate_crc(data, 0xFFFF)

      # CRC should be deterministic
      assert is_integer(crc)
      assert crc >= 0 and crc <= 0xFFFF

      # Same data should produce same CRC
      crc2 = Parser.calculate_crc(data, 0xFFFF)
      assert crc == crc2
    end

    test "calculates different CRC for different data" do
      crc1 = Parser.calculate_crc(<<1, 2, 3>>, 0xFFFF)
      crc2 = Parser.calculate_crc(<<1, 2, 4>>, 0xFFFF)

      assert crc1 != crc2
    end

    test "handles empty data" do
      crc = Parser.calculate_crc(<<>>, 0xFFFF)
      assert crc == 0xFFFF
    end
  end

  describe "frame validation with CRC_EXTRA" do
    test "validates MAVLink v1 frame with correct CRC_EXTRA" do
      # Create a frame with known CRC_EXTRA
      payload = <<1, 2, 3>>
      crc_extra = 50

      # Build header data for CRC calculation
      data = <<3, 0, 1, 1, 0, payload::binary>>

      # Calculate CRC with CRC_EXTRA
      # First calculate CRC over the data, then over the CRC_EXTRA byte
      crc_intermediate = Parser.calculate_crc(data, 0xFFFF)
      crc = Parser.calculate_crc(<<crc_extra>>, crc_intermediate)

      frame = %{
        version: 1,
        payload_length: 3,
        sequence: 0,
        source_system: 1,
        source_component: 1,
        message_id: 0,
        payload: payload,
        checksum: crc
      }

      assert Parser.validate_frame(frame, crc_extra) == true
    end

    test "validates MAVLink v2 frame with correct CRC_EXTRA" do
      # Create a frame with known CRC_EXTRA
      payload = <<1, 2, 3>>
      crc_extra = 50

      # Build header data for CRC calculation
      data = <<3, 0, 0, 0, 1, 1, 0::24-little, payload::binary>>

      # Calculate CRC with CRC_EXTRA
      # First calculate CRC over the data, then over the CRC_EXTRA byte
      crc_intermediate = Parser.calculate_crc(data, 0xFFFF)
      crc = Parser.calculate_crc(<<crc_extra>>, crc_intermediate)

      frame = %{
        version: 2,
        payload_length: 3,
        incompatibility_flags: 0,
        compatibility_flags: 0,
        sequence: 0,
        source_system: 1,
        source_component: 1,
        message_id: 0,
        payload: payload,
        checksum: crc
      }

      assert Parser.validate_frame(frame, crc_extra) == true
    end

    test "rejects frame with incorrect CRC_EXTRA" do
      payload = <<1, 2, 3>>
      crc_extra_correct = 50
      crc_extra_wrong = 51

      data = <<3, 0, 1, 1, 0, payload::binary>>

      # Calculate CRC with correct CRC_EXTRA
      crc_intermediate = Parser.calculate_crc(data, 0xFFFF)
      crc = Parser.calculate_crc(<<crc_extra_correct>>, crc_intermediate)

      frame = %{
        version: 1,
        payload_length: 3,
        sequence: 0,
        source_system: 1,
        source_component: 1,
        message_id: 0,
        payload: payload,
        checksum: crc
      }

      # Validate with wrong CRC_EXTRA should fail
      assert Parser.validate_frame(frame, crc_extra_wrong) == false
    end
  end

  describe "target extraction helpers" do
    test "extracts target_system from payload" do
      frame = %{
        version: 1,
        message_id: 0,
        payload: <<5, 10, 15, 20>>
      }

      assert Parser.get_target_system(frame) == 5
    end

    test "extracts target_component from payload" do
      frame = %{
        version: 1,
        message_id: 0,
        payload: <<5, 10, 15, 20>>
      }

      assert Parser.get_target_component(frame) == 10
    end

    test "returns 0 for target_system when payload too short" do
      frame = %{
        version: 1,
        message_id: 0,
        payload: <<>>
      }

      assert Parser.get_target_system(frame) == 0
    end

    test "returns 0 for target_component when payload too short" do
      frame = %{
        version: 1,
        message_id: 0,
        payload: <<5>>
      }

      assert Parser.get_target_component(frame) == 0
    end

    test "returns 0 for target_system when no payload field" do
      frame = %{
        version: 1,
        message_id: 0
      }

      assert Parser.get_target_system(frame) == 0
    end
  end

  describe "edge cases and error handling" do
    test "handles empty buffer" do
      {frames, remaining} = Parser.parse_frames(<<>>)

      assert frames == []
      assert remaining == <<>>
    end

    test "handles buffer smaller than minimum frame size" do
      {frames, remaining} = Parser.parse_frames(<<0xFE, 0x09, 0x00>>)

      assert frames == []
      assert remaining == <<0xFE, 0x09, 0x00>>
    end

    test "handles frame with zero-length payload" do
      # V1 frame with no payload
      crc = Parser.calculate_crc(<<0, 0, 1, 1, 0>>, 0xFFFF)
      frame_data = <<0xFE, 0, 0, 1, 1, 0, crc::16-little>>

      {frames, remaining} = Parser.parse_frames(frame_data)

      assert length(frames) == 1
      assert remaining == <<>>

      frame = hd(frames)
      assert frame.payload_length == 0
      assert frame.payload == <<>>
    end

    test "handles frame with maximum payload length (255 bytes)" do
      payload = :binary.copy(<<0xFF>>, 255)
      crc = Parser.calculate_crc(<<255, 0, 1, 1, 0, payload::binary>>, 0xFFFF)
      frame_data = <<0xFE, 255, 0, 1, 1, 0, payload::binary, crc::16-little>>

      {frames, remaining} = Parser.parse_frames(frame_data)

      assert length(frames) == 1
      assert remaining == <<>>

      frame = hd(frames)
      assert frame.payload_length == 255
      assert byte_size(frame.payload) == 255
    end

    test "skips invalid start bytes and continues parsing" do
      payload = <<1, 2, 3>>
      crc = Parser.calculate_crc(<<3, 0, 1, 1, 0, payload::binary>>, 0xFFFF)
      valid_frame = <<0xFE, 3, 0, 1, 1, 0, payload::binary, crc::16-little>>

      # Multiple garbage bytes followed by valid frame
      data = <<0x00, 0x01, 0x02, 0xAB, 0xCD, valid_frame::binary>>

      {frames, remaining} = Parser.parse_frames(data)

      assert length(frames) == 1
      assert remaining == <<>>
    end

    test "handles interleaved garbage between frames" do
      # Frame 1
      payload1 = <<1, 2>>
      crc1 = Parser.calculate_crc(<<2, 0, 1, 1, 0, payload1::binary>>, 0xFFFF)
      frame1 = <<0xFE, 2, 0, 1, 1, 0, payload1::binary, crc1::16-little>>

      # Frame 2
      payload2 = <<3, 4>>
      crc2 = Parser.calculate_crc(<<2, 1, 1, 1, 1, payload2::binary>>, 0xFFFF)
      frame2 = <<0xFE, 2, 1, 1, 1, 1, payload2::binary, crc2::16-little>>

      # Frames with garbage in between
      data = <<frame1::binary, 0xFF, 0xAA, frame2::binary>>

      {frames, remaining} = Parser.parse_frames(data)

      assert length(frames) == 2
      assert remaining == <<>>
    end

    test "preserves partial frame at end of buffer" do
      payload = <<1, 2, 3>>
      crc = Parser.calculate_crc(<<3, 0, 1, 1, 0, payload::binary>>, 0xFFFF)
      complete_frame = <<0xFE, 3, 0, 1, 1, 0, payload::binary, crc::16-little>>
      partial_frame = <<0xFE, 5, 0, 1, 1>>

      data = <<complete_frame::binary, partial_frame::binary>>

      {frames, remaining} = Parser.parse_frames(data)

      assert length(frames) == 1
      assert remaining == partial_frame
    end
  end
end
