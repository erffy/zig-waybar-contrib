> [!IMPORTANT]
> I'm new to Zig, so it might take me some time to add or update modules. I'd really appreciate your help and support as I learn! 🥰

# zig-waybar-contrib
A collection of high-performance Waybar modules written in Zig.

## Overview
`zig-waybar-contrib` provides efficient and lightweight modules for [Waybar](https://github.com/Alexays/Waybar) by leveraging the performance and safety features of [Zig](https://ziglang.org/). These modules are designed to optimize system monitoring and status reporting with minimal resource usage.

## Features
- ⚡ **High Performance**: Optimized Zig implementations for minimal resource consumption.
- 🧩 **Modular Design**: Select only the modules you need for flexibility.
- 📊 **Real-time Monitoring**: Accurate system metrics with minimal overhead.
  
## Available Modules
- All modules write a single line json output.
- All modules are compiled with LTO and ReleaseFast optimizations. See the [build](./build.zig) file for details.

| Module  | Description                               | Status                          | Dependencies                  | Known Issues                                    | Supports               |
|---------|-------------------------------------------|---------------------------------|-------------------------------|-------------------------------------------------|------------------------|
| Updates | Tracks available system updates           | ✅ Implemented                  | `pacman-contrib`, `fakeroot`  | Compatible only with Arch-based distributions   |                        |
| GPU     | Monitors GPU statistics and performance   | ✅ Implemented                  |                               |                                                 | AMD GPUs (RX series)   |
| Memory  | Tracks system memory usage and statistics | ✅ Implemented                  |                               |                                                 |                        |
| Ping    | Network latency monitoring                | ✅ Implemented                  |                               |                                                 |                        |

## Screenshots

| Module  | Screenshot                                                               |
|---------|--------------------------------------------------------------------------|
| Updates | ![](assets/updates_available.png) ![](assets/updates_noupdate.png)       |
| GPU     | ![](assets/gpu.png)                                                      |
| Memory  | ![](assets/memory.png)                                                   |
| Ping    | ![](assets/ping.png)                                                     |

## Installation
1. Download the latest release from the [GitHub Releases](https://github.com/erffy/zig-waybar-contrib/releases).
2. Alternatively, you can build from source (see the section below).

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
- Zig (0.14)

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
