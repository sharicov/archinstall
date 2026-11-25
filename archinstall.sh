#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# Arch Linux TUI installer (btrfs + zstd + subvolumes, GRUB/UEFI)
# Run from the Arch live ISO:
#   bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/archinstall.sh)
# Short form (make an is.gd link with alias "archx" pointing at the raw URL above):
#   bash <(curl -sL is.gd/archx)
# Log: /tmp/archinstall.log
# ──────────────────────────────────────────────────────────────────────────────
set -u
LOG=/tmp/archinstall.log

[[ $EUID -eq 0 ]]          || { echo "Run as root (live ISO default)."; exit 1; }
[[ -d /sys/firmware/efi ]] || { echo "UEFI boot required (set the VM to OVMF)."; exit 1; }
ping -c1 -W3 archlinux.org &>/dev/null || { echo "No network. Fix it first (iwctl / dhcpcd)."; exit 1; }
command -v dialog >/dev/null || pacman -Sy --noconfirm dialog

# ══════════════════════════ EDIT YOUR DEFAULTS HERE ══════════════════════════
# Format per line:  name|description|on/off

# Part 2 script, copied to the new user's home so you can run it after reboot (leave empty to skip):
POST_URL="https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/archpost.sh"

# Arch's ollama/ollama-rocm 0.40.17-1 were mismatched (backend needs libggml-base.so.1, ollama ships .so.0),
# so ROCm silently fell back to CPU. If that is detected after install, these versions are installed from
# the Arch Linux Archive and pinned in IgnorePkg. Unpin when a fixed build lands.
OLLAMA_PIN="0.40.14-1"

# Always installed by pacstrap (not selectable):
BASE_PKGS="base linux linux-firmware btrfs-progs grub efibootmgr grub-btrfs inotify-tools pacman-contrib networkmanager vim nano sudo git base-devel openssh"

PKG_CATS=(vm gfx desktop mon game files netfs fs virt)
declare -A CAT_TITLE=(
  [vm]="VM guest" [gfx]="Graphics & audio" [desktop]="Desktop & login"
  [mon]="Monitoring" [game]="Gaming" [files]="File managers & archives"
  [netfs]="Network filesystems" [fs]="Filesystem & disk tools" [virt]="Containers, VMs & AI")
declare -A CAT_PKGS
CAT_PKGS[vm]='qemu-guest-agent|QEMU guest agent (for Unraid/KVM)|on'
CAT_PKGS[gfx]='mesa|Mesa|on
vulkan-radeon|AMD Vulkan driver|on
lib32-mesa|Mesa 32-bit|on
lib32-vulkan-radeon|AMD Vulkan 32-bit|on
pipewire|PipeWire|on
pipewire-pulse|PipeWire PulseAudio|on
pipewire-jack|PipeWire JACK (avoids jack2)|on
wireplumber|WirePlumber|on'
CAT_PKGS[desktop]='hyprland|Hyprland compositor|on
xdg-desktop-portal-hyprland|Hyprland portal|on
fish|Fish shell|on
kitty|Kitty terminal|on
firefox|Firefox|on
greetd|Login manager|on
greetd-tuigreet|TUI greeter for greetd|on
caelestia-cli|Caelestia CLI (AUR)|off'
CAT_PKGS[mon]='amdgpu_top|AMD GPU monitor|on
nvtop|GPU top|on
btop|btop|on
glances|glances|on
ncdu|Disk usage|on
duf|Disk free|on
mission-center|Mission Center|on
lm_sensors|Sensors|on'
CAT_PKGS[game]='gamemode|GameMode|on
lib32-gamemode|GameMode 32-bit|on
gamescope|Gamescope|on
mangohud|MangoHud|on
lib32-mangohud|MangoHud 32-bit|on
goverlay|GOverlay|on
joystickwake|Joystick wake|on
umu-launcher|umu-run launcher|on'
CAT_PKGS[files]='cosmic-files|COSMIC Files|on
gvfs|GVfs|on
gvfs-nfs|GVfs NFS|on
gvfs-smb|GVfs SMB|on
mc|Midnight Commander|on
unzip|unzip|on
7zip|7zip|on
unrar|unrar|on
udiskie|Automount|on'
CAT_PKGS[netfs]='nfs-utils|NFS|on
cifs-utils|CIFS/SMB mount|on
smbclient|smbclient|on
sshfs|sshfs|on'
CAT_PKGS[fs]='btrfs-assistant|Btrfs GUI|on
compsize|Btrfs compression stats|on
duperemove|Dedupe|on
downgrade|Package downgrade|on
xfsprogs|XFS|on
f2fs-tools|F2FS|on
exfatprogs|exFAT|on
ntfs-3g|NTFS|on
dosfstools|FAT|on
mtools|mtools|on
gptfdisk|gdisk/sgdisk|on
gparted|GParted|on
testdisk|TestDisk|on
ddrescue|ddrescue|on'
CAT_PKGS[virt]='ollama-rocm|Ollama (ROCm)|on
rocm-hip-runtime|ROCm HIP runtime (GPU compute)|on
rocminfo|ROCm device info (diagnostics)|on
docker|Docker|on
docker-compose|Docker Compose|on
qemu-full|QEMU|on
libvirt|libvirt|on
virt-manager|virt-manager|on
dnsmasq|dnsmasq|on
edk2-ovmf|OVMF UEFI|on
swtpm|swtpm|on
python-playwright|Playwright|on'

SVC_LIST='NetworkManager|Networking (keep this on)|on
sshd|SSH server|on
qemu-guest-agent|QEMU guest agent|on
fstrim.timer|Weekly TRIM|on
paccache.timer|Pacman cache cleanup|on
grub-btrfsd|Btrfs snapshots in GRUB menu|on
greetd|TUI login manager|on
docker|Docker daemon|on
libvirtd|libvirt daemon|on
ollama|Ollama server|on'

OPT_LIST='multilib|Enable [multilib] repo|on
yay|Install yay (needed for AUR packages)|on
removable|GRUB --removable (safe for VM/OVMF)|on
sleepmask|Mask sleep/suspend/hibernate targets|on
fishshell|Use fish as default shell (if fish selected)|on
greetcfg|Write greetd config (tuigreet + Hyprland)|on
groups|Add user to render,video,docker,libvirt|on
ollamachown|Ollama: chown data dir + GPU access (render,video)|on'
# ═════════════════════════════════════════════════════════════════════════════

declare -A PSEL SSEL OSEL
init_sel() { local -n S=$2; local k d s; while IFS='|' read -r k d s; do [[ -n $k ]] && S[$k]=$s; done <<<"$1"; }
for c in "${PKG_CATS[@]}"; do init_sel "${CAT_PKGS[$c]}" PSEL; done
init_sel "$SVC_LIST" SSEL
init_sel "$OPT_LIST" OSEL

DISK="" HOST_NAME="archvm" TZ_NAME="UTC" LOCALE="en_US.UTF-8"
USERNAME="" USERPASS="" ROOTPASS="" PASS_OK=0

# ─────────────────────────────── TUI helpers ──────────────────────────────────
dlg() { dialog "$@" 2>&1 >/dev/tty; }

pick() {  # pick "Title" "data" ARRAYNAME
  local title=$1 data=$2; local -n S=$3
  local -a args=(); local k d s out
  while IFS='|' read -r k d s; do [[ -n $k ]] && args+=("$k" "$d" "${S[$k]}"); done <<<"$data"
  out=$(dlg --separate-output --title "$title" --checklist "SPACE = toggle   ENTER = confirm   ESC = back" 22 76 14 "${args[@]}") || return 0
  while IFS='|' read -r k d s; do [[ -n $k ]] && S[$k]=off; done <<<"$data"
  while read -r k; do [[ -n $k ]] && S[$k]=on; done <<<"$out"
}

count_on() { local -n S=$1; local n=0 v; for v in "${S[@]}"; do [[ $v == on ]] && ((n++)); done; echo $n; }

ask_pass() {  # sets REPLY_PASS
  local a b
  while true; do
    a=$(dlg --insecure --title "Password" --passwordbox "$1" 9 60) || return 1
    b=$(dlg --insecure --title "Password" --passwordbox "Repeat password" 9 60) || return 1
    if [[ -n $a && $a == "$b" ]]; then REPLY_PASS=$a; return 0; fi
    dialog --msgbox "Passwords are empty or do not match." 6 42 >/dev/tty
  done
}

choose_disk() {
  local -a items=(); local n s m
  while read -r n s m; do items+=("$n" "$s  $m"); done < <(lsblk -dpno NAME,SIZE,MODEL -e7,11)
  local pick_d
  pick_d=$(dlg --title "Target disk" --menu "Choose the disk to INSTALL on (it will be wiped at the end):" 18 70 8 "${items[@]}") && DISK=$pick_d
}

edit_system() {
  local out; local -a f
  out=$(dlg --title "System" --form "Edit values, TAB/arrows to move, ENTER on OK" 12 66 3 \
    "Hostname:" 1 1 "$HOST_NAME" 1 14 32 0 \
    "Timezone:" 2 1 "$TZ_NAME"   2 14 32 0 \
    "Locale:"   3 1 "$LOCALE"    3 14 32 0) || return 0
  mapfile -t f <<<"$out"
  [[ ${f[0]} =~ ^[a-zA-Z0-9-]+$ ]]       && HOST_NAME=${f[0]} || dialog --msgbox "Invalid hostname, kept old." 6 40 >/dev/tty
  [[ -e /usr/share/zoneinfo/${f[1]} ]]   && TZ_NAME=${f[1]}   || dialog --msgbox "Unknown timezone (use Region/City), kept old." 6 50 >/dev/tty
  grep -q "^#\?${f[2]} UTF-8" /etc/locale.gen && LOCALE=${f[2]} || dialog --msgbox "Unknown locale, kept old." 6 40 >/dev/tty
}

edit_user() {
  local u
  u=$(dlg --title "User" --inputbox "Username (lowercase):" 8 50 "$USERNAME") || return 0
  [[ $u =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { dialog --msgbox "Invalid username." 6 30 >/dev/tty; return 0; }
  ask_pass "Password for $u" || return 0; USERPASS=$REPLY_PASS
  if dialog --yesno "Use the same password for root?" 6 44 >/dev/tty; then ROOTPASS=$USERPASS
  else ask_pass "Root password" || return 0; ROOTPASS=$REPLY_PASS; fi
  USERNAME=$u; PASS_OK=1
}

menu_packages() {
  local sel=${PKG_CATS[0]} c
  while true; do
    local -a items=(); local n tot
    for c in "${PKG_CATS[@]}"; do
      n=0; tot=0; local k d s
      while IFS='|' read -r k d s; do [[ -n $k ]] || continue; ((tot++)); [[ ${PSEL[$k]} == on ]] && ((n++)); done <<<"${CAT_PKGS[$c]}"
      items+=("$c" "${CAT_TITLE[$c]}  ($n/$tot)")
    done
    sel=$(dlg --title "Packages" --default-item "$sel" --cancel-label "Back" --menu "Pick a category:" 20 64 12 "${items[@]}") || return 0
    pick "${CAT_TITLE[$sel]}" "${CAT_PKGS[$sel]}" PSEL
  done
}

main_menu() {
  local sel=disk
  while true; do
    sel=$(dlg --title "Arch Linux Installer" --default-item "$sel" --cancel-label "Quit" \
      --menu "Go through each entry, then choose Install." 20 78 8 \
      disk "1. Disk       : ${DISK:-<not set>}" \
      sys  "2. System     : $HOST_NAME | $TZ_NAME | $LOCALE" \
      user "3. User       : ${USERNAME:-<not set>}" \
      pkgs "4. Packages   : $(count_on PSEL) selected" \
      svcs "5. Services   : $(count_on SSEL) to enable" \
      opts "6. Options    : $(count_on OSEL) active" \
      go   ">> Review and INSTALL") || { dialog --yesno "Quit the installer?" 6 30 >/dev/tty && exit 0; continue; }
    case $sel in
      disk) choose_disk ;;
      sys)  edit_system ;;
      user) edit_user ;;
      pkgs) menu_packages ;;
      svcs) pick "Services to enable at boot" "$SVC_LIST" SSEL ;;
      opts) pick "Options" "$OPT_LIST" OSEL ;;
      go)   review && return 0 ;;
    esac
  done
}

review() {
  [[ -n $DISK ]]              || { dialog --msgbox "Choose a disk first." 6 30 >/dev/tty; return 1; }
  [[ -n $USERNAME && $PASS_OK == 1 ]] || { dialog --msgbox "Set a username and password first." 6 40 >/dev/tty; return 1; }
  dialog --title "Summary" --yesno "Disk:     $DISK
Host:     $HOST_NAME   TZ: $TZ_NAME   Locale: $LOCALE
User:     $USERNAME
Packages: $(count_on PSEL)   Services: $(count_on SSEL)   Options: $(count_on OSEL)

Layout: 1G EFI + btrfs (zstd:1) with subvolumes
@ @home @log @snapshots @pkg @docker @ollama @libvirt

Continue?" 17 66 >/dev/tty || return 1
  dialog --colors --defaultno --title "\Z1WARNING: DATA LOSS\Zn" --yesno "\Z1\ZbALL DATA ON $DISK WILL BE PERMANENTLY ERASED.\Zn

$(lsblk -no NAME,SIZE,FSTYPE,LABEL "$DISK" | head -12)

Erase the disk and install Arch Linux?" 20 70 >/dev/tty
}

# ───────────────────────────── installation ───────────────────────────────────
run_install() {
  set -eE
  trap 'echo; echo "!!! FAILED at line $LINENO. See $LOG"; exit 1' ERR
  exec > >(tee -a "$LOG") 2>&1
  clear

  local p="" k
  [[ $DISK =~ (nvme|mmcblk|loop) ]] && p="p"
  local P1="${DISK}${p}1" P2="${DISK}${p}2"
  local O="noatime,compress=zstd:1,space_cache=v2"
  local CH="arch-chroot /mnt"

  echo "==> Partitioning $DISK"
  umount -R /mnt 2>/dev/null || true
  wipefs -af "$DISK"
  sgdisk -Z "$DISK"
  sgdisk -n1:0:+1G -t1:ef00 -n2:0:0 -t2:8300 "$DISK"
  partprobe "$DISK"; udevadm settle; sleep 1

  echo "==> Filesystems and subvolumes"
  mkfs.fat -F32 "$P1"
  mkfs.btrfs -f -L arch "$P2"
  mount "$P2" /mnt
  for s in @ @home @log @snapshots @pkg @docker @ollama @libvirt; do btrfs subvolume create /mnt/$s; done
  umount /mnt
  mount -o "$O,subvol=@" "$P2" /mnt
  for m in home:@home var/log:@log .snapshots:@snapshots var/cache/pacman/pkg:@pkg \
           var/lib/docker:@docker var/lib/ollama:@ollama var/lib/libvirt:@libvirt; do
    mount --mkdir -o "$O,subvol=${m#*:}" "$P2" "/mnt/${m%%:*}"
  done
  chattr +C /mnt/var/lib/libvirt
  mount --mkdir "$P1" /mnt/boot/efi

  echo "==> pacstrap"
  pacstrap -K /mnt $BASE_PKGS
  genfstab -U /mnt >> /mnt/etc/fstab

  echo "==> System config"
  $CH ln -sf "/usr/share/zoneinfo/$TZ_NAME" /etc/localtime
  $CH hwclock --systohc
  sed -i "s/^#\(${LOCALE} UTF-8\)/\1/" /mnt/etc/locale.gen
  $CH locale-gen
  echo "LANG=$LOCALE" > /mnt/etc/locale.conf
  echo "$HOST_NAME"   > /mnt/etc/hostname

  $CH useradd -mG wheel -s /bin/bash "$USERNAME"
  printf '%s:%s\n' "$USERNAME" "$USERPASS" | $CH chpasswd
  printf 'root:%s\n' "$ROOTPASS"            | $CH chpasswd
  echo '%wheel ALL=(ALL:ALL) ALL' > /mnt/etc/sudoers.d/10-wheel
  chmod 440 /mnt/etc/sudoers.d/10-wheel

  if [[ ${OSEL[multilib]} == on ]]; then
    sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /mnt/etc/pacman.conf
  fi
  # no *-debug split packages: they pin exact versions and block later AUR package swaps
  sed -i -E '/^OPTIONS=/ s/(^|[ (])!?debug/\1!debug/' /mnt/etc/makepkg.conf
  $CH pacman -Syu --noconfirm

  echo "==> GRUB"
  local rem=""; [[ ${OSEL[removable]} == on ]] && rem="--removable"
  $CH grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Arch $rem
  $CH grub-mkconfig -o /boot/grub/grub.cfg

  # temporary passwordless sudo for AUR builds
  echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /mnt/etc/sudoers.d/99-installer-tmp
  chmod 440 /mnt/etc/sudoers.d/99-installer-tmp

  local -a pk=()
  for k in "${!PSEL[@]}"; do [[ ${PSEL[$k]} == on ]] && pk+=("$k"); done

  if [[ ${OSEL[yay]} == on ]]; then
    echo "==> yay"
    $CH runuser -l "$USERNAME" -c 'cd ~ && rm -rf yay-bin && git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si --noconfirm && cd .. && rm -rf yay-bin'
  fi

  if ((${#pk[@]})); then
    echo "==> Installing ${#pk[@]} packages"
    if [[ ${OSEL[yay]} == on ]]; then
      $CH runuser -l "$USERNAME" -c "yay -S --needed --noconfirm --answerdiff None --answerclean None ${pk[*]}"
    else
      $CH pacman -S --needed --noconfirm "${pk[@]}"
    fi
  fi

  if [[ ${PSEL[ollama-rocm]:-off} == on ]]; then
    echo "==> Checking ollama-rocm backend"
    if $CH bash -c 'for f in /usr/lib/ollama/rocm_*/libggml-hip.so; do ldd "$f" 2>&1 | grep -q "not found" && exit 1; done; exit 0'; then
      echo "ollama-rocm backend loads fine."
    else
      echo "ollama-rocm backend is broken (missing libggml-base) -> installing $OLLAMA_PIN from the Arch archive"
      A=https://archive.archlinux.org/packages/o
      if $CH pacman -U --noconfirm "$A/ollama/ollama-$OLLAMA_PIN-x86_64.pkg.tar.zst" "$A/ollama-rocm/ollama-rocm-$OLLAMA_PIN-x86_64.pkg.tar.zst"; then
        if grep -q '^IgnorePkg' /mnt/etc/pacman.conf; then
          sed -i -E '/^IgnorePkg/ s/$/ ollama ollama-rocm/' /mnt/etc/pacman.conf
        else
          sed -i '/^\[options\]/a IgnorePkg = ollama ollama-rocm' /mnt/etc/pacman.conf
        fi
      else
        echo "WARNING: could not install the pinned version; Ollama will run on CPU until this is fixed."
      fi
    fi
  fi

  echo "==> Post-config"
  if [[ ${OSEL[greetcfg]} == on && ${PSEL[greetd]:-off} == on ]]; then
    local cmd="start-hyprland"; [[ -x /mnt/usr/bin/start-hyprland ]] || cmd="Hyprland"
    cat > /mnt/etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "tuigreet --remember --cmd $cmd"
user = "greeter"
EOF
  fi
  if [[ ${OSEL[groups]} == on ]]; then
    local g
    for g in render video docker libvirt; do
      getent group "$g" >/dev/null 2>&1 || grep -q "^$g:" /mnt/etc/group && $CH usermod -aG "$g" "$USERNAME"
    done
  fi
  if [[ ${OSEL[ollamachown]} == on ]] && grep -q '^ollama:' /mnt/etc/passwd; then
    $CH chown ollama:ollama /var/lib/ollama
    # the service runs as user "ollama": without render/video it silently falls back to CPU
    $CH usermod -aG render,video ollama
    mkdir -p /mnt/etc/systemd/system/ollama.service.d
    printf '[Service]\nSupplementaryGroups=render video\n' > /mnt/etc/systemd/system/ollama.service.d/gpu.conf
  fi
  if [[ ${OSEL[fishshell]} == on && ${PSEL[fish]:-off} == on ]]; then
    $CH chsh -s /usr/bin/fish "$USERNAME"
  fi
  if [[ ${OSEL[sleepmask]} == on ]]; then
    $CH systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
  fi

  echo "==> Enabling services"
  local u
  for u in "${!SSEL[@]}"; do
    [[ ${SSEL[$u]} == on ]] || continue
    local unit=$u; [[ $u == *.* ]] || unit="$u.service"
    if [[ -e /mnt/usr/lib/systemd/system/$unit || -e /mnt/etc/systemd/system/$unit ]]; then
      $CH systemctl enable "$unit"
    else
      echo "   skip $unit (not installed)"
    fi
  done

  rm -f /mnt/etc/sudoers.d/99-installer-tmp
  if [[ -n $POST_URL ]] && curl -fsSL "$POST_URL" -o "/mnt/home/$USERNAME/archpost.sh"; then
    $CH chown "$USERNAME:$USERNAME" "/home/$USERNAME/archpost.sh"
    $CH chmod +x "/home/$USERNAME/archpost.sh"
    echo "Part 2 saved to ~/archpost.sh"
  fi
  cp "$LOG" /mnt/home/"$USERNAME"/archinstall.log 2>/dev/null || true
  sync
  umount -R /mnt
  echo; echo "==> DONE"
}

# ───────────────────────────────── main ───────────────────────────────────────
main_menu
( run_install )
rc=$?
if ((rc == 0)); then
  dialog --msgbox "Installation finished.

Detach the ISO, then reboot.
Services are enabled and will start on first boot.
After logging into Hyprland, run: bash ~/archpost.sh
(Caelestia, snapper, containers, Ollama model)." 12 62 >/dev/tty
  dialog --yesno "Reboot now?" 6 24 >/dev/tty && reboot
else
  echo "Install failed (exit $rc). Log: $LOG"
fi
