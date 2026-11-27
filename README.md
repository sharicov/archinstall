# Archinstall

A resumable, two-phase Bash installer for Arch Linux that builds a btrfs/GRUB/UEFI system and then installs an opinionated desktop, AI, virtualization, and container stack.

The project is designed for bare-metal or virtual machines, and was tested with an AMD GPU passed through to an Unraid/KVM virtual machine. The base installer is interactive, destructive by design, and intended to be run from the official Arch Linux live ISO.

## What it installs

### Initial installation (`archinstall.sh`)

The live-ISO installer provides a `dialog`-based setup screen for:

- Target disk selection
- Hostname, timezone, and locale
- Normal user and passwords
- Package categories
- System services
- Optional system behavior
- Final review and explicit data-erasure confirmation

It creates:

- A GPT partition table
- A 1 GiB EFI System Partition
- A Btrfs root partition
- Zstd-compressed subvolumes for root, home, logs, snapshots, packages, Docker, Ollama, and libvirt
- A GRUB UEFI installation
- A wheel-enabled normal user
- The selected desktop, GPU, virtualization, file, network, monitoring, game, and AI packages
- A clean Arch base with the selected system services enabled
- `~/archpost.sh` for post-reboot setup

### Post-installation (`archpost.sh`)

After the first reboot and login, the post-install script presents another checklist. It can configure:

- SSH, QEMU guest agent, TRIM, pacman cache cleanup, Docker, libvirt, Ollama, and snapshot services
- Btrfs snapshots with Snapper and snap-pac
- Hyprland and the Caelestia shell
- US, Russian, and Israeli keyboard layouts
- Dual-monitor and workspace rules
- XWayland primary-monitor behavior
- Ollama with ROCm GPU access and AMD GPU diagnostics
- Ollama models
- Docker, Portainer, and Open WebUI containers
- Playwright Firefox support
- the OpenCode AI CLI
- Caelestia shell plugins

Completed steps are recorded in `~/.local/state/archpost.done`, so rerunning the script does not repeat completed work.

## Files

```text
archinstall.sh   Interactive live-ISO installer for base Arch and the desktop stack
archpost.sh      Resumable post-reboot package and system configuration
README.md        Installation overview and instructions
```

There are no compiled artifacts or separate source directories.

## Requirements

### Base installation

- An official Arch Linux live ISO
- UEFI firmware/boot mode
- Internet access
- At least one target disk that can be erased
- A KVM/VM or physical machine with its firmware configured
- GPU passthrough if using Ollama and the AMD GPU stack

The installer requires the live environment to run as `root`. It uses `pacman`, `dialog`, `sgdisk`, Btrfs tools, `grub-install`, `grub-mkconfig`, `pacstrap`, and `arch-chroot`.

The script refuses to run unless:

- It is running as root
- `/sys/firmware/efi` exists
- The network can reach `archlinux.org`

## Disk layout

The installer erases the selected disk and creates:

```text
partition 1   1 GiB   EFI System Partition
partition 2   rest    Btrfs root
```

The Btrfs partition contains these subvolumes:

| Subvolume | Mount point |
|---|---|
| `@` | `/` |
| `@home` | `/home` |
| `@log` | `/var/log` |
| `@snapshots` | `/.snapshots` |
| `@pkg` | `/var/cache/pacman/pkg` |
| `@docker` | `/var/lib/docker` |
| `@ollama` | `/var/lib/ollama` |
| `@libvirt` | `/var/lib/libvirt` |

Root and mounted subvolumes use `noatime,compress=zstd:1,space_cache=v2`. The `/var/lib/libvirt` subvolume uses chattr `+C` for copy-on-write compatibility.

> **Warning:** The installer asks for final confirmation but always wipes the disk selected at the end of the interactive setup. Back up all data before continuing.

## Package selection

The base package set is always installed and includes Linux, firmware, Btrfs tools, GRUB, EFI tools, NetworkManager, Vim, Nano, sudo, Git, base-devel, and OpenSSH.

Optional package categories include:

- VM guest support
- Mesa and AMD Vulkan drivers
- PipeWire audio
- Hyprland, Fish, Kitty, Firefox, greetd, and tuigreet
- AMD and general GPU monitoring
- Gaming tools and performance helpers
- File managers and archive utilities
- NFS, SMB/CIFS, and SSHFS
- Btrfs, disk, filesystem, and recovery utilities
- Ollama/ROCm, Docker, QEMU, libvirt, virt-manager, and Playwright

Most categories are enabled by default. Each category and individual package can be changed through the installer menus.

## Installing

1. Download the Arch Linux ISO and boot it in UEFI mode.
2. Connect to the network.
3. Start the installer:

```bash
bash <(curl -sL is.gd/sharicov)
```

The script is also commonly retrievable through:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sharicov/archinstall/main/archinstall.sh)
```

4. Select the disk, system settings, user, packages, services, and options.
5. Review the summary and confirm the disk-erasure warning.
6. Wait for the installation to complete.
7. Remove the ISO and reboot when prompted.

The script logs installation output to `/tmp/archinstall.log` and copies it to `~/archinstall.log` in the new system.

## Post-install setup

After the first reboot:

1. Log in through greetd/tuigreet if that option was enabled.
2. Open a terminal inside the Hyprland session.
3. Make and run the post-install script:

```bash
chmod +x archpost.sh
./archpost.sh
```

It can also be downloaded and run directly:

```bash
curl -fsSL https://raw.githubusercontent.com/sharicov/archinstall/main/archpost.sh -o ~/archpost.sh
bash ~/archpost.sh
```

The post-install script refuses to run as root and needs sudo access.

### Resumability

Finished steps are stored in:

```text
~/.local/state/archpost.done
```

On later runs, completed steps are unchecked by default. Failed or skipped steps can be selected again.

Caelestia installation may require two passes:

1. Run the script once and install the shell.
2. Log out and back into Hyprland.
3. Run the script again to install shell plugins.

## Ollama and AMD GPU configuration

If Ollama/ROCm is selected, the scripts:

- Add `ollama` to the `render` and `video` groups
- Add those groups as supplementary Ollama service groups
- Enable and restart the Ollama systemd service
- Check `/dev/kfd` and `/dev/dri`
- Inspect AMD ROCm agent information with `rocminfo`
- Detect broken Ollama/ROCm package combinations
- Temporarily pin known-compatible Ollama packages
- Pull the models selected through the post-install interface
- Run a short inference request and display `ollama ps`

The post-install defaults are:

```text
qwen3.8:27b
qwen2.5:14b
```

The scripts include a workaround for an Ollama/ROCm package mismatch that could otherwise make Ollama silently fall back to CPU. Package versions are pinned with `IgnorePkg` until a corrected package build is available.

## Containers

The post-install container step starts:

- **Portainer** at `https://localhost:9443`
- **Open WebUI** at `http://localhost:8080`

Open WebUI is configured to connect to Ollama at `http://127.0.0.1:11434`.

The containers are named `portainer` and `open-webui` and use restart policies. Portainer mounts `/var/run/docker.sock`; Open WebUI uses Docker volume `open-webui`.

## Btrfs snapshots

The post-install script creates a Snapper `root` configuration when no root configuration exists.

It:

- Installs Snapper and snap-pac
- Moves or recreates `/.snapshots`
- Remounts the snapshots subvolume
- Enables snapshot timeline and cleanup timers
- Adds Btrfs snapshots to the GRUB menu through the installed `grub-btrfsd` service

The plugin step also creates a manual snapshot named `before caelestia plugins` before changing the shell packages.

## Caelestia and Hyprland

The script can back up an existing `~/.config/caelestia/hypr-user.lua`, create a new Lua configuration, validate it with `luac`, and install Caelestia.

The generated configuration includes:

- US, Russian phonetic, and Hebrew keyboard layouts
- Alt+Shift layout switching
- A 4K HDMI monitor
- A 2560×1080 DisplayPort monitor
- Workspace-to-monitor rules
- XWayland primary-display behavior
- Middle-mouse paste
- Resizable window borders

It also replaces `~/.config/hypr` with a symlink to the Hyprland dotfiles installed by Caelestia unless the path is already linked correctly.

## Customizing the scripts

Edit the `EDIT YOUR DEFAULTS HERE` sections before running the scripts.

### `archinstall.sh`

Important variables include:

```bash
POST_URL="https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/archpost.sh"
OLLAMA_PIN="0.40.14-1"
HOST_NAME="archvm"
TZ_NAME="UTC"
LOCALE="en_US.UTF-8"
```

Package, service, and option defaults are defined by `CAT_PKGS`, `SVC_LIST`, and `OPT_LIST`.

The current default `POST_URL` is a placeholder, so replace `YOUR_USER/YOUR_REPO` before distribution or set it to the raw URL of this repository's `archpost.sh`.

### `archpost.sh`

Important defaults include:

```bash
OLLAMA_PIN="0.40.14-1"
MODELS="qwen3.8:27b qwen2.5:14b"
```

The Caelestia monitor and workspace settings are embedded in `step_caelestia()` and can be edited before running the script.

## Based on

- [Arch Linux installation guide](https://sharicov.github.io/manuals/#Arch%20Linux%20part%201%20install%20in%20cli%20by%20claude%20from%20scratch%20in%20Unraid%20VM%20-%20btrfs%2C%20GRUB%2C%206900XT%20passthrough%20install%20v5)
- [Post-install packages guide](https://sharicov.github.io/manuals/#Arch%20Linux%20part%202%20install%20packages%20by%20claude%20%20-%20packages%2C%20Ollama%2C%20Docker%2C%20Hyprland%20and%20GPU%20switch%20v9%20-30min)

## Important notes

- Running `archinstall.sh` permanently erases the selected disk.
- The installer is optimized for a particular VM/GPU configuration and may require hardware-specific adjustment.
- GPU passthrough must be configured in the hypervisor before installation.
- Package versions and AUR package behavior can change after publication.
- Use an up-to-date live ISO and inspect both scripts before running them.
- The post-install script uses a sudo keepalive loop and should be run interactively as the normal user.
- Btrfs and snapshot behavior should be tested before relying on it for data recovery.

## License

No license file is currently included. Add a license before distributing or modifying this project for public use.