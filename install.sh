#!/bin/bash

# ==========================================
# Linux Mint Post-Install Script (FINAL)
# ==========================================

LOGFILE="$HOME/mint-postinstall.log"
exec > >(tee -a "$LOGFILE") 2>&1

set -e
trap 'echo "❌ Script interrupted. Safe to rerun."' INT

echo "=========================================="
echo " Linux Mint Post-Install Tool"
echo " Log: $LOGFILE"
echo "=========================================="

# ------------------------------------------
# Argument handling
# ------------------------------------------

AUTO=false
FORCE_OFFLINE=false

for arg in "$@"; do
  case "$arg" in
    --yes|-y) AUTO=true ;;
    --offline) FORCE_OFFLINE=true ;;
  esac
done

# Detect curl | bash (no TTY)
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
# Helpers
# ------------------------------------------

confirm() {
  if $AUTO; then
    echo "✔ Auto-approved: $1"
    return 0
  fi
  read -rp "$1 [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

spinner() {
  local pid=$1
  local msg=$2
  local spin='-\|/'

  printf "%s " "$msg"
  while kill -0 "$pid" 2>/dev/null; do
    for i in {0..3}; do
      printf "\b${spin:$i:1}"
      sleep 0.1
    done
  done
  printf "\b✔\n"
}

check_net() {
  ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1
}

ONLINE=true
if $FORCE_OFFLINE || ! check_net; then
  ONLINE=false
  echo "⚠️ Offline mode active — network steps will be skipped"
fi

run_with_spinner() {
  ("$@") &
  spinner $! "➡️ $*"
}

# ------------------------------------------
# Update &
