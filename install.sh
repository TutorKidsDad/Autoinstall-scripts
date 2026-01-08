#!/bin/bash

# =====================================
# Linux Mint Post-Install Script
# =====================================

LOGFILE="$HOME/mint-postinstall.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "====================================="
echo " Linux Mint Post-Install Tool"
echo " Log file: $LOGFILE"
echo "====================================="

# -------------------------------
# Safety checks
# -------------------------------

if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root:"
  echo "   sudo bash install.sh"
  exit 1
fi

if ! grep -qi "linux mint" /etc/os-release; then
  echo "❌ This script is for Linux Mint only."
  exit 1
fi

pause() {
  read -rp "Press ENTER to continue or Ctrl+C to cancel..."
}

confirm() {
  read -rp "$1 [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

pause

# -------------------------------
# Update & Upgrade
# -------------------------------

if confirm "➡️ Update & upgrade system?"; then
  apt update && apt upgrade -y
fi

# -------------------------------
# GRUB Silent Boot
# -------------------------------

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

# -------------------------------
# LibreOffice Cleanup
# -------------------------------

if confirm "➡️ Remove preinstalled LibreOffice (APT)?"; then
  apt remove --purge libreoffice* -y
  apt autoremove --purge -y
fi

# -------------------------------
# LibreOffice Latest (Official)
# -------------------------------

if confirm "➡️ Install latest LibreOffice (official DEB)?"; then
  TMP="/tmp/libreoffice"
  mkdir -p "$TMP"
  cd "$TMP"

  wget -q --show-progress \
  https://download.documentfoundation.org/libreoffice/stable/25.8.4/deb/x86_64/LibreOffice_25.8.4_Linux_x86-64_deb.tar.gz

  tar -xf LibreOffice_*.tar.gz
  cd LibreOffice_*_Linux_x86-64_deb/DEBS
  dpkg -i *.deb || apt -f install -y
fi

# -------------------------------
# Stacer (APT only)
# -------------------------------

if confirm "➡️ Install Stacer (APT)?"; then
  apt install stacer -y
fi

# -------------------------------
# Flatpak + Flathub
# -------------------------------

if confirm "➡️ Install Flatpak & Flathub?"; then
  apt install flatpak -y
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

# -------------------------------
# Flatpak Applications
# -------------------------------

if confirm "➡️ Install apps via Flatpak?"; then
  flatpak install -y flathub \
    org.gnome.Boxes \
    com.obsproject.Studio \
    org.kde.kdenlive \
    org.audacityteam.Audacity \
    org.onlyoffice.desktopeditors
fi

echo "====================================="
echo " ✅ Setup completed successfully!"
echo " 📄 Log saved at:"
echo "    $LOGFILE"
echo " 🔁 Reboot recommended"
echo "====================================="
