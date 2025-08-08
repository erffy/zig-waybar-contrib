# Changelog

## v1.x

### v1.1.3

#### module: memory, updates, ping

- General code improvements for better readability and performance

#### module: updates

- Optimize `ArenaAllocator` usage to reduce heap allocations and improve memory management

#### module: ping

- Remove IPv6 detection for simplification
- Replace `heap.page_allocator` with `ArenaAllocator` for more efficient memory allocation

### v1.1.2

#### module: ping

- Now supports domain names instead of just static IPs
  - The IP address is automatically re-resolved every 30 seconds to ensure accuracy

### v1.1.1

#### GPU Module

- Binary now automatically selects the appropriate backend (on compile time):
  - Uses `amdsmi.zig` if `amdsmi` is installed.
  - Uses `rocmsmi.zig` if `amdsmi` is unavailable and `rocm-smi-lib` available.
  - Uses `nvml` if `cuda` is available
- Added support for `nvml` (requires CUDA).
- Support for `rocmsmi` backend is deprecated.
- Fixed compatibility issues with the `amdsmi` backend.

#### Build

- Improvements to the build system for stability and consistency.

---

### v1.1.0

#### Ping Module

- Introduced detailed quality metrics for latency results.

#### GPU Module

- Binary now automatically selects the appropriate backend:
  - Uses `amdsmi.zig` if `amdsmi` is installed.
  - Falls back to `rocmsmi.zig` if `amdsmi` is unavailable.
  - `amdsmi.zig` takes precedence if both are present.
- Added support for `amdsmi` backend

#### Network Module

- **Removed** — functionality has been deprecated or relocated.

#### Build

- Refactored build files for better modularity and ease of use.

#### Utilities

- Moved `waybar` and `format` utilities to a shared `utils/` directory for reuse across modules.

#### Project Structure

- Reorganized file tree for improved clarity and maintainability.
- Cleaned up and standardized codebase for better readability and consistency.
