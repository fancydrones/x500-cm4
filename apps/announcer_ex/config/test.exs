import Config

# Test-specific config - set test environment variables
System.put_env("CAMERA_ID", "100")
System.put_env("CAMERA_NAME", "Test Camera")
System.put_env("CAMERA_URL", "rtsp://test:554/stream")
System.put_env("SYSTEM_ID", "1")
System.put_env("SYSTEM_HOST", "localhost")
System.put_env("SYSTEM_PORT", "14550")
