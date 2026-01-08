#!/usr/bin/env bash
set -Eeuo pipefail

### ================= CONFIG =================
LOG="/root/mint-postinstall.log"
AUTO=false
OFFLINE=false
COUNTDOWN=8
RAN=()
SKIPPED=()
FAILED=()
### ==========================================

exec > >(tee -a "$LOG") 2>&1

### ================= FLAGS ==================
for arg in "$@"; do
  case "$arg" in
    --yes) AUTO=true ;;
    --offline) OFFLINE=true ;;
  esac
done

### ================= UTILS ==================
countdown() {
  echo
  echo "⏳ Auto-continue in $COUNTDOWN seconds (Ctrl+C to cancel)"
  for ((i=COUNTDOWN; i>0; i--)); do
    printf "\rStarting in %s..." "$i"
    sleep 1
  done
  echo
}

network_ok() {
  ping -c1 -W2 8.8.8.8 &>/dev/null
}

retry() {
  for i in 1 2 3; do
    "$@" && return 0
    echo "⚠️ Retry $i failed, retrying..."
    sleep 4
  done
  return 1
}

### ================= CHECKS =================
clear
echo "=========================================="
echo " Linux Mint Post-Install Tool"
echo " Log: $LOG"
echo "=========================================="

if [[ $EUID -ne 0 ]]; then
  echo "❌ Run as root (sudo)"
  exit 1
fi

if ! grep -qi "linux mint" /etc/os-release; then
  echo "❌ This script supports Linux Mint ONLY"
  exit 1
fi

if ! $OFFLINE && network_ok; then
  ONLINE=true
else
  ONLINE=false
  echo "⚠️ Offline mode active"
fi

export XDG_DATA_DIRS="/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"

countdown

### ================= TASKS ==================

update_upgrade() {
  $ONLINE || { SKIPPED+=("Update & upgrade (offline)"); return; }
  apt update && apt upgrade -y \
    && RAN+=("System update & upgrade") \
    || FAILED+=("Update & upgrade")
}

configure_grub() {
  echo "⚙ Configuring GRUB..."
  cat > /etc/default/grub <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_RECORDFAIL_TIMEOUT=0
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=0 vt.global_cursor_default=0"
GRUB_CMDLINE_LINUX=""
EOF
  update-grub && RAN+=("GRUB optimized") || FAILED+=("GRUB config")
}

remove_libreoffice() {
  apt remove --purge libreoffice* -y
  apt autoremove --purge -y
  RAN+=("LibreOffice removed")
}

install_libreoffice_latest() {
  $ONLINE || { SKIPPED+=("LibreOffice install (offline)"); return; }

  tmp=$(mktemp -d)
  cd "$tmp"
  echo "📥 Downloading LibreOffice 25.8.4..."
  retry wget --timeout=20 https://download.documentfoundation.org/libreoffice/stable/25.8.4/deb/x86_64/LibreOffice_25.8.4_Linux_x86-64_deb.tar.gz \
    || { FAILED+=("LibreOffice download"); return; }

  echo "📦 Extracting..."
  tar xf LibreOffice_*.tar.gz

  echo "⚙ Installing LibreOffice..."
  dpkg -i LibreOffice_*_Linux_x86-64_deb/DEBS/*.deb || apt -f install -y
  RAN+=("LibreOffice 25.8.4 installed")

  cd -
  rm -rf "$tmp"
}

install_flatpak_apps() {
  $ONLINE || { SKIPPED+=("Flatpak apps (offline)"); return; }

  echo
  echo "📦 Installing Flatpak applications"
  echo "⏳ Large runtimes (1–3 GB). Network speed may fluctuate."

  apt install -y flatpak ca-certificates

  # ---- SAFETY: ensure certs are fresh ----
  update-ca-certificates

  # ---- Check if flathub already exists ----
  if flatpak remotes | grep -q flathub; then
    echo "✔ Flathub already configured"
  else
    echo "➕ Adding Flathub remote"

    # Retry repo add (SSL can fail temporarily)
    if ! retry flatpak remote-add --if-not-exists flathub \
      https://flathub.org/repo/flathub.flatpakrepo; then
      FAILED+=("Flathub repo (SSL/network)")
      echo "❌ Unable to add Flathub — skipping Flatpak apps"
      return
    fi
  fi

  # ---- PERFORMANCE & STABILITY ----
  # ---- Disable deltas ONLY if supported (Flatpak ≥ 1.15) ----
if flatpak config --help 2>/dev/null | grep -q disable-delta; then
  echo "⚙ Disabling Flatpak delta downloads (supported)"
  flatpak config --system --set disable-delta true
else
  echo "ℹ Flatpak delta control not supported on this version — skipping"
fi

  export G_MESSAGES_DEBUG=none
  export FLATPAK_HTTP_TIMEOUT=300
  export GIO_USE_PROXY_RESOLVER=0

  local USER_RUN="${SUDO_USER:-$USER}"

  echo "⬇ Installing Flatpak apps (single transaction)"

  if sudo -u "$USER_RUN" flatpak install -y flathub \
    org.gnome.Boxes \
    com.obsproject.Studio \
    org.kde.kdenlive \
    org.audacityteam.Audacity \
    org.onlyoffice.desktopeditors; then
      RAN+=("Flatpak apps installed")
  else
      FAILED+=("Flatpak apps install")
  fi
}


### ================= MENU ===================

show_menu() {
  echo
  echo "1) Update & upgrade system"
  echo "2) Optimize GRUB (hidden boot)"
  echo "3) Remove LibreOffice"
  echo "4) Install LibreOffice 25.8.4"
  echo "5) Install Flatpak apps (Boxes, OBS, Kdenlive, Audacity, ONLYOFFICE)"
  echo "6) Run EVERYTHING"
  echo "0) Exit"
}

run_all() {
  update_upgrade
  configure_grub
  remove_libreoffice
  install_libreoffice_latest
  install_flatpak_apps
}

if $AUTO; then
  run_all
else
  while true; do
    show_menu
    read -rp "Choose option: " choice
    case "$choice" in
      1) update_upgrade ;;
      2) configure_grub ;;
      3) remove_libreoffice ;;
      4) install_libreoffice_latest ;;
      5) install_flatpak_apps ;;
      6) run_all ;;
      0) break ;;
      *) echo "Invalid option" ;;
    esac
  done
fi

### ================= SUMMARY =================

echo
echo "=========================================="
echo " ✅ Setup complete!"
echo "=========================================="

[[ ${#RAN[@]} -gt 0 ]] && echo "✔ Completed:" && printf "  - %s\n" "${RAN[@]}"
[[ ${#SKIPPED[@]} -gt 0 ]] && echo "⚠ Skipped:" && printf "  - %s\n" "${SKIPPED[@]}"
[[ ${#FAILED[@]} -gt 0 ]] && echo "❌ Failed:" && printf "  - %s\n" "${FAILED[@]}"

echo
echo "📄 Log file: $LOG"
echo "🔁 Reboot recommended"
echo "=========================================="
