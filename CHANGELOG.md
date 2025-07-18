# CHANGELOG

## v1.x

### v1.1.0

#### Module: ping

- Added detailed quality information for latency results.

#### Module: gpu

The binary now builds with `amdsmi.zig` if `amdsmi` is installed; otherwise, it falls back to `rocmsmi.zig`.
If both are available, `amdsmi.zig` takes precedence.

- Added support for reporting the `amdsmi` version.

#### Build

- Build file improvements

#### Utils

- Moved waybar and format modules to a dedicated shared directory.

#### Project

- Reorganized and reordered the project file tree for better clarity and maintainability.
- Edited and cleaned up existing files to improve code consistency and readability.
