# Membrane Rpicam Source - Internalized

This directory contains an internalized version of the `membrane_rpicam_plugin`.

## Why Internalized?

The original `membrane_rpicam_plugin` v0.1.5 had compatibility issues:

1. **Missing codec parameter**: When outputting to stdout (`-o -`), `libcamera-vid` requires `--codec h264` to be explicitly specified, otherwise it throws:
   ```
   ERROR: *** libav: cannot allocate output context, try setting with --libav-format ***
   ```

2. **Single file dependency**: The plugin is just one simple source file (~140 lines), making it easy to internalize and maintain.

3. **Better control**: Having it in our codebase allows us to make fixes and improvements without waiting for upstream changes.

## Changes from Original

See [source.ex](source.ex) for the full implementation. Key changes:

- **Line 144**: Added `--codec h264` parameter to the command
- **Lines 155-178**: Added automatic detection of `rpicam-vid` vs `libcamera-vid`
- Uses `rpicam-vid` by default on newer Raspberry Pi OS
- Falls back to `libcamera-vid` on older systems
- Updated module documentation to reflect internalization
- Preserved Apache 2.0 license and attribution

## Original Source

- Repository: https://github.com/membraneframework/membrane_rpicam_plugin
- Version: Based on v0.1.5
- License: Apache 2.0

## Setup Requirements

On Raspberry Pi OS (Bookworm or later):

```bash
# Install rpicam-apps
sudo apt update
sudo apt install -y rpicam-apps

# Verify installation
rpicam-vid --version
```

**Note:** No symlink required! The module automatically detects which binary is available (`rpicam-vid` or `libcamera-vid`).

## Future Considerations

If the upstream plugin is updated to fix these issues, we can consider switching back to the dependency. For now, this internalized version provides better stability and maintainability.
