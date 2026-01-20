![zig-waybar-contrib](https://img.shields.io/badge/zig--waybar--contrib-gray?style=for-the-badge&logo=zig&logoColor=orange) 
![License](https://img.shields.io/badge/License-GPL--3.0-orange?style=for-the-badge) 
![Stars](https://img.shields.io/gitea/stars/erffy/zig-waybar-contrib?gitea_url=https%3A%2F%2Fcodeberg.org&style=for-the-badge&color=DAA520)
![Issues](https://img.shields.io/github/issues/erffy/zig-waybar-contrib?style=for-the-badge)
![Last Commit](https://img.shields.io/gitea/last-commit/erffy/zig-waybar-contrib?gitea_url=https%3A%2F%2Fcodeberg.org&style=for-the-badge&color=F7A41D)
<br>
**High-performance Waybar modules written in Zig for efficient system monitoring**

### Overview

`zig-waybar-contrib` is a collection of high-performance custom modules for [Waybar](https://github.com/Alexays/Waybar), built using the [Zig](https://ziglang.org).

- **Blazingly Fast**: Minimal startup time and runtime overhead.
- **Memory Safe**: Leveraging Zig's safety features to prevent common crashes and leaks.
- **Zero Dependencies**: Statically linked binaries that run anywhere without runtime interpreters.
- **Deeply Configurable**: Simple, type-safe configuration using ZON (Zig Object Notation).

Whether you need to monitor precision fan speeds, track compilation latency with pings, or watch your memory usage without eating it up, `zig-waybar-contrib` has you covered.

### Modules

| Module      | Description                            |
|:------------|:---------------------------------------|
| **CPU**     | Displays per-core CPU usage            |
| **Fan**     | Monitors fan speeds                    |
| **Memory**  | Reports RAM usage and statistics       |
| **Ping**    | Measures network latency               |
| **Updates** | Tracks system package updates          |

See [MODULES](MODULES.md) for detailed documentation on each module.

### Installation

![Repology](https://repology.org/badge/vertical-allrepos/zig-waybar-contrib.svg)
![Repology](https://repology.org/badge/vertical-allrepos/zig-waybar-contrib-beta-bin.svg)

> [!NOTE]
> To try the Nightly versions, follow `Script Installation` section.<br>
> To try the Beta versions, install the `zig-waybar-contrib-beta-bin` package from [AUR](https://aur.archlinux.org/packages/zig-waybar-contrib-beta-bin)

#### Quick Installation (AUR)

You can easily install the latest version from the [AUR](https://aur.archlinux.org/packages/zig-waybar-contrib).

```bash
# Using paru
paru -S zig-waybar-contrib

# Using yay
yay -S zig-waybar-contrib
```

#### Script Installation

> [!NOTE]
> This script doesn't need root permissions.

The installation script automates cloning, building, and installing.

```bash
bash -c "$(curl -fsSL https://codeberg.org/erffy/zig-waybar-contrib/raw/branch/0.16.x-staging/install.sh)"
```

This script installs into your `$HOME` directory (`$HOME/.local/share/zig-waybar-contrib`) and places its binaries in `$HOME/.local/bin`.

#### Manual Build (From Source)

To build from source, you need [Zig](https://ziglang.org/download) installed (check `build.zig` for version requirements).

```bash
git clone https://codeberg.org/erffy/zig-waybar-contrib.git
cd zig-waybar-contrib
zig build -Drelease
```

Binaries will be available in `zig-out/bin/`.

### Configuration

Add the modules to your Waybar configuration. You can include the provided config file or define modules manually.

**Method 1: Include Config**

```jsonc
{
  // Load module configurations from zig-waybar-contrib
  "include": [
    "/usr/share/zig-waybar-contrib/config.jsonc", // if you installed from aur
    "~/.local/share/zig-waybar-contrib/config.waybar.jsonc" // if you installed with script
  ],

  "modules-right": [
    "custom/updates",
    "custom/memory",
    "custom/ping",
    "custom/cpu",
    "custom/fan"
  ]
}
```

**Method 2: Manual Definition**

See [config.waybar.jsonc](https://codeberg.org/erffy/zig-waybar-contrib/src/branch/0.16.x-staging/config.waybar.jsonc) for the default configuration values.

### Contributing

See [CONTRIBUTING](https://codeberg.org/erffy/zig-waybar-contrib/src/branch/0.16.x-staging/CONTRIBUTING.md)

### Acknowledgments

- **Zig Team** - For creating an amazing systems programming language
- **Waybar Contributors** - For the excellent status bar that makes this possible
- **Community** - For feedback, bug reports, and contributions

---

<div align="center">

**Made with ❤️ by Me**

*Star ⭐ this repo if you find it useful!*<br>
*Join our [Discord](https://discord.gg/tb8MvnnSfZ) for support and updates!*

This project is licensed under the **GNU General Public License v3.0**. See [LICENSE](./LICENSE) for details.

</div>
