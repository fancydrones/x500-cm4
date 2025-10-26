defmodule VideoAnnotator.WebPreview do
  @moduledoc """
  Simple web-based preview server for annotated video frames.

  Serves:
  - / - HTML page with live MJPEG stream
  - /stream - MJPEG stream of annotated frames
  - /stats - JSON stats about detection performance

  Access at http://localhost:4001
  """

  use Plug.Router
  require Logger

  plug :match
  plug :dispatch

  # Store latest frame in ETS
  @table_name :web_preview_frames

  # Implement child_spec for Supervisor compatibility
  def child_spec(port) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [port]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(port \\ 4001) do
    # Create ETS table for frame storage with frame counter
    :ets.new(@table_name, [:named_table, :public, :set])
    :ets.insert(@table_name, {:latest_frame, nil})
    :ets.insert(@table_name, {:frame_id, 0})  # Track frame updates
    :ets.insert(@table_name, {:stats, %{frame_count: 0, fps: 0, detections: 0}})

    Logger.info("Starting web preview server on http://localhost:#{port}")

    Bandit.start_link(
      plug: __MODULE__,
      scheme: :http,
      port: port
    )
  end

  def update_frame(jpeg_binary, stats \\ %{}) do
    # Increment frame ID to signal new frame available
    [{:frame_id, old_id}] = :ets.lookup(@table_name, :frame_id)
    :ets.insert(@table_name, {:latest_frame, jpeg_binary})
    :ets.insert(@table_name, {:frame_id, old_id + 1})
    :ets.insert(@table_name, {:stats, stats})
  end

  # HTML page with MJPEG viewer
  get "/" do
    html = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>Video Annotator - Live Preview</title>
      <style>
        body {
          margin: 0;
          padding: 20px;
          background: #1a1a1a;
          color: #fff;
          font-family: monospace;
        }
        .container {
          max-width: 1200px;
          margin: 0 auto;
        }
        h1 {
          color: #4CAF50;
        }
        .preview {
          background: #000;
          border: 2px solid #4CAF50;
          margin: 20px 0;
          display: inline-block;
        }
        img {
          display: block;
          max-width: 50%;
          height: auto;
        }
        .stats {
          background: #2a2a2a;
          padding: 15px;
          border-radius: 5px;
          margin: 20px 0;
        }
        .stats-row {
          margin: 5px 0;
        }
        .value {
          color: #4CAF50;
          font-weight: bold;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>🎥 Video Annotator - Live Preview</h1>
        <div class="preview">
          <img src="/stream" alt="Live video stream" />
        </div>
        <div class="stats">
          <h2>📊 Stats</h2>
          <div class="stats-row">FPS: <span class="value" id="fps">-</span></div>
          <div class="stats-row">Frames: <span class="value" id="frames">-</span></div>
          <div class="stats-row">Detections: <span class="value" id="detections">-</span></div>
        </div>
      </div>
      <script>
        // Update stats every second
        setInterval(async () => {
          try {
            const response = await fetch('/stats');
            const stats = await response.json();
            document.getElementById('fps').textContent = stats.fps.toFixed(1);
            document.getElementById('frames').textContent = stats.frame_count;
            document.getElementById('detections').textContent = stats.detections;
          } catch (e) {
            console.error('Failed to fetch stats:', e);
          }
        }, 1000);
      </script>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  # MJPEG stream endpoint
  get "/stream" do
    conn
    |> put_resp_content_type("multipart/x-mixed-replace; boundary=frame")
    |> send_chunked(200)
    |> stream_frames()
  end

  # Stats JSON endpoint
  get "/stats" do
    [{:stats, stats}] = :ets.lookup(@table_name, :stats)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(stats))
  end

  defp stream_frames(conn, last_frame_id \\ 0) do
    # Get current frame ID
    [{:frame_id, current_id}] = :ets.lookup(@table_name, :frame_id)

    if current_id > last_frame_id do
      # New frame available! Send it immediately
      case :ets.lookup(@table_name, :latest_frame) do
        [{:latest_frame, nil}] ->
          # Frame was cleared, wait and retry
          Process.sleep(10)
          stream_frames(conn, last_frame_id)

        [{:latest_frame, jpeg_binary}] ->
          # Send frame in MJPEG format
          frame_data = [
            "--frame\r\n",
            "Content-Type: image/jpeg\r\n",
            "Content-Length: #{byte_size(jpeg_binary)}\r\n\r\n",
            jpeg_binary,
            "\r\n"
          ]

          case chunk(conn, IO.iodata_to_binary(frame_data)) do
            {:ok, conn} ->
              # Continue with updated frame ID
              stream_frames(conn, current_id)

            {:error, :closed} ->
              conn
          end
      end
    else
      # No new frame yet, wait briefly and check again
      Process.sleep(10)
      stream_frames(conn, last_frame_id)
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
