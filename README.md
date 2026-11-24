Automated Arch Linux installation tested in VM with GPU passthrough.

Download ISO from https://archlinux.org/download/ (tested on Arch Release: 2026.11.01)

Based on Guides:

Part 1: https://sharicov.github.io/manuals/#Arch%20Linux%20part%201%20install%20in%20cli%20by%20claude%20from%20scratch%20in%20Unraid%20VM%20-%20btrfs%2C%20GRUB%2C%206900XT%20passthrough%20install%20v5

Part 2: https://sharicov.github.io/manuals/#Arch%20Linux%20part%202%20install%20packages%20by%20claude%20%20-%20packages%2C%20Ollama%2C%20Docker%2C%20Hyprland%20and%20GPU%20switch%20v9%20-30min

After first reboot make archpost.sh in home directory executable and run it

chmod +X archpost.sh && ./archpost.sh
