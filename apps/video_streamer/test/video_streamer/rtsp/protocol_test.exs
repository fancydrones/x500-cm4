defmodule VideoStreamer.RTSP.ProtocolTest do
  use ExUnit.Case, async: true
  alias VideoStreamer.RTSP.Protocol

  describe "parse_request/1" do
    test "parses OPTIONS request" do
      request = "OPTIONS rtsp://10.10.10.2:8554/video RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: VLC/3.0.18\r\n\r\n"

      assert {:ok, parsed} = Protocol.parse_request(request)
      assert parsed.method == "OPTIONS"
      assert parsed.uri == "rtsp://10.10.10.2:8554/video"
      assert parsed.version == "RTSP/1.0"
      assert parsed.headers["CSeq"] == "1"
      assert parsed.headers["User-Agent"] == "VLC/3.0.18"
      assert parsed.body == ""
    end

    test "parses DESCRIBE request" do
      request = "DESCRIBE rtsp://10.10.10.2:8554/video RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\n\r\n"

      assert {:ok, parsed} = Protocol.parse_request(request)
      assert parsed.method == "DESCRIBE"
      assert parsed.headers["Accept"] == "application/sdp"
    end

    test "parses SETUP request with Transport header" do
      request = "SETUP rtsp://10.10.10.2:8554/video RTSP/1.0\r\nCSeq: 3\r\nTransport: RTP/AVP;unicast;client_port=50000-50001\r\n\r\n"

      assert {:ok, parsed} = Protocol.parse_request(request)
      assert parsed.method == "SETUP"
      assert parsed.headers["Transport"] == "RTP/AVP;unicast;client_port=50000-50001"
    end

    test "parses PLAY request" do
      request = "PLAY rtsp://10.10.10.2:8554/video RTSP/1.0\r\nCSeq: 4\r\nSession: 12345678\r\n\r\n"

      assert {:ok, parsed} = Protocol.parse_request(request)
      assert parsed.method == "PLAY"
      assert parsed.headers["Session"] == "12345678"
    end

    test "parses TEARDOWN request" do
      request = "TEARDOWN rtsp://10.10.10.2:8554/video RTSP/1.0\r\nCSeq: 5\r\nSession: 12345678\r\n\r\n"

      assert {:ok, parsed} = Protocol.parse_request(request)
      assert parsed.method == "TEARDOWN"
      assert parsed.headers["Session"] == "12345678"
    end

    test "returns error for malformed request" do
      request = "INVALID REQUEST"
      assert {:error, _reason} = Protocol.parse_request(request)
    end

    test "handles request with body" do
      body = "test body content"
      request = "POST rtsp://10.10.10.2:8554/video RTSP/1.0\r\nCSeq: 1\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert {:ok, parsed} = Protocol.parse_request(request)
      assert parsed.method == "POST"
      assert parsed.body == body
    end
  end

  describe "build_options_response/1" do
    test "builds OPTIONS response with correct structure" do
      cseq = "1"
      response = Protocol.build_options_response(cseq)

      assert response.status == 200
      assert response.reason == "OK"
      assert response.headers["CSeq"] == "1"
      assert response.headers["Public"] =~ "OPTIONS"
      assert response.headers["Public"] =~ "DESCRIBE"
      assert response.headers["Public"] =~ "SETUP"
      assert response.headers["Public"] =~ "PLAY"
      assert response.headers["Public"] =~ "TEARDOWN"
      assert response.headers["Server"]
      assert response.body == ""
    end
  end

  describe "build_describe_response/2" do
    test "builds DESCRIBE response with SDP body" do
      cseq = "2"
      sdp = "v=0\r\no=- 0 0 IN IP4 10.10.10.2\r\ns=Video Stream\r\n"

      response = Protocol.build_describe_response(cseq, sdp)

      assert response.status == 200
      assert response.reason == "OK"
      assert response.headers["CSeq"] == "2"
      assert response.headers["Content-Type"] == "application/sdp"
      assert response.headers["Content-Length"] == to_string(byte_size(sdp))
      assert response.body == sdp
    end

    test "calculates correct content length" do
      cseq = "2"
      sdp = "test content with some length"

      response = Protocol.build_describe_response(cseq, sdp)

      assert response.headers["Content-Length"] == to_string(byte_size(sdp))
    end
  end

  describe "build_setup_response/3" do
    test "builds SETUP response with session and transport" do
      cseq = "3"
      session_id = "abcd1234"
      transport_params = %{
        protocol: "RTP/AVP",
        unicast: true,
        client_port: {50000, 50001},
        server_port: {5000, 5001}
      }

      response = Protocol.build_setup_response(cseq, session_id, transport_params)

      assert response.status == 200
      assert response.reason == "OK"
      assert response.headers["CSeq"] == "3"
      assert response.headers["Session"] =~ session_id
      assert response.headers["Transport"]
      assert response.body == ""
    end
  end

  describe "build_play_response/2" do
    test "builds PLAY response with RTP-Info" do
      cseq = "4"
      session_id = "abcd1234"

      response = Protocol.build_play_response(cseq, session_id)

      assert response.status == 200
      assert response.reason == "OK"
      assert response.headers["CSeq"] == "4"
      assert response.headers["Session"] == session_id
      assert response.headers["RTP-Info"]
    end
  end

  describe "build_teardown_response/2" do
    test "builds TEARDOWN response" do
      cseq = "5"
      session_id = "abcd1234"

      response = Protocol.build_teardown_response(cseq, session_id)

      assert response.status == 200
      assert response.reason == "OK"
      assert response.headers["CSeq"] == "5"
      assert response.headers["Session"] == session_id
    end
  end

  describe "build_error_response/3" do
    test "builds error response with custom status" do
      cseq = "1"
      status = 404
      reason = "Not Found"

      response = Protocol.build_error_response(cseq, status, reason)

      assert response.status == 404
      assert response.reason == "Not Found"
      assert response.headers["CSeq"] == "1"
    end

    test "builds 500 Internal Server Error" do
      response = Protocol.build_error_response("2", 500, "Internal Server Error")

      assert response.status == 500
      assert response.reason == "Internal Server Error"
    end
  end

  describe "serialize_response/1" do
    test "serializes response to wire format" do
      response = %{
        status: 200,
        reason: "OK",
        headers: %{
          "CSeq" => "1",
          "Server" => "TestServer"
        },
        body: ""
      }

      serialized = Protocol.serialize_response(response)

      assert serialized =~ "RTSP/1.0 200 OK"
      assert serialized =~ "CSeq: 1"
      assert serialized =~ "Server: TestServer"
      assert serialized =~ "\r\n\r\n"
    end

    test "serializes response with body" do
      body = "test body"
      response = %{
        status: 200,
        reason: "OK",
        headers: %{"CSeq" => "1"},
        body: body
      }

      serialized = Protocol.serialize_response(response)

      assert String.ends_with?(serialized, "\r\n\r\n#{body}")
    end

    test "includes all headers in wire format" do
      response = %{
        status: 200,
        reason: "OK",
        headers: %{
          "CSeq" => "1",
          "Content-Type" => "application/sdp",
          "Content-Length" => "100"
        },
        body: ""
      }

      serialized = Protocol.serialize_response(response)

      assert serialized =~ "CSeq: 1"
      assert serialized =~ "Content-Type: application/sdp"
      assert serialized =~ "Content-Length: 100"
    end
  end

  describe "get_cseq/1" do
    test "extracts CSeq from request" do
      request = %{headers: %{"CSeq" => "123"}}
      assert Protocol.get_cseq(request) == "123"
    end

    test "returns nil for missing CSeq" do
      request = %{headers: %{}}
      assert Protocol.get_cseq(request) == nil
    end
  end

  describe "get_session/1" do
    test "extracts Session from request" do
      request = %{headers: %{"Session" => "abcd1234"}}
      assert Protocol.get_session(request) == "abcd1234"
    end

    test "returns nil for missing Session" do
      request = %{headers: %{}}
      assert is_nil(Protocol.get_session(request))
    end
  end
end
