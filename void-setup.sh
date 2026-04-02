#!/bin/bash
# ============================================================
#  void-setup.sh — Minimales Void Linux Post-Install Setup
#  fuer dots-hyprland (end-4)
#
#  Enthaelt: Internet, Bluetooth, Audio, Dateimanager,
#            Schriftarten, Display Manager, Build-Tools,
#            Wayland/Hyprland-Basis
#
#  Ausfuehren als normaler User (sudo wird intern genutzt):
#    chmod +x void-setup.sh && ./void-setup.sh
# ============================================================

set -e

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[0;34m'
NC='\033[0m'

step() { echo -e "\n${BLU}==>${NC} ${GRN}$1${NC}"; }
warn() { echo -e "${YLW}[WARN]${NC} $1"; }
ok()   { echo -e "${GRN}[OK]${NC} $1"; }

# Sicherheitscheck
if [ "$EUID" -eq 0 ]; then
  echo -e "${RED}Bitte NICHT als root ausfuehren. Das Skript nutzt sudo intern.${NC}"
  exit 1
fi

echo -e "${BLU}"
echo "==========================================================="
echo "    Void Linux Minimal Setup for dots-hyprland             "
echo "==========================================================="
echo -e "${NC}"

# ── Schritt 0: xbps updaten & Repos einrichten ───────────────
step "Schritt 0: xbps self-update & Repos synchronisieren"
sudo xbps-install -u xbps
sudo xbps-install -S

step "Nonfree-Repo aktivieren"
sudo xbps-install -y void-repo-nonfree 2>/dev/null || true
sudo xbps-install -S

# ── Schritt 1: System-Upgrade ────────────────────────────────
step "Schritt 1: Vollstaendiges System-Upgrade"
sudo xbps-install -Syu

# ── Schritt 2: Basis & Build-Tools ───────────────────────────
step "Schritt 2: Basis-Tools & Build-Umgebung"
sudo xbps-install -y \
  base-devel git curl wget rsync unzip tar xz \
  cmake ninja meson pkg-config autoconf automake libtool \
  gcc clang make \
  bash-completion fish-shell \
  vim nano less man-db \
  htop btop tree fd ripgrep jq bc \
  rustup

# ── Schritt 3: Internet / Netzwerk ───────────────────────────
step "Schritt 3: Netzwerk (NetworkManager)"
sudo xbps-install -y \
  NetworkManager \
  network-manager-applet \
  iw wpa_supplicant \
  nss-mdns

warn "Entferne konfliktierende Netzwerk-Services (dhcpcd, wpa_supplicant)..."
sudo rm -f /var/service/dhcpcd 2>/dev/null || true
sudo rm -f /var/service/wpa_supplicant 2>/dev/null || true

step "dbus & NetworkManager als runit-Services aktivieren"
sudo ln -sf /etc/sv/dbus           /var/service/ 2>/dev/null || true
sudo ln -sf /etc/sv/NetworkManager /var/service/ 2>/dev/null || true
sudo usermod -aG network "$USER"
ok "NetworkManager aktiviert. '$USER' zur Gruppe 'network' hinzugefuegt."

# ── Schritt 4: Bluetooth ─────────────────────────────────────
step "Schritt 4: Bluetooth (bluez + blueman)"
sudo xbps-install -y bluez blueman
sudo ln -sf /etc/sv/bluetoothd /var/service/ 2>/dev/null || true
sudo usermod -aG bluetooth "$USER"
ok "bluetoothd aktiviert. '$USER' zur Gruppe 'bluetooth' hinzugefuegt."

# ── Schritt 5: Audio (Pipewire) ──────────────────────────────
step "Schritt 5: Audio (Pipewire + WirePlumber)"
sudo xbps-install -y \
  pipewire wireplumber \
  pipewire-pulse pipewire-alsa pipewire-jack \
  alsa-utils \
  pavucontrol-qt \
  playerctl \
  cava

# ── Schritt 6: Session-Management ────────────────────────────
step "Schritt 6: Session-Management (elogind + seatd + polkit)"
sudo xbps-install -y elogind seatd polkit polkit-gnome gnome-keyring

sudo ln -sf /etc/sv/elogind /var/service/ 2>/dev/null || true
sudo ln -sf /etc/sv/seatd   /var/service/ 2>/dev/null || true

sudo usermod -aG _seatd,audio,video,input,optical,storage,disk,kvm "$USER"
ok "Session-Services aktiviert. '$USER' zu allen relevanten Gruppen hinzugefuegt."

# ── Schritt 7: Grafik (Wayland + Mesa) ───────────────────────
step "Schritt 7: Grafik-Treiber & Wayland-Basis"
sudo xbps-install -y \
  mesa mesa-dri mesa-vulkan-overlay \
  vulkan-loader \
  mesa-vulkan-radeon mesa-vulkan-intel \
  libdrm libdrm-devel \
  wayland wayland-protocols wayland-devel \
  xwayland \
  linux-firmware linux-firmware-network

warn "GPU-spezifisch: NVIDIA -> 'sudo xbps-install nvidia' (nonfree-Repo noetig)."
warn "               AMD   -> mesa-vulkan-radeon genuegt bereits."
warn "               Intel -> mesa-vulkan-intel genuegt bereits."

# ── Schritt 8: Display Manager (SDDM) ────────────────────────
step "Schritt 8: Display Manager (SDDM)"
sudo xbps-install -y sddm qt5-graphicaleffects qt5-quickcontrols2 qt5-svg
sudo ln -sf /etc/sv/sddm /var/service/ 2>/dev/null || true
ok "SDDM aktiviert."

# ── Schritt 9: Dateimanager & Desktop-Utilities ──────────────
step "Schritt 9: Dateimanager (Thunar + Dolphin) & Desktop-Utilities"
sudo xbps-install -y \
  thunar thunar-archive-plugin thunar-media-tags-plugin \
  dolphin \
  gvfs gvfs-mtp gvfs-gphoto2 gvfs-smb \
  file-roller \
  xdg-user-dirs xdg-utils \
  udisks2 ntfs-3g dosfstools \
  p7zip zip unzip

xdg-user-dirs-update
ok "Dateimanager installiert. XDG-Verzeichnisse erstellt."

# ── Schritt 10: Fonts ─────────────────────────────────────────
step "Schritt 10: Schriftarten"
sudo xbps-install -y \
  nerd-fonts-symbols-ttf \
  dejavu-fonts-ttf \
  liberation-fonts-ttf \
  noto-fonts-ttf \
  noto-fonts-emoji \
  fontconfig

fc-cache -fv
ok "Fonts installiert und Cache aktualisiert."

# ── Schritt 11: Qt6 & GTK4 ───────────────────────────────────
step "Schritt 11: Qt6 / GTK4 & Theme-Infrastruktur"
sudo xbps-install -y \
  qt6-base qt6-declarative qt6-wayland qt6-wayland-tools \
  qt6-svg qt6-tools qt6-multimedia qt6-imageformats \
  qt6-5compat qt6-sensors qt6-positioning \
  qt6-virtualkeyboard qt6-quicktimeline qt6-translations \
  qt5ct qt6ct \
  gtk4 libadwaita libsoup3 \
  gobject-introspection \
  libportal libportal-gtk4 \
  adwaita-icon-theme adw-gtk3 \
  breeze breeze-icons \
  glib glib-devel

# ── Schritt 12: Wayland-Tools & XDG-Portal ───────────────────
step "Schritt 12: Wayland-Tools & XDG-Portal"
sudo xbps-install -y \
  wl-clipboard cliphist wtype \
  grim slurp swappy \
  brightnessctl \
  fuzzel \
  xdg-desktop-portal xdg-desktop-portal-gtk \
  imagemagick \
  jemalloc jemalloc-devel

# ── Schritt 13: Python & Node ────────────────────────────────
step "Schritt 13: Python & Node.js"
sudo xbps-install -y \
  python3 python3-devel python3-pip \
  python3-gobject python3-gobject-devel \
  python3-Pillow python3-psutil \
  nodejs npm

# ── Schritt 14: Inoffizielle Hyprland-Repos ──────────────────
step "Schritt 14: Inoffizielle Hyprland-Repos hinzufuegen"

echo "repository=https://raw.githubusercontent.com/Makrennel/hyprland-void/repository-x86_64-glibc" \
  | sudo tee /etc/xbps.d/10-hyprland-makrennel.conf

echo "repository=https://github.com/void-land/hyprland-void-packages/releases/latest/download/" \
  | sudo tee /etc/xbps.d/11-hyprland-void-land.conf

sudo xbps-install -S
ok "Hyprland-Repos hinzugefuegt. Fingerprint bei Aufforderung bestaetigen!"

# ── Schritt 15: Hyprland & Hypr-Suite ───────────────────────
step "Schritt 15: Hyprland & Hypr-Suite installieren"
sudo xbps-install -y \
  hyprland \
  hyprland-protocols \
  hyprcursor \
  hypridle \
  hyprlang \
  hyprlock \
  hyprpaper \
  hyprutils \
  xdg-desktop-portal-hyprland

# ── Abschluss ────────────────────────────────────────────────
echo ""
echo -e "${GRN}==========================================================="
echo "    Setup abgeschlossen! Bitte rebooten.                  "
echo "===========================================================${NC}"
echo ""
echo -e "${YLW}Naechste Schritte fuer dots-hyprland:${NC}"
echo "  1. Neu starten:  sudo reboot"
echo ""
echo "  2. Quickshell aus Quellcode bauen (nach Neustart):"
echo "     rustup-init -y && source ~/.cargo/env && rustup default stable"
echo "     git clone https://git.outfoxxed.me/quickshell/quickshell.git ~/build/quickshell"
echo "     cd ~/build/quickshell && just release && sudo just install"
echo ""
echo "  3. matugen installieren:"
echo "     cargo install matugen"
echo "     sudo cp ~/.cargo/bin/matugen /usr/local/bin/"
echo ""
echo "  4. dots-hyprland klonen und installieren:"
echo "     git clone https://github.com/end-4/dots-hyprland.git ~/.cache/dots-hyprland"
echo "     cd ~/.cache/dots-hyprland && ./setup install"
echo ""
echo -e "${YLW}Aktivierte runit-Services:${NC}"
echo "  dbus, NetworkManager, bluetoothd, elogind, seatd, sddm"
echo ""
echo -e "${YLW}Benutzergruppen hinzugefuegt:${NC}"
echo "  network, bluetooth, _seatd, audio, video, input, optical, storage, disk, kvm"
echo ""
warn "Bitte rebooten, damit alle Aenderungen wirksam werden!"
