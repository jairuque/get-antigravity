# get-antigravity

One-command installer for **[Google Antigravity](https://antigravity.google)** products on Linux.

## Quick install

### Interactive (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/USERNAME/get-antigravity/main/install.sh -o install.sh
bash install.sh
```

### One-liner (specific product)

```bash
# Install Antigravity IDE for current user
curl -fsSL https://raw.githubusercontent.com/USERNAME/get-antigravity/main/install.sh | bash -s -- --install ide --user

# Install CLI system-wide
curl -fsSL https://raw.githubusercontent.com/USERNAME/get-antigravity/main/install.sh | sudo bash -s -- --install cli

# Install everything
curl -fsSL https://raw.githubusercontent.com/USERNAME/get-antigravity/main/install.sh | bash -s -- --user all
```

### System-wide installation

```bash
sudo bash install.sh --install ide
```

## Supported Products

| Product | Description | Binary |
|---|---|---|
| **Antigravity 2.0** | Desktop app | `/usr/local/bin/antigravity` |
| **Antigravity IDE** | Code editor (VS Code fork) | `/usr/local/bin/antigravity-ide` |
| **Antigravity CLI** | Terminal agent (`agy`) | `~/.local/bin/agy` |
| **Antigravity SDK** | Python SDK | `pipx` / `pip install` |

## Options

```
Usage: install.sh [OPTIONS] [PRODUCTS...]

Products: antigravity, ide, cli, sdk, all

Options:
  --install PRODUCT   Install specific product (can be repeated)
  --update            Update all installed products
  --uninstall PRODUCT Uninstall a product
  --list              List installed vs available versions
  --dry-run           Preview actions without executing them
  --force             Force reinstall even if already up to date
  --user              Install for current user only (no root required)
  --keep-previous N   Keep N previous backup versions (default: 1)
  --verbose           Detailed output for debugging
  --quiet             Minimal output
  --help              Show this help
```

## Supported Distributions

| Distribution | Notes |
|---|---|
| Ubuntu 20.04+ | Full support |
| Debian 11+ | Full support (Debian 10: glibc 2.28 minimum) |
| Fedora 36+ | Full support |
| RHEL 8+ / Rocky 8+ | Full support (needs EPEL for pip) |
| Arch Linux / Manjaro | Full support (package names differ) |
| openSUSE Leap 15.4+ | Full support |
| openSUSE Tumbleweed | Full support |
| Linux Mint 20+ | Full support |
| **Alpine Linux** | **Not supported** for desktop products (musl libc). CLI and SDK work. |

All supported distros require **glibc >= 2.28** for desktop products.

## Installation paths

| Mode | Binaries | Desktop/Icons | Application Data |
|---|---|---|---|
| System (`sudo`) | `/usr/local/bin/` | `/usr/share/` | `/opt/` |
| User (`--user`) | `~/.local/bin/` | `~/.local/share/` | `~/.local/opt/` |

## Integrity verification

When run from a downloaded file, the script self-verifies its SHA256 hash before executing.
This check is skipped in pipe mode (`curl | bash`).

## License

MIT — see [LICENSE](LICENSE)
