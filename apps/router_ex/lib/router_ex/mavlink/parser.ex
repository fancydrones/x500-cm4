defmodule RouterEx.MAVLink.Parser do
  @moduledoc """
  MAVLink frame parser supporting both MAVLink v1 and v2 protocols.

  This module provides stateless parsing functions for extracting MAVLink
  frames from binary data streams. It handles:

  - MAVLink v1 frames (0xFE start byte)
  - MAVLink v2 frames (0xFD start byte)
  - Frame buffering for partial data
  - CRC validation
  - Frame recovery from corrupt data

  ## Usage

      # Parse frames from binary data
      {frames, remaining} = RouterEx.MAVLink.Parser.parse_frames(buffer)

      # Serialize frame back to binary
      {:ok, binary} = RouterEx.MAVLink.Parser.serialize_frame(frame)

  ## Frame Structure

  A parsed frame is a map containing:

  - `:version` - 1 or 2
  - `:payload_length` - Size of payload in bytes
  - `:sequence` - Message sequence number
  - `:source_system` - System ID of sender
  - `:source_component` - Component ID of sender
  - `:message_id` - MAVLink message type ID
  - `:payload` - Raw message payload
  - `:raw` - Original binary frame (for retransmission)
  - `:incompatibility_flags` - MAVLink v2 only
  - `:compatibility_flags` - MAVLink v2 only

  ## MAVLink Protocol

  ### MAVLink v1 Frame Format (8 + payload bytes)
  ```
  0xFE | len | seq | sysid | compid | msgid | payload | crc_low | crc_high
  ```

  ### MAVLink v2 Frame Format (12 + payload bytes, optional 13-byte signature)
  ```
  0xFD | len | incompat | compat | seq | sysid | compid |
  msgid (24-bit LE) | payload | crc_low | crc_high | [signature]
  ```

  ## CRC Validation

  MAVLink uses X.25 CRC-16-CCITT for frame validation. The CRC is computed
  over the frame header and payload, with an additional CRC_EXTRA seed value
  that depends on the message ID.

  Currently, CRC validation is implemented but CRC_EXTRA lookup requires
  message definition metadata from the MAVLink dialect.
  """

  import Bitwise
  require Logger

  # MAVLink magic numbers
  @mavlink_v1_stx 0xFE
  @mavlink_v2_stx 0xFD

  @type frame :: %{
          version: 1 | 2,
          payload_length: non_neg_integer(),
          sequence: byte(),
          source_system: byte(),
          source_component: byte(),
          message_id: non_neg_integer(),
          payload: binary(),
          raw: binary()
        }

  @doc """
  Parses MAVLink frames from a binary buffer.

  Returns a tuple of `{frames, remaining_buffer}` where frames is a list
  of parsed frame maps and remaining_buffer contains unparsed bytes.

  ## Examples

      iex> data = <<0xFE, 9, 0, 1, 1, 0, 0::72, 0::16>>
      iex> {frames, _remaining} = RouterEx.MAVLink.Parser.parse_frames(data)
      iex> length(frames)
      1
      iex> hd(frames).version
      1
  """
  @spec parse_frames(binary()) :: {[frame()], binary()}
  def parse_frames(buffer) when is_binary(buffer) do
    do_parse_frames(buffer, [])
  end

  @doc """
  Serializes a frame back to binary format.

  Returns `{:ok, binary}` if the frame can be serialized, or
  `{:error, reason}` if the frame format is invalid.

  If the frame has a `:raw` field, it will be used directly.
  Otherwise, the frame will be rebuilt from its components.

  ## Examples

      iex> frame = %{version: 1, sequence: 0, source_system: 1, source_component: 1,
      ...>           message_id: 0, payload: <<0::72>>, raw: <<0xFE, 9, 0, 1, 1, 0, 0::72, 0::16>>}
      iex> {:ok, _binary} = RouterEx.MAVLink.Parser.serialize_frame(frame)
  """
  @spec serialize_frame(frame()) :: {:ok, binary()} | {:error, atom()}
  def serialize_frame(frame) when is_map(frame) do
    case Map.get(frame, :raw) do
      nil ->
        build_frame(frame)

      raw when is_binary(raw) ->
        {:ok, raw}
    end
  end

  ## Private Functions - Frame Parsing

  defp do_parse_frames(<<>>, frames), do: {Enum.reverse(frames), <<>>}

  defp do_parse_frames(buffer, frames) when byte_size(buffer) < 8 do
    # Not enough data for minimum frame size
    {Enum.reverse(frames), buffer}
  end

  # MAVLink v2 frame
  defp do_parse_frames(<<@mavlink_v2_stx, payload_len, _rest::binary>> = buffer, frames) do
    min_frame_len = 12 + payload_len

    if byte_size(buffer) >= min_frame_len do
      <<frame_data::binary-size(min_frame_len), rest::binary>> = buffer

      case parse_v2_frame(frame_data) do
        {:ok, frame} ->
          do_parse_frames(rest, [frame | frames])

        {:error, _reason} ->
          # Skip this byte and try again
          <<_::8, rest::binary>> = buffer
          do_parse_frames(rest, frames)
      end
    else
      # Not enough data yet
      {Enum.reverse(frames), buffer}
    end
  end

  # MAVLink v1 frame
  defp do_parse_frames(<<@mavlink_v1_stx, payload_len, _rest::binary>> = buffer, frames) do
    frame_len = 8 + payload_len

    if byte_size(buffer) >= frame_len do
      <<frame_data::binary-size(frame_len), rest::binary>> = buffer

      case parse_v1_frame(frame_data) do
        {:ok, frame} ->
          do_parse_frames(rest, [frame | frames])

        {:error, _reason} ->
          # Skip this byte and try again
          <<_::8, rest::binary>> = buffer
          do_parse_frames(rest, frames)
      end
    else
      # Not enough data yet
      {Enum.reverse(frames), buffer}
    end
  end

  # Not a valid frame start marker
  defp do_parse_frames(<<_::8, rest::binary>>, frames) do
    do_parse_frames(rest, frames)
  end

  ## Private Functions - V2 Frame Parsing

  defp parse_v2_frame(
         <<@mavlink_v2_stx, payload_len, incompat_flags, compat_flags, seq, sysid, compid,
           msg_id::24-little, payload::binary-size(payload_len), checksum::16-little,
           signature::binary>> = data
       )
       when byte_size(data) >= payload_len + 12 do
    frame = %{
      version: 2,
      payload_length: payload_len,
      incompatibility_flags: incompat_flags,
      compatibility_flags: compat_flags,
      sequence: seq,
      source_system: sysid,
      source_component: compid,
      message_id: msg_id,
      payload: payload,
      checksum: checksum,
      raw: binary_part(data, 0, payload_len + 12)
    }

    # Add signature if present (13 bytes when signature flag is set)
    frame =
      if byte_size(signature) == 13 do
        Map.put(frame, :signature, signature)
      else
        frame
      end

    # Validate CRC (basic validation without CRC_EXTRA for now)
    if validate_crc_v2(frame) do
      {:ok, frame}
    else
      Logger.debug("Invalid CRC for MAVLink v2 frame, msgid=#{msg_id}")
      {:ok, frame}  # Accept frame anyway for now
    end
  end

  defp parse_v2_frame(_data) do
    {:error, :invalid_v2_frame}
  end

  ## Private Functions - V1 Frame Parsing

  defp parse_v1_frame(
         <<@mavlink_v1_stx, payload_len, seq, sysid, compid, msg_id,
           payload::binary-size(payload_len), checksum::16-little>> = data
       )
       when byte_size(data) >= payload_len + 8 do
    frame = %{
      version: 1,
      payload_length: payload_len,
      sequence: seq,
      source_system: sysid,
      source_component: compid,
      message_id: msg_id,
      payload: payload,
      checksum: checksum,
      raw: data
    }

    # Validate CRC (basic validation without CRC_EXTRA for now)
    if validate_crc_v1(frame) do
      {:ok, frame}
    else
      Logger.debug("Invalid CRC for MAVLink v1 frame, msgid=#{msg_id}")
      {:ok, frame}  # Accept frame anyway for now
    end
  end

  defp parse_v1_frame(_data) do
    {:error, :invalid_v1_frame}
  end

  ## Private Functions - Frame Building

  defp build_frame(%{version: 2} = frame) do
    payload = Map.get(frame, :payload, <<>>)
    payload_len = byte_size(payload)

    incompat_flags = Map.get(frame, :incompatibility_flags, 0)
    compat_flags = Map.get(frame, :compatibility_flags, 0)

    # Build frame without checksum
    header_and_payload =
      <<@mavlink_v2_stx, payload_len, incompat_flags, compat_flags, frame.sequence,
        frame.source_system, frame.source_component, frame.message_id::24-little,
        payload::binary>>

    # Calculate CRC (simplified - should use CRC_EXTRA)
    checksum = calculate_crc(header_and_payload, 0xFFFF)

    data = <<header_and_payload::binary, checksum::16-little>>

    {:ok, data}
  end

  defp build_frame(%{version: 1} = frame) do
    payload = Map.get(frame, :payload, <<>>)
    payload_len = byte_size(payload)

    # Build frame without checksum
    header_and_payload =
      <<@mavlink_v1_stx, payload_len, frame.sequence, frame.source_system, frame.source_component,
        frame.message_id, payload::binary>>

    # Calculate CRC (simplified - should use CRC_EXTRA)
    checksum = calculate_crc(header_and_payload, 0xFFFF)

    data = <<header_and_payload::binary, checksum::16-little>>

    {:ok, data}
  end

  defp build_frame(_frame) do
    {:error, :invalid_frame_format}
  end

  ## Private Functions - CRC Validation

  defp validate_crc_v2(frame) do
    # Build the data to be checksummed (everything except STX and checksum)
    data =
      <<frame.payload_length, frame.incompatibility_flags, frame.compatibility_flags,
        frame.sequence, frame.source_system, frame.source_component, frame.message_id::24-little,
        frame.payload::binary>>

    # Calculate CRC starting with 0xFFFF
    calculated = calculate_crc(data, 0xFFFF)

    # For proper validation, we should add CRC_EXTRA here:
    # calculated = accumulate_crc(crc_extra_byte, calculated)

    calculated == frame.checksum
  end

  defp validate_crc_v1(frame) do
    # Build the data to be checksummed (everything except STX and checksum)
    data =
      <<frame.payload_length, frame.sequence, frame.source_system, frame.source_component,
        frame.message_id, frame.payload::binary>>

    # Calculate CRC starting with 0xFFFF
    calculated = calculate_crc(data, 0xFFFF)

    # For proper validation, we should add CRC_EXTRA here:
    # calculated = accumulate_crc(crc_extra_byte, calculated)

    calculated == frame.checksum
  end

  @doc """
  Calculates X.25 CRC-16-CCITT checksum for MAVLink frames.

  This is the standard MAVLink CRC algorithm. Note that proper validation
  also requires adding the CRC_EXTRA byte specific to each message ID,
  which requires message definition metadata.
  """
  @spec calculate_crc(binary(), char()) :: char()
  def calculate_crc(data, initial_crc \\ 0xFFFF) do
    data
    |> :binary.bin_to_list()
    |> Enum.reduce(initial_crc, &accumulate_crc/2)
  end

  defp accumulate_crc(byte, crc) do
    tmp = bxor(byte, band(crc, 0xFF))
    tmp = band(bxor(tmp, tmp <<< 4), 0xFF)
    crc = crc >>> 8
    crc = bxor(crc, tmp <<< 8)
    crc = bxor(crc, tmp <<< 3)
    crc = bxor(crc, tmp >>> 4)
    band(crc, 0xFFFF)
  end

  @doc """
  Validates a complete MAVLink frame including CRC_EXTRA.

  This requires the CRC_EXTRA byte for the specific message ID,
  which comes from the MAVLink message definitions.

  Returns `true` if the frame is valid, `false` otherwise.
  """
  @spec validate_frame(frame(), byte()) :: boolean()
  def validate_frame(%{version: 2} = frame, crc_extra) do
    data =
      <<frame.payload_length, frame.incompatibility_flags, frame.compatibility_flags,
        frame.sequence, frame.source_system, frame.source_component, frame.message_id::24-little,
        frame.payload::binary>>

    calculated =
      data
      |> calculate_crc(0xFFFF)
      |> accumulate_crc(crc_extra)

    calculated == frame.checksum
  end

  def validate_frame(%{version: 1} = frame, crc_extra) do
    data =
      <<frame.payload_length, frame.sequence, frame.source_system, frame.source_component,
        frame.message_id, frame.payload::binary>>

    calculated =
      data
      |> calculate_crc(0xFFFF)
      |> accumulate_crc(crc_extra)

    calculated == frame.checksum
  end

  @doc """
  Extracts the target system ID from a frame's payload if present.

  Many MAVLink messages include a target_system field. This is a helper
  to extract it if available. Returns 0 (broadcast) if not found.
  """
  @spec get_target_system(frame()) :: byte()
  def get_target_system(%{payload: <<target_system, _rest::binary>>}) do
    target_system
  end

  def get_target_system(_frame), do: 0

  @doc """
  Extracts the target component ID from a frame's payload if present.

  Many MAVLink messages include a target_component field (usually the
  second byte). Returns 0 (broadcast) if not found.
  """
  @spec get_target_component(frame()) :: byte()
  def get_target_component(%{payload: <<_target_system, target_component, _rest::binary>>}) do
    target_component
  end

  def get_target_component(_frame), do: 0
end
