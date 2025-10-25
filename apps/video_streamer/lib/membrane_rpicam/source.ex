defmodule Membrane.Rpicam.Source do
  @moduledoc """
  Membrane Source Element for capturing live feed from a Raspberry Pi camera using rpicam-apps.

  This is an internalized and patched version of the membrane_rpicam_plugin to fix compatibility issues with
  newer Raspberry Pi OS and to add missing codec parameter.

  Original source: https://github.com/membraneframework/membrane_rpicam_plugin
  License: Apache 2.0

  Changes from original:
  - Added --codec h264 parameter to fix libav output format error
  - Updated to use rpicam-vid directly (newer Raspberry Pi OS standard)
  - Falls back to libcamera-vid for older systems
  """

  use Membrane.Source
  alias Membrane.{Buffer, H264, RemoteStream}
  require Membrane.Logger

  @app_name "rpicam-vid"
  @fallback_app_name "libcamera-vid"
  @max_retries 3

  def_output_pad(:output,
    accepted_format: %RemoteStream{type: :bytestream, content_format: H264},
    flow_control: :push
  )

  def_options(
    timeout: [
      spec: Membrane.Time.non_neg() | :infinity,
      default: :infinity,
      description: """
      Time for which program runs in milliseconds.
      """
    ],
    framerate: [
      spec: {pos_integer(), pos_integer()} | :camera_default,
      default: :camera_default,
      description: """
      Fixed framerate.
      """
    ],
    width: [
      spec: pos_integer() | :camera_default,
      default: :camera_default,
      description: """
      Output image width.
      """
    ],
    height: [
      spec: pos_integer() | :camera_default,
      default: :camera_default,
      description: """
      Output image height.
      """
    ],
    camera_open_delay: [
      spec: Membrane.Time.non_neg(),
      default: Membrane.Time.milliseconds(50),
      inspector: &Membrane.Time.pretty_duration/1,
      description: """
      Determines for how long initial opening the camera should be delayed.
      No delay can cause a crash on Nerves system when initializing the
      element during the boot sequence of the device.
      """
    ],
    verbose: [
      spec: boolean(),
      default: false,
      description: """
      Enable verbose output from rpicam-vid (frame statistics, exposure, gain, etc.).
      When false, suppresses the frame-by-frame debug output.
      """
    ],
    profile: [
      spec: :baseline | :main | :high,
      default: :main,
      description: """
      H.264 encoding profile (baseline, main, or high).
      Main profile provides better compression (~20% savings vs baseline).
      """
    ],
    level: [
      spec: String.t(),
      default: "4.1",
      description: """
      H.264 encoding level (e.g., "3.1", "4.0", "4.1").
      Level 4.1 supports up to 1080p30, level 3.1 supports up to 720p30.
      """
    ],
    bitrate: [
      spec: pos_integer() | :auto,
      default: :auto,
      description: """
      Target bitrate in bits per second. Set to :auto for automatic bitrate.
      For 720p30, recommend 2-3 Mbps for mobile devices.
      """
    ],
    keyframe_interval: [
      spec: pos_integer(),
      default: 60,
      description: """
      Keyframe interval in frames (GOP size / IDR period). MediaMTX uses 60 frames
      (2 seconds at 30fps) which provides smooth Android playback with less bandwidth.
      Matches MediaMTX rpiCameraIDRPeriod default.
      """
    ],
    inline_headers: [
      spec: boolean(),
      default: true,
      description: """
      Insert SPS/PPS before every keyframe for better mobile compatibility.
      """
    ],
    flush: [
      spec: boolean(),
      default: false,
      description: """
      Flush encoder output immediately. MediaMTX doesn't use flush mode and works
      well. Default false to match MediaMTX behavior and allow encoder buffering.
      """
    ],
    low_latency: [
      spec: boolean(),
      default: true,
      description: """
      Enable low-latency mode (rpicam-vid v1.6.0+). Reduces encoding latency from
      8 frames to 1 frame by disabling B-frames and arithmetic coding. Critical for
      eliminating keyframe jitter in real-time streaming. Recommended for all streaming.
      """
    ],
    hflip: [
      spec: boolean(),
      default: false,
      description: """
      Flip image horizontally (mirror).
      """
    ],
    vflip: [
      spec: boolean(),
      default: false,
      description: """
      Flip image vertically (upside down).
      """
    ]
  )

  @impl true
  def handle_init(_ctx, options) do
    Process.sleep(Membrane.Time.as_milliseconds(options.camera_open_delay, :round))

    # Detect which camera binary is available
    app_binary = detect_camera_binary()
    Membrane.Logger.info("Using camera binary: #{app_binary}")

    state = %{
      app_port: nil,
      init_time: nil,
      camera_open: false,
      retries: 0,
      options: options,
      app_binary: app_binary
    }

    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, %RemoteStream{type: :bytestream, content_format: H264}}],
     %{state | app_port: open_port(state.options, state.app_binary)}}
  end

  @impl true
  def handle_info({port, {:data, data}}, _ctx, %{app_port: port} = state) do
    time = Membrane.Time.monotonic_time()
    init_time = state.init_time || time

    buffer = %Buffer{payload: data, pts: time - init_time}

    {[buffer: {:output, buffer}], %{state | init_time: init_time, camera_open: true}}
  end

  @impl true
  def handle_info({port, {:exit_status, exit_status}}, _ctx, %{app_port: port} = state) do
    cond do
      exit_status == 0 ->
        {[end_of_stream: :output], state}

      state.camera_open ->
        raise "#{state.app_binary} error, exit status: #{exit_status}"

      state.retries < @max_retries ->
        Membrane.Logger.warning("Camera failed to open with exit status #{exit_status}, retrying")
        Process.sleep(50)
        new_port = open_port(state.options, state.app_binary)
        {[], %{state | retries: state.retries + 1, app_port: new_port}}

      true ->
        raise "Max retries exceeded, camera failed to open, exit status: #{exit_status}"
    end
  end

  @spec open_port(Membrane.Rpicam.Source.t(), String.t()) :: port()
  defp open_port(options, app_binary) do
    # Set LIBCAMERA_LOG_LEVELS to suppress INFO/WARN messages for cleaner logs
    # Log levels: 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR, 4=FATAL
    # Setting to 3 (ERROR) suppresses the noisy SDN tuning and SyncMode warnings
    # while keeping error messages visible for troubleshooting
    Port.open(
      {:spawn, create_command(options, app_binary)},
      [:binary, :exit_status, {:env, [{~c"LIBCAMERA_LOG_LEVELS", ~c"*:3"}]}]
    )
  end

  @spec create_command(Membrane.Element.options(), String.t()) :: String.t()
  defp create_command(opts, app_binary) do
    timeout =
      case opts.timeout do
        :infinity -> 0
        t when t >= 0 -> t
      end

    {framerate_num, framerate_denom} = resolve_defaultable_option(opts.framerate, {-1, 1})
    framerate_float = framerate_num / framerate_denom

    width = resolve_defaultable_option(opts.width, 0)
    height = resolve_defaultable_option(opts.height, 0)

    # Suppress verbose output unless explicitly enabled
    verbose_flag = if opts.verbose, do: "", else: "--nopreview"

    # Get profile and level from options
    profile = Atom.to_string(opts.profile)
    level = opts.level

    # Build flip options
    hflip_flag = if opts.hflip, do: "--hflip", else: ""
    vflip_flag = if opts.vflip, do: "--vflip", else: ""

    # Build bitrate option
    bitrate_args =
      case opts.bitrate do
        :auto -> []
        bitrate when is_integer(bitrate) -> ["--bitrate", "#{bitrate}"]
      end

    # Build inline headers option (for mobile compatibility)
    inline_headers_flag = if opts.inline_headers, do: "--inline", else: ""

    # Build flush option (for low latency)
    flush_flag = if opts.flush, do: "--flush", else: ""

    # Build low-latency option (eliminates keyframe jitter)
    low_latency_flag = if opts.low_latency, do: "--low-latency", else: ""

    # PATCHED: Added --codec h264 and --libav-format h264 to fix libav output format error
    # The --libav-format parameter is required when outputting to stdout (-o -)
    # Profile, level, and flip options are now configurable for better compatibility
    # Added keyframe interval (--intra) for better mobile decoder performance
    # Added inline headers for mobile compatibility
    # Added flush for immediate encoder output (reduces latency)
    # Added low-latency mode to eliminate keyframe jitter in real-time streaming
    # libcamera INFO/WARN messages are suppressed via LIBCAMERA_LOG_LEVELS env var (set in open_port/2)
    ([
       app_binary,
       "-t",
       "#{timeout}",
       "--codec",
       "h264",
       "--profile",
       profile,
       "--level",
       "#{level}",
       "--intra",
       "#{opts.keyframe_interval}",
       "--libav-format",
       "h264",
       "--framerate",
       "#{framerate_float}",
       "--width",
       "#{width}",
       "--height",
       "#{height}",
       hflip_flag,
       vflip_flag,
       inline_headers_flag,
       flush_flag,
       low_latency_flag,
       verbose_flag,
       "-o",
       "-"
     ] ++ bitrate_args)
    |> Enum.filter(&(&1 != ""))
    |> Enum.join(" ")
  end

  @spec resolve_defaultable_option(:camera_default | x, x) :: x when x: var
  defp resolve_defaultable_option(option, default) do
    case option do
      :camera_default -> default
      x -> x
    end
  end

  @spec detect_camera_binary() :: String.t()
  defp detect_camera_binary do
    # Try rpicam-vid first (newer Raspberry Pi OS)
    case System.find_executable(@app_name) do
      nil ->
        # Fall back to libcamera-vid (older systems)
        case System.find_executable(@fallback_app_name) do
          nil ->
            Membrane.Logger.warning(
              "Neither #{@app_name} nor #{@fallback_app_name} found in PATH. " <>
                "Defaulting to #{@app_name}, but this may fail."
            )

            @app_name

          path ->
            Membrane.Logger.info("Found #{@fallback_app_name} at #{path}")
            @fallback_app_name
        end

      path ->
        Membrane.Logger.info("Found #{@app_name} at #{path}")
        @app_name
    end
  end
end
