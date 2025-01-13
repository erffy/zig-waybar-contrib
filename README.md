> [!IMPORTANT]
> I am new to Zig, so some modules may take a long time to add/update. I would appreciate your help 🥰.

# zig-waybar-contrib
A collection of high-performance Waybar modules written in Zig.

## Overview
`zig-waybar-contrib` provides efficient, lightweight modules for [Waybar](https://github.com/Alexays/Waybar) by leveraging the performance and safety features of [Zig](https://ziglang.org/). These modules are optimized and focus on system monitoring and status reporting.

## Features
- **High Performance**: Optimized implementation in Zig for minimal resource usage
- **Modular Design**: Use only the modules you need
- **Real-time Monitoring**: Accurate system metrics with minimal overhead

## Available Modules
- All modules write a single line json output.
- All modules are compiled with LTO and ReleaseFast optimizations. See the [build](./build.zig) file for details.

| Module  | Description                               | Status                          | Dependencies                  | Known Issues                                    | Supports               |
|---------|-------------------------------------------|---------------------------------|-------------------------------|-------------------------------------------------|------------------------|
| Updates | Tracks available system updates           | ✅ Implemented                  | `pacman-contrib`, `fakeroot`  | Compatible only with Arch-based distributions   |                        |
| GPU     | Monitors GPU statistics and performance   | ✅ Implemented                  |                               | Path resolution errors may affect functionality | AMD GPUs (RX series)   |
| Memory  | Tracks system memory usage and statistics | ✅ Implemented                  |                               |                                                 |                        |
| Ping    | Network latency monitoring                | ✅ Implemented                  |                               |                                                 |                        |
| CPU     | CPU usage and temperature monitoring      | 🚧 In Development               |                               |                                                 |                        |

## Installation
- Download the latest release from the [GitHub Releases](https://github.com/erffy/zig-waybar-contrib/releases)

## Configuration

Add modules to your Waybar configuration (`~/.config/waybar/config`):

```json
{
    "modules-right": [
        "custom/updates",
        "custom/gpu",
        "custom/memory",
        "custom/ping"
    ],
    "custom/updates": {
        "exec": "path/to/updates-module",
        "return-type": "json",
        "interval": 3600
    }
    // Add other module configurations as needed
}
```

## Building from Source
> Requirements
- Zig (0.13)

```bash
git clone https://github.com/erffy/zig-waybar-contrib
cd zig-waybar-contrib
zig build
```

## Contributing

Contributions are welcome! Please consider:
- Adding new modules
- Improving existing modules
- Fixing bugs
- Improving documentation

## 🛡️ License

This project is licensed under the GNU General Public License v3.0. See the [LICENSE](./LICENSE) file for details.

---

### ✨ Made with ❤️ by Me
