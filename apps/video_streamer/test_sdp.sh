#!/bin/bash
# Simple script to get SDP from RTSP server

PI_IP="${1:-10.5.0.26}"
PORT="${2:-8554}"

echo "Getting SDP from rtsp://$PI_IP:$PORT/video"
echo ""

# Use netcat to send proper RTSP DESCRIBE
(
  echo "DESCRIBE rtsp://$PI_IP:$PORT/video RTSP/1.0"
  echo "CSeq: 1"
  echo "Accept: application/sdp"
  echo ""
) | nc $PI_IP $PORT

echo ""
echo "================================"
echo "To use: ./test_sdp.sh <pi-ip> <port>"
echo "Example: ./test_sdp.sh 10.5.0.26 8554"
