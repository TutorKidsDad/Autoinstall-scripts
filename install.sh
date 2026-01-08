#!/bin/bash

# ==========================================
# Linux Mint Post-Install Script (Resilient)
# ==========================================

LOGFILE="$HOME/mint-postinstall.log"
exec > >(tee -a "$LOGFILE") 2>&1

set -e
trap 'echo "❌ Script interrupted. Safe to rerun later."' INT

echo "=========================================="
echo " Linux Mint Post-Install Tool"
echo " Log: $LOGFILE"
echo "=========================================="

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
# Helpers
# ------------------------------------------

pause() {
  read -rp "Press ENTER to continue or Ctrl+C to cancel..."
}

confirm() {
  read -rp "$1 [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

check_net() {
  ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1
}

retry_cmd() {
  local retries=3
  local count=1
  until "$@"; do
    if [ "$count" -ge "$retries" ]; then
      echo "❌ Failed after $retries attempts: $*"
      return 1
    fi
    echo "🔁 Retry $count/$retries..."
    count=$((count + 1))
    sleep 3
  done
}

ONLINE=true
if ! check_net; then
  ONLINE=false
  echo "⚠️ No internet detected — entering OFFLINE-SKIP mode"
fi

pause

# ------------------------------------------
# Update & Upgrade
# ------------------------------------------

if confirm "➡️ Update & upgrade system?"; then
  if $ONLINE; then
    retry_cmd apt update
    retry_cmd apt upgrade -y
  else
    echo "⚠️ Skipped (offline)"
  fi
fi

# ------------------------------------------
# GRUB Silent Boot
# ------------------------------------------

if confirm "➡️ Apply silent boot (GRUB) settings?"; then
  echo "📦 Backing up GRUB config..."
  cp /etc/default/grub /etc/default/grub.backup

  sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
  sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
  sed -i 's/^GRUB_RECORDFAIL_TIMEOUT=.*/GRUB_RECORDFAIL_TIMEOUT=0/' /etc/default/grub
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=0 vt.global_cursor_default=0"/' /etc/default/grub
  sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=""/' /etc/default/grub

  update-grub
fi

# ------------------------------------------
# LibreOffice Removal
# ------------------------------------------

if confirm "➡️ Remove preinstalled LibreOffice (APT)?"; then
  apt remove --purge libreoffice* -y || true
  apt autoremove --purge -y || true
fi

# ------------------------------------------
# LibreOffice Latest (Official)
# ------------------------------------------

if confirm "➡️ Install latest LibreOffice (official DEB)?"; then
  if $ONLINE; then
    TMP="/tmp/libreoffice"
    mkdir -p "$TMP"
    cd "$TMP"

    retry_cmd wget --timeout=20 --tries=3 --show-progress \
      https://download.documentfoundation.org/libreoffice/stable/25.8.4/deb/x86_64/LibreOffice_25.8.4_Linux_x86-64_deb.tar.gz

    tar -xf LibreOffice_*.tar.gz
    cd LibreOffice_*_Linux_x86-64_deb/DEBS
    dpkg -i *.deb || apt -f install -y
  else
    echo "⚠️ Skipped LibreOffice install (offline)"
  fi
fi

# ------------------------------------------
# Stacer (APT)
# ------------------------------------------

if confirm "➡️ Install Stacer (APT)?"; then
  if $ONLINE; then
    retry_cmd apt install stacer -y
  else
    echo "⚠️ Skipped Stacer install (offline)"
  fi
fi

# ------------------------------------------
# Flatpak + Flathub
# ------------------------------------------

if confirm "➡️ Install Flatpak & Flathub?"; then
  if $ONLINE; then
    retry_cmd apt install flatpak -y
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  else
    echo "⚠️ Skipped Flatpak setup (offline)"
  fi
fi

# ------------------------------------------
# Flatpak Applications
# ------------------------------------------

if confirm "➡️ Install apps via Flatpak?"; then
  if $ONLINE; then
    retry_cmd flatpak install -y flathub \
      org.gnome.Boxes \
      com.obsproject.Studio \
      org.kde.kdenlive \
      org.audacityteam.Audacity \
      org.onlyoffice.desktopeditors
  else
    echo "⚠️ Skipped Flatpak apps (offline)"
  fi
fi

echo "=========================================="
echo " ✅ Setup complete!"
echo " 📄 Log file:"
echo "    $LOGFILE"
echo " 🔁 Reboot recommended"
echo "=========================================="
