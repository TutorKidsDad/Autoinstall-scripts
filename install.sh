#!/bin/bash

# ==========================================
# Linux Mint Post-Install Script (FINAL UX)
# ==========================================

LOGFILE="$HOME/mint-postinstall.log"
exec > >(tee -a "$LOGFILE") 2>&1

set -e
trap 'echo -e "\n❌ Script interrupted. Safe to rerun later."' INT

# ------------------------------------------
# Globals
# ------------------------------------------

AUTO=false
FORCE_OFFLINE=false
COUNTDOWN=10

RAN=()
SKIPPED=()

# ------------------------------------------
# Arguments
# ------------------------------------------

for arg in "$@"; do
  case "$arg" in
    --yes|-y) AUTO=true ;;
    --offline) FORCE_OFFLINE=true ;;
  esac
done

# Detect curl | bash
if [ ! -t 0 ]; then
  AUTO=true
  echo "⚠️ No TTY detected (curl | bash mode)"
  echo "➡️ AUTO mode enabled"
fi

# ------------------------------------------
# Safety checks
# ------------------------------------------

if [ "$EUID" -ne 0 ]; then
  echo "❌ Run as root:"
  echo "   sudo bash install.sh"
  exit 1
fi

if ! grep -qi "linux mint" /etc/os-release; then
  echo "❌ This script supports Linux Mint only."
  exit 1
fi

# ------------------------------------------
# Network
# ------------------------------------------

check_net() {
  ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1
}

ONLINE=true
if $FORCE_OFFLINE || ! check_net; then
  ONLINE=false
  echo "⚠️ Offline mode active"
fi

# ------------------------------------------
# Countdown
# ------------------------------------------

countdown() {
  for ((i=COUNTDOWN; i>0; i--)); do
    printf "\r➡️ Starting in %d seconds... (Ctrl+C to cancel)" "$i"
    sleep 1
  done
  echo
}

# ------------------------------------------
# Menu
# ------------------------------------------

show_menu() {
  echo
  echo "========== Linux Mint Setup Menu =========="
  echo "1) System update & upgrade"
  echo "2) Apply silent boot (GRUB)"
  echo "3) Remove APT LibreOffice"
  echo "4) Install latest LibreOffice (official)"
  echo "5) Install Stacer (APT)"
  echo "6) Install Flatpak & apps"
  echo "7) Run EVERYTHING"
  echo "0) Exit"
  echo "==========================================="
}

# ------------------------------------------
# Actions
# ------------------------------------------

update_system() {
  if $ONLINE; then
    apt update && apt upgrade -y
    RAN+=("System update & upgrade")
  else
    SKIPPED+=("System update (offline)")
  fi
}

grub_silent() {
  cp /etc/default/grub /etc/default/grub.backup
  sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
  sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
  sed -i 's/^GRUB_RECORDFAIL_TIMEOUT=.*/GRUB_RECORDFAIL_TIMEOUT=0/' /etc/default/grub
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=0 vt.global_cursor_default=0"/' /etc/default/grub
  sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=""/' /etc/default/grub
  update-grub
  RAN+=("Silent boot (GRUB)")
}

remove_lo() {
  apt remove --purge libreoffice* -y || true
  apt autoremove --purge -y || true
  RAN+=("Removed LibreOffice (APT)")
}

install_lo() {
  if $ONLINE; then
    TMP="/tmp/libreoffice"
    mkdir -p "$TMP"
    cd "$TMP"
    wget --tries=3 --timeout=20 --show-progress \
      https://download.documentfoundation.org/libreoffice/stable/25.8.4/deb/x86_64/LibreOffice_25.8.4_Linux_x86-64_deb.tar.gz
    tar -xf LibreOffice_*.tar.gz
    cd LibreOffice_*_Linux_x86-64_deb/DEBS
    dpkg -i *.deb || apt -f install -y
    RAN+=("Installed LibreOffice (official)")
  else
    SKIPPED+=("LibreOffice install (offline)")
  fi
}

install_stacer() {
  if $ONLINE; then
    apt install stacer -y
    RAN+=("Installed Stacer")
  else
    SKIPPED+=("Stacer (offline)")
  fi
}

install_apps() {
  if $ONLINE; then
    apt install flatpak -y
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install -y flathub \
      org.gnome.Boxes \
      com.obsproject.Studio \
      org.kde.kdenlive \
      org.audacityteam.Audacity \
      org.onlyoffice.desktopeditors
    RAN+=("Flatpak apps installed")
  else
    SKIPPED+=("Flatpak apps (offline)")
  fi
}

# ------------------------------------------
# Execution
# ------------------------------------------

echo
echo "Linux Mint Post-Install Tool"
echo "Log: $LOGFILE"

if $AUTO; then
  echo "AUTO MODE — running everything"
  countdown
  update_system
  grub_silent
  remove_lo
  install_lo
  install_stacer
  install_apps
else
  while true; do
    show_menu
    read -rp "Choose an option: " choice
    case $choice in
      1) update_system ;;
      2) grub_silent ;;
      3) remove_lo ;;
      4) install_lo ;;
      5) install_stacer ;;
      6) install_apps ;;
      7)
         countdown
         update_system
         grub_silent
         remove_lo
         install_lo
         install_stacer
         install_apps
         ;;
      0) break ;;
      *) echo "Invalid choice" ;;
    esac
  done
fi

# ------------------------------------------
# Summary
# ------------------------------------------

echo
echo "============= SUMMARY ============="
echo "✔ Completed:"
for i in "${RAN[@]}"; do echo "  - $i"; done

if [ "${#SKIPPED[@]}" -gt 0 ]; then
  echo
  echo "⚠️ Skipped:"
  for i in "${SKIPPED[@]}"; do echo "  - $i"; done
fi

echo
echo "📄 Log file: $LOGFILE"
echo "🔁 Reboot recommended"
echo "==================================="
