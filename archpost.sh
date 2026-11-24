#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# Arch post-install (part 2). Run AFTER the first reboot, as your normal user,
# from a terminal INSIDE the Hyprland session (log in via tuigreet first):
#
#   curl -fsSL https://raw.githubusercontent.com/sharicov/archinstall/main/archpost.sh -o ~/archpost.sh && bash ~/archpost.sh
#
# Resumable: finished steps are remembered in ~/.local/state/archpost.done.
# Caelestia needs two passes: run once, log out and back in to the Caelestia
# shell, then run the same command again to finish the plugin step.
# ──────────────────────────────────────────────────────────────────────────────
set -u
[[ $EUID -ne 0 ]] || { echo "Run as your normal user, not root."; exit 1; }
STATE=$HOME/.local/state/archpost.done
mkdir -p "${STATE%/*}"; touch "$STATE"

sudo -v || exit 1
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
sudo pacman -S --needed --noconfirm dialog lua >/dev/null
command -v yay >/dev/null || { echo "yay not found (install it first)."; exit 1; }

# ══════════════════════════ EDIT YOUR DEFAULTS HERE ══════════════════════════
MODEL="qwen3.8:27b"   # change to any tag from ollama.com/library

STEP_LIST='services|Start and enable services|on
snapper|Configure snapper for / (+ snap-pac, timers)|on
caelestia|Caelestia: CLI, hypr-user.lua, caelestia install, hypr link|on
containers|Docker: Portainer + Open WebUI|on
ollama|Pull Ollama model|on
playwright|playwright install firefox|on
opencode|Install opencode (AI CLI for fixing the OS)|on
plugins|Caelestia shell plugins (needs 2nd pass inside Caelestia)|on'

SVC_LIST='sshd|SSH server|on
qemu-guest-agent|QEMU guest agent|on
fstrim.timer|Weekly TRIM|on
paccache.timer|Pacman cache cleanup|on
grub-btrfsd|Btrfs snapshots in GRUB menu|on
docker|Docker daemon|on
libvirtd|libvirt daemon|on
ollama|Ollama server|on'
# (greetd and NetworkManager are deliberately not here: restarting them would
#  kill your session or network.)
# ═════════════════════════════════════════════════════════════════════════════

declare -A STEP SVC
init_sel() { local -n S=$2; local k d s; while IFS='|' read -r k d s; do [[ -n $k ]] && S[$k]=$s; done <<<"$1"; }
init_sel "$STEP_LIST" STEP
init_sel "$SVC_LIST" SVC

done_before() { grep -qx "$1" "$STATE"; }
for k in "${!STEP[@]}"; do done_before "$k" && STEP[$k]=off; done
CAEL_PRE=0; done_before caelestia && CAEL_PRE=1
# plugin step only makes sense on the second pass
[[ $CAEL_PRE == 0 ]] && STEP[plugins]=off

dlg() { dialog "$@" 2>&1 >/dev/tty; }
pick() {  # pick "Title" "data" ARRAYNAME
  local title=$1 data=$2; local -n S=$3
  local -a args=(); local k d s out
  while IFS='|' read -r k d s; do [[ -n $k ]] && args+=("$k" "$d" "${S[$k]}"); done <<<"$data"
  out=$(dlg --separate-output --title "$title" --checklist "SPACE = toggle   ENTER = confirm" 22 76 14 "${args[@]}") || return 1
  while IFS='|' read -r k d s; do [[ -n $k ]] && S[$k]=off; done <<<"$data"
  while read -r k; do [[ -n $k ]] && S[$k]=on; done <<<"$out"
}

# ─────────────────────────────── TUI ──────────────────────────────────────────
pick "Post-install steps (done steps are off by default)" "$STEP_LIST" STEP || exit 0
WRITE_HYPR=0
if [[ ${STEP[services]} == on ]]; then pick "Services to enable and start now" "$SVC_LIST" SVC || exit 0; fi
if [[ ${STEP[caelestia]} == on ]]; then
  dialog --yesno "Write ~/.config/caelestia/hypr-user.lua (your keyboard layouts, monitors, workspaces)?\n\nAn existing file is backed up." 10 64 >/dev/tty && WRITE_HYPR=1
fi
if [[ ${STEP[ollama]} == on ]]; then
  MODEL=$(dlg --title "Ollama model" --inputbox "Model to pull:" 8 50 "$MODEL") || exit 0
fi
if [[ ${STEP[plugins]} == on ]]; then
  dialog --yesno "Plugin step: are you logged into the Caelestia shell session right now?" 7 60 >/dev/tty || STEP[plugins]=off
fi
clear

# ─────────────────────────────── steps ────────────────────────────────────────
step_services() {
  local u
  for u in "${!SVC[@]}"; do
    [[ ${SVC[$u]} == on ]] || continue
    if systemctl cat "$u" &>/dev/null; then
      sudo systemctl enable --now "$u" || echo "   warning: could not enable/start $u"
    else
      echo "   skip $u (not installed)"
    fi
  done
}

step_snapper() {
  yay -S --needed --noconfirm snapper snap-pac
  if sudo snapper list-configs | grep -q '^root'; then echo "root config already exists"; return 0; fi
  # standard procedure when /.snapshots is already a separate subvolume (@snapshots)
  mountpoint -q /.snapshots && sudo umount /.snapshots
  sudo rmdir /.snapshots
  sudo snapper -c root create-config /
  sudo btrfs subvolume delete /.snapshots
  sudo mkdir /.snapshots
  sudo mount -a
  sudo chmod 750 /.snapshots
  sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
  sudo snapper -c root list
}

step_caelestia() {
  [[ -n ${WAYLAND_DISPLAY:-} ]] || { echo "Run this from a terminal inside the Hyprland session."; exit 1; }
  yay -S --needed --noconfirm caelestia-cli
  if [[ $WRITE_HYPR == 1 ]]; then
    local f=$HOME/.config/caelestia/hypr-user.lua
    mkdir -p "${f%/*}"
    [[ -e $f ]] && cp "$f" "$f.bak.$(date +%s)"
    cat > "$f" <<'EOF'
-- ── Keyboard Layouts ──────────────────────────────────────────────
hl.config({
    input = {
        kb_layout = "us,ru,il",
        kb_variant = ",phonetic,",
        kb_options = "grp:alt_shift_toggle"
    }
})

-- ── Monitors ──────────────────────────────────────────────────────
-- 4K Hisense monitor, left side
hl.monitor({
    output = "HDMI-A-1",
    mode = "3840x2160@60",
    position = "0x0",
    scale = 1
})

-- LG Ultrawide to the right, aligned at the bottom
hl.monitor({
    output = "DP-1",
    mode = "2560x1080@75",
    position = "3840x1080",
    scale = 1
})

-- ── Workspaces (rules incl. per-monitor borders and gaps) ─────────
hl.workspace_rule({
    workspace = "1",
    monitor = "HDMI-A-1",
    border_size = 2,
    gaps_in = 2,
    gaps_out = 5
})

hl.workspace_rule({
    workspace = "2",
    monitor = "DP-1",
    border_size = 1,
    gaps_in = 1,
    gaps_out = 3
})

-- ── XWayland Primary Display Fix ──────────────────────────────────
-- Forces games running under XWayland to open on the 4K Hisense
hl.on("hyprland.start", function()
    hl.exec_cmd("xrandr --output HDMI-A-1 --primary")
end)

-- ── Middle Mouse copy paste ───────────────────────────────────────
hl.config({
    misc = {
        middle_click_paste = true
    }
})

-- Resize borders
hl.config({
    general = {
        resize_on_border = true,
        extend_border_grab_area = 15,
    },
})
EOF
    luac -p "$f"
    echo "hypr-user.lua syntax OK"
  fi

  caelestia install

  local H=$HOME/.config/hypr T=$HOME/.local/state/caelestia/dots/hypr
  [[ -d $T ]] || { echo "Missing $T (did caelestia install finish?)"; exit 1; }
  if [[ ( -e $H || -L $H ) && $(readlink -f "$H") != "$(readlink -f "$T")" ]]; then
    mv "$H" "$H.bak.$(date +%s)"
  fi
  [[ -L $H ]] || ln -s "$T" "$H"
  echo "~/.config/hypr -> $T"
}

step_containers() {
  local D=docker
  docker info &>/dev/null || D="sudo docker"
  $D ps -a --format '{{.Names}}' | grep -qx portainer || \
    $D run -d --name portainer --restart=always -p 9443:9443 \
      -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce
  $D ps -a --format '{{.Names}}' | grep -qx open-webui || \
    $D run -d --name open-webui --restart=always --network=host \
      -e OLLAMA_BASE_URL=http://127.0.0.1:11434 -v open-webui:/app/backend/data \
      ghcr.io/open-webui/open-webui:main
  echo "Open WebUI: http://localhost:8080   Portainer: https://localhost:9443"
}

step_ollama() {
  systemctl is-active --quiet ollama || sudo systemctl enable --now ollama
  local i
  for i in {1..30}; do curl -fs http://127.0.0.1:11434 >/dev/null && break; sleep 1; done
  ollama pull "$MODEL"
  ollama ps
}

step_playwright() { playwright install firefox; }

step_opencode() {
  curl -fsSL https://opencode.ai/install | bash
  command -v fish >/dev/null && fish -c "fish_add_path $HOME/.opencode/bin" || true
}

step_plugins() {
  # interactive on purpose: accept removal of conflicting packages when asked
  if pacman -Q caelestia-shell-debug &>/dev/null; then sudo pacman -R caelestia-shell-debug; fi
  yay -S caelestia-shell-plugins-git
  caelestia shell -d && caelestia-shell -k
}

# ─────────────────────────────── run ──────────────────────────────────────────
declare -a RESULT=()
for id in services snapper caelestia containers ollama playwright opencode plugins; do
  [[ ${STEP[$id]} == on ]] || continue
  echo; echo "════════ $id ════════"
  ( set -eEuo pipefail; "step_$id" ); rc=$?
  if ((rc == 0)); then echo "$id" >> "$STATE"; RESULT+=("OK    $id"); else RESULT+=("FAIL  $id"); fi
done

echo; echo "════════ Summary ════════"
printf '%s\n' "${RESULT[@]}"
if done_before caelestia && ! done_before plugins; then
  echo
  echo "NEXT: log out and back in so the Caelestia shell starts, then run this script again"
  echo "      to finish the plugin step. Failed steps can be retried the same way."
fi
