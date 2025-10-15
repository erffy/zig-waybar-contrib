# CHANGELOG
<!--
### master (v1.4.1)

- release: update to 1.4.1
- refactor(gpu): remove unnecessary `free()` functions
- refactor(updates): remove unnecessary `EUID` allocating
- refactor(updates): replace `fs.max_path_bytes` with `linux.MAX_PATH`
- chore(ping): improve code quality
- build: create module for `network`
- modules: update module files that uses `resolveIP()` function from `ping` module
- core(network): move `resolveIP()` function to here
-->
## v1.x

### v1.4.1

- release: update to `1.4.1`
- refactor(gpu): remove unnecessary `free()` functions
- refactor(updates): remove unnecessary `EUID` allocating
- refactor(updates): replace `fs.max_path_bytes` with `linux.MAX_PATH`
- chore(ping): improve code quality
- build: create module for `network`
- modules: update module files that uses `resolveIP()` function from `ping` module
- core(network): move `resolveIP()` function to here

### v1.4.0

- release: update to `1.4.0`
- build: add semantic version to executables
- fix: fix type mismatch in getPid function
- chore: remove unnecessary `utils` imports in gpu module
- refactor: implement new tree changes in modules
- build: import config and pid
- build: update module sources
- tree: move all modules to `modules/` directory
- tree: move `utils/config.zig` to `core/config.zig`
- core(pid): improve code
- utils(waybar): move to `core/pid.zig` and it has been made modular to avoid any issues when used anywhere.
- refactor(memory): change paramater `w` to `writer` and define `*Io.Writer` type
- build: use `ReadOnly` mode on `fileExists()` function
- refactor(memory): use `@This()` instead of `MemoryInfo`
- build: simplify linking

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

- release(zig): updated to `0.15.1`.
