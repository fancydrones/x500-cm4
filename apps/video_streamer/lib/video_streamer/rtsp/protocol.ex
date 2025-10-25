defmodule VideoStreamer.RTSP.Protocol do
  @moduledoc """
  RTSP protocol parser and response builder.
  Implements RFC 2326 (RTSP 1.0) for video streaming.

  Supported methods:
  - OPTIONS: Query supported methods
  - DESCRIBE: Get session description (SDP)
  - SETUP: Establish transport parameters
  - PLAY: Start streaming
  - TEARDOWN: End session
  """

  require Logger

  @rtsp_version "RTSP/1.0"
  @server_name "VideoStreamer/0.1.0"

  @type request :: %{
          method: String.t(),
          uri: String.t(),
          version: String.t(),
          headers: %{String.t() => String.t()},
          body: String.t()
        }

  @type response :: %{
          status: integer(),
          reason: String.t(),
          headers: %{String.t() => String.t()},
          body: String.t()
        }

  ## Request Parsing

  @doc """
  Parse RTSP request from raw socket data.

  ## Examples

      iex> parse_request("OPTIONS rtsp://localhost:8554/video RTSP/1.0\\r\\nCSeq: 1\\r\\n\\r\\n")
      {:ok, %{method: "OPTIONS", uri: "rtsp://localhost:8554/video", ...}}
  """
  @spec parse_request(binary()) :: {:ok, request()} | {:error, term()}
  def parse_request(data) do
    case String.split(data, "\r\n\r\n", parts: 2) do
      [headers_section, body] ->
        parse_request_with_body(headers_section, body)

      [headers_section] ->
        parse_request_with_body(headers_section, "")

      _ ->
        {:error, :invalid_request}
    end
  end

  defp parse_request_with_body(headers_section, body) do
    lines = String.split(headers_section, "\r\n")

    case lines do
      [request_line | header_lines] ->
        with {:ok, method, uri, version} <- parse_request_line(request_line),
             {:ok, headers} <- parse_headers(header_lines) do
          {:ok,
           %{
             method: method,
             uri: uri,
             version: version,
             headers: headers,
             body: body
           }}
        end

      _ ->
        {:error, :invalid_request}
    end
  end

  defp parse_request_line(line) do
    case String.split(line, " ", parts: 3) do
      [method, uri, version] ->
        {:ok, method, uri, version}

      _ ->
        {:error, :invalid_request_line}
    end
  end

  defp parse_headers(lines) do
    headers =
      lines
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&parse_header/1)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    {:ok, headers}
  end

  defp parse_header(line) do
    case String.split(line, ":", parts: 2) do
      [key, value] ->
        {String.trim(key), String.trim(value)}

      _ ->
        nil
    end
  end

  ## Response Building

  @doc """
  Build OPTIONS response.
  Lists all supported RTSP methods.
  """
  @spec build_options_response(String.t()) :: response()
  def build_options_response(cseq) do
    %{
      status: 200,
      reason: "OK",
      headers: %{
        "CSeq" => cseq,
        "Public" => "OPTIONS, DESCRIBE, SETUP, PLAY, TEARDOWN",
        "Server" => @server_name
      },
      body: ""
    }
  end

  @doc """
  Build DESCRIBE response with SDP body.
  """
  @spec build_describe_response(String.t(), String.t()) :: response()
  def build_describe_response(cseq, sdp_body) do
    %{
      status: 200,
      reason: "OK",
      headers: %{
        "CSeq" => cseq,
        "Content-Type" => "application/sdp",
        "Content-Length" => to_string(byte_size(sdp_body)),
        "Server" => @server_name
      },
      body: sdp_body
    }
  end

  @doc """
  Build SETUP response with transport and session information.
  """
  @spec build_setup_response(String.t(), String.t(), map()) :: response()
  def build_setup_response(cseq, session_id, transport_params) do
    # Build transport header from params
    # Example: "RTP/AVP;unicast;client_port=50000-50001;server_port=50002-50003"
    transport = build_transport_header(transport_params)

    %{
      status: 200,
      reason: "OK",
      headers: %{
        "CSeq" => cseq,
        "Session" => "#{session_id};timeout=60",
        "Transport" => transport,
        "Server" => @server_name
      },
      body: ""
    }
  end

  @doc """
  Build PLAY response to start streaming.
  """
  @spec build_play_response(String.t(), String.t()) :: response()
  def build_play_response(cseq, session_id) do
    %{
      status: 200,
      reason: "OK",
      headers: %{
        "CSeq" => cseq,
        "Session" => session_id,
        "RTP-Info" => "url=rtsp://localhost:8554/video/trackID=0",
        "Server" => @server_name
      },
      body: ""
    }
  end

  @doc """
  Build TEARDOWN response to end session.
  """
  @spec build_teardown_response(String.t(), String.t()) :: response()
  def build_teardown_response(cseq, session_id) do
    %{
      status: 200,
      reason: "OK",
      headers: %{
        "CSeq" => cseq,
        "Session" => session_id,
        "Server" => @server_name
      },
      body: ""
    }
  end

  @doc """
  Build error response.
  """
  @spec build_error_response(String.t(), integer(), String.t()) :: response()
  def build_error_response(cseq, status, reason) do
    %{
      status: status,
      reason: reason,
      headers: %{
        "CSeq" => cseq,
        "Server" => @server_name
      },
      body: ""
    }
  end

  @doc """
  Serialize response to wire format.
  """
  @spec serialize_response(response()) :: binary()
  def serialize_response(%{status: status, reason: reason, headers: headers, body: body}) do
    status_line = "#{@rtsp_version} #{status} #{reason}\r\n"

    headers_text =
      headers
      |> Enum.map(fn {key, value} -> "#{key}: #{value}\r\n" end)
      |> Enum.join()

    status_line <> headers_text <> "\r\n" <> body
  end

  ## Helper Functions

  @doc """
  Extract CSeq header from request.
  """
  @spec get_cseq(request()) :: String.t() | nil
  def get_cseq(%{headers: headers}) do
    Map.get(headers, "CSeq")
  end

  @doc """
  Extract Session header from request.
  """
  @spec get_session(request()) :: String.t() | nil
  def get_session(%{headers: headers}) do
    case Map.get(headers, "Session") do
      nil -> nil
      session -> session |> String.split(";") |> List.first()
    end
  end

  @doc """
  Parse Transport header from SETUP request.
  Returns map with client_port_rtp, client_port_rtcp, etc.
  """
  @spec parse_transport_header(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_transport_header(transport_string) do
    parts = String.split(transport_string, ";")

    params =
      parts
      |> Enum.map(&String.trim/1)
      |> Enum.reduce(%{}, fn part, acc ->
        case String.split(part, "=", parts: 2) do
          ["client_port", ports] ->
            case String.split(ports, "-") do
              [rtp, rtcp] ->
                acc
                |> Map.put(:client_port_rtp, String.to_integer(rtp))
                |> Map.put(:client_port_rtcp, String.to_integer(rtcp))

              _ ->
                acc
            end

          [key, value] ->
            Map.put(acc, String.to_atom(key), value)

          [flag] ->
            Map.put(acc, String.to_atom(flag), true)
        end
      end)

    {:ok, params}
  rescue
    _ -> {:error, :invalid_transport}
  end

  @doc """
  Build Transport header response string from parameters.
  """
  @spec build_transport_header(map()) :: String.t()
  def build_transport_header(params) do
    parts = ["RTP/AVP", "unicast"]

    parts =
      if params[:client_port_rtp] && params[:client_port_rtcp] do
        client_ports = "client_port=#{params[:client_port_rtp]}-#{params[:client_port_rtcp]}"
        parts ++ [client_ports]
      else
        parts
      end

    parts =
      if params[:server_port_rtp] && params[:server_port_rtcp] do
        server_ports = "server_port=#{params[:server_port_rtp]}-#{params[:server_port_rtcp]}"
        parts ++ [server_ports]
      else
        parts
      end

    parts =
      if params[:ssrc] do
        parts ++ ["ssrc=#{params[:ssrc]}"]
      else
        parts
      end

    Enum.join(parts, ";")
  end
end
