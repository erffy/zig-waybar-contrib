# Changelog

### master

- refactor(memory): use `@This()` instead of `MemoryInfo`
- build: simplify linking

## v1.x

### v1.3.0

- release: update to `1.3.0`
- fix(updates): fix repeated calls in allocators
- refactor(updates): code improvements
- fix(updates): fix wrong allocator usage in `configData`
- build: set `OptimizationMode` to `ReleaseSmall`
- build: set `abi` to `gnu`
- build: set `os_tag` to `linux`
- build: update deprecated APIs, set target CPU to x86_64
- utils(waybar): replace `RTMIN+32` with `posix.sigrtmin()` function
- fix(updates): fix wrong allocator usage in `arena_config`
- fix(updates): fix allocator usage
- refactor(updates): replace deprecated `fixedBufferStream()` function with new one
- refactor(ping): improve `resolveIP()` function
- refactor(updates): improve readability and cleanup handling in `checkupdates()` function
- refactor(updates): improve readability and memory handling
- feat(memory): add `SwapCached` info
- utils(waybar): replace deprecated `trimRight()` function with `trimEnd()`
- utils(waybar): replace deprecated `readAll()` function with new one
- refactor(ping): remove `TARGET_UPDATE_MS` from config and set to `60`s
- docs: update readme
- docs: update changelog
- refactor(ping): remove domain ip update info
- refactor(memory): replace deprecated `readAll()` function with new one
- refactor(updates): update imports for clarity

### v1.2.0

- zig: updated to `0.15.1`.

### v1.1.4

#### module: ping

- Swap the positions of the total percentage and total text.
- Fix TARGET_PORT type mismatch in ping module

#### module: updates

- Make `CHECK_INTERVAL` configurable `(~/.config/zwc/updates.json)`
- Fix `CHECK_INTERVAL` is `0` that caused by alloc (08/24/2025)

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
