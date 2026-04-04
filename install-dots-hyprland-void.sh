#!/usr/bin/env bash
# =============================================================================
#  dots-hyprland (end-4/dots-hyprland) – Void Linux x86_64 musl + runit
#  AMD GPU · SDDM Display Manager · sddm-astronaut-theme (hyprland_kath)
#
#  Inspiriert von: https://github.com/end-4/dots-hyprland
#  Hyprland-Repo:  https://github.com/Makrennel/hyprland-void (musl Binaries)
#
#  Nutzung: chmod +x install-dots-hyprland-void.sh && ./install-dots-hyprland-void.sh
#
#  ACHTUNG: Das Script baut fehlende Pakete aus dem Quellcode.
#           Buildzeit ~20-40 Minuten je nach Hardware.
# =============================================================================

set -euo pipefail

# ── Farben & Logging ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

LOGFILE="$HOME/dots-hyprland-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERR ]${NC}  $*"; exit 1; }
step()    { echo -e "\n${CYAN}${BOLD}════════════════════════════════════════${NC}"; \
            echo -e "${CYAN}${BOLD}  $*${NC}"; \
            echo -e "${CYAN}${BOLD}════════════════════════════════════════${NC}\n"; }
substep() { echo -e "  ${BOLD}▸ $*${NC}"; }

BUILD_DIR="$HOME/.cache/dots-hyprland-build"
DOTS_DIR="$HOME/.cache/dots-hyprland-src"
FONT_DIR="$HOME/.local/share/fonts"

# ── Schritt 0: Voraussetzungen ────────────────────────────────────────────────
step "Schritt 0 · Voraussetzungen prüfen"

[[ $EUID -eq 0 ]] && error "Nicht als root ausführen."

source /etc/os-release 2>/dev/null || error "/etc/os-release nicht gefunden."
[[ "${ID:-}" == "void" ]] || error "Nur für Void Linux. Erkannt: ${ID:-?}"
[[ "$(uname -m)" == "x86_64" ]] || error "Nur x86_64 wird unterstützt."

# musl prüfen
if ! ldd --version 2>&1 | grep -qi "musl"; then
    warn "musl nicht erkannt – bist du sicher, dass du Void musl nutzt?"
    read -rp "Trotzdem fortfahren? (j/N) " _ans
    [[ "$_ans" =~ ^[jJyY]$ ]] || exit 1
fi

ping -c1 -W3 github.com &>/dev/null || error "Keine Internetverbindung."

command -v sudo &>/dev/null || error "'sudo' fehlt. Installiere es zuerst: xbps-install -S sudo"
sudo -v || error "sudo-Authentifizierung fehlgeschlagen."

# sudo am Leben halten
while true; do sudo -v; sleep 50; done &
_SUDO_PID=$!
trap 'kill $_SUDO_PID 2>/dev/null; exit' EXIT INT TERM

ok "Void Linux musl x86_64 · Internet OK · sudo OK"

# ── Übersicht ────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}╔══════════════════════════════════════════════════════════════════╗"
echo -e "║  end-4/dots-hyprland auf Void Linux musl installieren            ║"
echo -e "╠══════════════════════════════════════════════════════════════════╣"
echo -e "║  GPU:           AMD (Mesa/AMDGPU Vulkan)                         ║"
echo -e "║  Session-Start: SDDM (sddm-astronaut hyprland_kath)              ║"
echo -e "║  Init-System:   runit                                            ║"
echo -e "║  XFCE:          bleibt als w\u00e4hlbare Session in SDDM             ║"
echo -e "╠══════════════════════════════════════════════════════════════════╣"
echo -e "║  Selbst gebaut: cpptrace · songrec · ydotool                    ║"
echo -e "║                 hyprshot · adw-gtk3 · MicroTeX                   ║"
echo -e "╚══════════════════════════════════════════════════════════════════╝${NC}\n"

read -rp "Fortfahren? (j/N) " _confirm
[[ "$_confirm" =~ ^[jJyY]$ ]] || { info "Abgebrochen."; exit 0; }

mkdir -p "$BUILD_DIR" "$DOTS_DIR" "$FONT_DIR"

# ═════════════════════════════════════════════════════════════════════════════
# Schritt 1 · Hyprland-Repo hinzufügen + System updaten
# ═════════════════════════════════════════════════════════════════════════════
step "Schritt 1 · Hyprland-Repo + System-Update"

HYPR_CONF="/etc/xbps.d/hyprland-void.conf"
if ! grep -q "repository-x86_64-musl" "$HYPR_CONF" 2>/dev/null; then
    echo "repository=https://raw.githubusercontent.com/Makrennel/hyprland-void/repository-x86_64-musl" \
        | sudo tee "$HYPR_CONF" > /dev/null
    ok "Makrennel Hyprland-Repo hinzugefügt (musl)."
else
    ok "Hyprland-Repo bereits konfiguriert."
fi

substep "xbps selbst aktualisieren..."
sudo xbps-install -u xbps || true
substep "System aktualisieren..."
sudo xbps-install -Syu
ok "System ist aktuell."

# ═════════════════════════════════════════════════════════════════════════════
# Schritt 2 · Pakete aus Void-Repos installieren
# ═════════════════════════════════════════════════════════════════════════════
step "Schritt 2 · Pakete aus Void-Repos installieren"

# Hilfsfunktion: einzeln installieren, fehlende protokollieren
_FAILED_PKGS=()
xinstall() {
    for _pkg in "$@"; do
        if sudo xbps-install -y "$_pkg" 2>/dev/null; then
            ok "$_pkg"
        else
            warn "$_pkg – nicht gefunden (wird ggf. selbst gebaut)"
            _FAILED_PKGS+=("$_pkg")
        fi
    done
}

# ── Hyprland-Kern ────────────────────────────────────────────────────────────
substep "Hyprland + Ökosystem"
xinstall \
    hyprland \
    hypridle \
    hyprlock \
    hyprpaper \
    hyprpicker \
    hyprsunset \
    xdg-desktop-portal-hyprland

# ── Wayland-Basis ────────────────────────────────────────────────────────────
substep "Wayland-Basis"
xinstall \
    xorg-server-xwayland \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk \
    xdg-desktop-portal-kde \
    xdg-utils \
    wayland \
    wayland-protocols \
    wl-clipboard

# ── Session / Auth ───────────────────────────────────────────────────────────
substep "Session & Auth"
xinstall \
    seatd \
    dbus \
    elogind \
    polkit \
    polkit-gnome \
    gnome-keyring \
    networkmanager

# ── AMD GPU ──────────────────────────────────────────────────────────────────
substep "AMD GPU-Treiber"
xinstall \
    mesa \
    mesa-dri \
    mesa-vaapi \
    mesa-vdpau \
    mesa-vulkan-radeon \
    vulkan-loader \
    Vulkan-Headers \
    libdrm \
    libva-utils

# ── Audio ────────────────────────────────────────────────────────────────────
substep "Audio (PipeWire)"
xinstall \
    pipewire \
    pipewire-pulse \
    wireplumber \
    pavucontrol-qt \
    playerctl \
    libdbusmenu-gtk3

# ── Qt6 (für Quickshell) ─────────────────────────────────────────────────────
substep "Qt6 & KDE-Frameworks"
xinstall \
    qt6-base \
    qt6-declarative \
    qt6-qt5compat \
    qt6-imageformats \
    qt6-multimedia \
    qt6-positioning \
    qt6-quicktimeline \
    qt6-sensors \
    qt6-svg \
    qt6-tools \
    qt6-translations \
    qt6-virtualkeyboard \
    qt6-wayland \
    qt6-shadertools \
    kirigami2 \
    kdialog \
    syntax-highlighting \
    jemalloc

# ── KDE (für Portale / Theming) ──────────────────────────────────────────────
substep "KDE-Pakete"
xinstall \
    bluedevil \
    plasma-nm \
    polkit-kde-agent \
    dolphin \
    plasma-systemsettings

# ── Shell & Fonts-Tools ──────────────────────────────────────────────────────
substep "Shell, Fonts, Themes"
xinstall \
    fish-shell \
    kitty \
    starship \
    eza \
    fontconfig \
    matugen

# ── Werkzeuge & Utilities ─────────────────────────────────────────────────────
substep "Werkzeuge"
xinstall \
    bc \
    curl \
    wget \
    ripgrep \
    jq \
    xdg-user-dirs \
    rsync \
    yq \
    ImageMagick \
    upower \
    wtype \
    translate-shell \
    uv \
    clang \
    gtk4 \
    libadwaita \
    libsoup3 \
    libportal-gtk4 \
    gobject-introspection \
    geoclue2 \
    brightnessctl \
    ddcutil \
    cliphist

# ── Quickshell (offiziell in Void!) ──────────────────────────────────────────
substep "Quickshell"
xinstall quickshell

# ── Screen Capture ───────────────────────────────────────────────────────────
substep "Screen Capture"
xinstall \
    grim \
    slurp \
    swappy \
    wf-recorder \
    tesseract \
    tesseract-langpack-deu

# ── Widgets & Launcher ───────────────────────────────────────────────────────
substep "Widgets & Launcher"
xinstall \
    fuzzel \
    wlogout \
    libqalculate \
    mako \
    swaybg

# ── MicroTeX Build-Deps ──────────────────────────────────────────────────────
substep "MicroTeX Build-Abhängigkeiten"
xinstall \
    tinyxml2-devel \
    gtkmm3 \
    gtkmm3-devel \
    gtksourceviewmm \
    gtksourceviewmm-devel \
    cairomm \
    cairomm-devel \
    cmake \
    ninja \
    git \
    base-devel \
    pkg-config

# ── SongRec Build-Deps ───────────────────────────────────────────────────────
substep "SongRec Build-Abhängigkeiten"
xinstall \
    rust \
    cargo \
    alsa-lib-devel \
    gtk+3-devel \
    glib-devel \
    libssl-devel

# ── adw-gtk3 Build-Deps ──────────────────────────────────────────────────────
substep "adw-gtk3 Build-Abhängigkeiten"
xinstall \
    meson \
    sassc \
    gtk+3-devel

if [[ ${#_FAILED_PKGS[@]} -gt 0 ]]; then
    warn "Folgende Pakete waren nicht in den Repos:"
    printf '  • %s\n' "${_FAILED_PKGS[@]}"
fi

# ═════════════════════════════════════════════════════════════════════════════
# Schritt 3 · Fehlende Pakete selbst bauen
# ═════════════════════════════════════════════════════════════════════════════
step "Schritt 3 · Fehlende Pakete aus Quellcode bauen"

# ── 3a. cpptrace ─────────────────────────────────────────────────────────────
substep "Baue cpptrace (Quickshell-Abhängigkeit)"
if ! pkg-config --exists cpptrace 2>/dev/null; then
    cd "$BUILD_DIR"
    if [[ -d cpptrace ]]; then
        git -C cpptrace pull --ff-only || true
    else
        git clone --depth=1 https://github.com/jeremy-rifkin/cpptrace.git
    fi
    cd cpptrace
    cmake -B build -S . \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DBUILD_SHARED_LIBS=ON
    cmake --build build -j"$(nproc)"
    sudo cmake --install build
    ok "cpptrace gebaut und installiert."
else
    ok "cpptrace bereits vorhanden."
fi

# ── 3b. ydotool ──────────────────────────────────────────────────────────────
substep "Baue ydotool"
if ! command -v ydotool &>/dev/null; then
    cd "$BUILD_DIR"
    if [[ -d ydotool ]]; then
        git -C ydotool pull --ff-only || true
    else
        git clone --depth=1 https://github.com/ReimuNotMoe/ydotool.git
    fi
    cd ydotool
    cmake -B build -S . \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DBUILD_DOCS=OFF \
        -DSYSTEMD_USER_SERVICE=OFF \
        -DSYSTEMD_SYSTEM_SERVICE=OFF
    cmake --build build -j"$(nproc)"
    sudo cmake --install build
    ok "ydotool gebaut und installiert."
else
    ok "ydotool bereits vorhanden."
fi

# ── 3c. hyprshot (Shell-Script, kein Build nötig) ─────────────────────────────
substep "Installiere hyprshot (Shell-Script)"
if ! command -v hyprshot &>/dev/null; then
    cd "$BUILD_DIR"
    if [[ -d Hyprshot ]]; then
        git -C Hyprshot pull --ff-only || true
    else
        git clone --depth=1 https://github.com/Gustash/Hyprshot.git
    fi
    sudo install -Dm755 Hyprshot/hyprshot /usr/local/bin/hyprshot
    ok "hyprshot installiert."
else
    ok "hyprshot bereits vorhanden."
fi

# ── 3d. adw-gtk3 (GTK3-Theme im Libadwaita-Stil) ─────────────────────────────
substep "Baue adw-gtk3 Theme"
if [[ ! -d "$HOME/.local/share/themes/adw-gtk3" ]]; then
    cd "$BUILD_DIR"
    if [[ -d adw-gtk3 ]]; then
        git -C adw-gtk3 pull --ff-only || true
    else
        git clone --depth=1 https://github.com/lassekongo83/adw-gtk3.git
    fi
    cd adw-gtk3
    meson setup build \
        --prefix="$HOME/.local" \
        --libdir="$HOME/.local/lib"
    ninja -C build install
    ok "adw-gtk3 in ~/.local/share/themes/ installiert."
else
    ok "adw-gtk3 bereits vorhanden."
fi

# ── 3e. SongRec (Shazam-Klon in Rust) ────────────────────────────────────────
substep "Baue SongRec (Shazam-Klon) – dauert einige Minuten"
if ! command -v songrec &>/dev/null; then
    cd "$BUILD_DIR"
    if [[ -d SongRec ]]; then
        git -C SongRec pull --ff-only || true
    else
        git clone --depth=1 https://github.com/marin-m/SongRec.git
    fi
    cd SongRec
    # Release-Build ohne GUI (für Headless-Nutzung in der Shell reicht CLI)
    cargo build --release
    sudo install -Dm755 target/release/songrec /usr/local/bin/songrec
    ok "songrec gebaut und installiert."
else
    ok "songrec bereits vorhanden."
fi

# ── 3f. MicroTeX (LaTeX-Renderer) ────────────────────────────────────────────
substep "Baue MicroTeX (LaTeX-Renderer für Quickshell)"
if [[ ! -x /opt/MicroTeX/LaTeX ]]; then
    cd "$BUILD_DIR"
    if [[ -d MicroTeX ]]; then
        git -C MicroTeX pull --ff-only || true
    else
        git clone --depth=1 https://github.com/NanoMichael/MicroTeX.git
    fi
    cd MicroTeX
    # Patches (wie im PKGBUILD von dots-hyprland)
    sed -i 's/gtksourceviewmm-3\.0/gtksourceviewmm-4.0/g' CMakeLists.txt  || true
    sed -i 's/tinyxml2\.so\.10/tinyxml2.so.11/g'          CMakeLists.txt  || true
    cmake -B build -S . \
        -DCMAKE_BUILD_TYPE=None \
        -DCMAKE_INSTALL_PREFIX=/opt/MicroTeX
    cmake --build build -j"$(nproc)"
    sudo cmake --install build
    ok "MicroTeX gebaut und nach /opt/MicroTeX/ installiert."
else
    ok "MicroTeX bereits vorhanden."
fi

# ═════════════════════════════════════════════════════════════════════════════
# Schritt 4 · Fonts installieren
# ═════════════════════════════════════════════════════════════════════════════
step "Schritt 4 · Fonts installieren"

# Hilfsfunktion: Font-URL herunterladen
dl_font() {
    local name="$1" url="$2" dest="$FONT_DIR/$3"
    if [[ -f "$dest" ]]; then
        ok "Font '$name' bereits vorhanden."
        return 0
    fi
    substep "Lade $name..."
    mkdir -p "$(dirname "$dest")"
    if curl -fsSL "$url" -o "$dest"; then
        ok "$name"
    else
        warn "$name – Download fehlgeschlagen: $url"
    fi
}

# ── JetBrains Mono Nerd Font ──────────────────────────────────────────────────
substep "JetBrains Mono Nerd Font"
if ! ls "$FONT_DIR"/JetBrainsMonoNerd*.ttf &>/dev/null; then
    _TMPF=$(mktemp)
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz" -o "$_TMPF"
    tar -xf "$_TMPF" -C "$FONT_DIR" --wildcards '*.ttf' 2>/dev/null || \
        tar -xf "$_TMPF" -C "$FONT_DIR"
    rm -f "$_TMPF"
    ok "JetBrains Mono Nerd Font installiert."
else
    ok "JetBrains Mono Nerd Font bereits vorhanden."
fi

# ── Space Grotesk OTF ─────────────────────────────────────────────────────────
substep "Space Grotesk"
if ! ls "$FONT_DIR"/SpaceGrotesk* &>/dev/null; then
    _TMPF=$(mktemp --suffix=.zip)
    curl -fsSL "https://github.com/floriankarsten/space-grotesk/releases/download/2.0.0/SpaceGrotesk-2.0.0.zip" -o "$_TMPF"
    unzip -q -j "$_TMPF" '*.otf' '*.ttf' -d "$FONT_DIR" 2>/dev/null || \
        unzip -q "$_TMPF" -d "$FONT_DIR"
    rm -f "$_TMPF"
    ok "Space Grotesk installiert."
else
    ok "Space Grotesk bereits vorhanden."
fi

# ── Material Symbols Variable Font ───────────────────────────────────────────
# URL-Encoding für eckige Klammern
dl_font "Material Symbols Outlined" \
    "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsOutlined%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf" \
    "MaterialSymbolsOutlined[FILL,GRAD,opsz,wght].ttf"

dl_font "Material Symbols Rounded" \
    "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf" \
    "MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf"

# ── Readex Pro Variable Font ──────────────────────────────────────────────────
dl_font "Readex Pro" \
    "https://github.com/ThomasJockin/readexpro/raw/master/fonts/variable/Readexpro%5BHEX%2Cwght%5D.ttf" \
    "ReadexPro[HEX,wght].ttf"

# ── Rubik Variable Font ───────────────────────────────────────────────────────
dl_font "Rubik" \
    "https://github.com/googlefonts/rubik/raw/main/fonts/variable/Rubik%5Bwght%5D.ttf" \
    "Rubik[wght].ttf"

dl_font "Rubik Italic" \
    "https://github.com/googlefonts/rubik/raw/main/fonts/variable/Rubik-Italic%5Bwght%5D.ttf" \
    "Rubik-Italic[wght].ttf"

# ── Twemoji (Emoji) ───────────────────────────────────────────────────────────
dl_font "Twemoji" \
    "https://github.com/JoeBlakeB/ttf-twemoji-aur/releases/download/17.0.2/Twemoji-17.0.2.ttf" \
    "Twemoji.ttf"

# ── Google Sans Flex ──────────────────────────────────────────────────────────
substep "Google Sans Flex"
if ! ls "$FONT_DIR"/GoogleSans* &>/dev/null; then
    _TMPF=$(mktemp --suffix=.zip)
    if curl -fsSL "https://fonts.google.com/download?family=Google+Sans+Flex" -o "$_TMPF" --max-time 30; then
        unzip -q -j "$_TMPF" '*.ttf' -d "$FONT_DIR" 2>/dev/null || true
        ok "Google Sans Flex installiert."
    else
        warn "Google Sans Flex – Download fehlgeschlagen. Lade es manuell von fonts.google.com"
    fi
    rm -f "$_TMPF"
else
    ok "Google Sans Flex bereits vorhanden."
fi

# ── Font-Cache aktualisieren ──────────────────────────────────────────────────
substep "Font-Cache aktualisieren..."
fc-cache -fv "$FONT_DIR" &>/dev/null
ok "Font-Cache aktualisiert."

# ═════════════════════════════════════════════════════════════════════════════
# Schritt 5 · dots-hyprland Repo klonen & Configs installieren
# ═════════════════════════════════════════════════════════════════════════════
step "Schritt 5 · dots-hyprland Konfiguration installieren"

substep "Klone end-4/dots-hyprland..."
if [[ -d "$DOTS_DIR/.git" ]]; then
    git -C "$DOTS_DIR" pull --ff-only || \
        { warn "Pull fehlgeschlagen – nutze bestehende Version."; }
else
    git clone --depth=1 https://github.com/end-4/dots-hyprland.git "$DOTS_DIR"
fi
ok "Repository bereit: $DOTS_DIR"

# Backup existierender Configs
_backup() {
    local dir="$1"
    if [[ -e "$dir" ]] && [[ ! -L "$dir" ]]; then
        local bak
        bak="${dir}.bak.$(date +%Y%m%d_%H%M%S)"
        mv "$dir" "$bak"
        warn "Backup erstellt: $bak"
    fi
}

CONF="$HOME/.config"
SHARE="$HOME/.local/share"

mkdir -p "$CONF" "$SHARE"

# ── Konfigurationsdateien kopieren ────────────────────────────────────────────
substep "Kopiere Konfigurationsdateien..."

# Quickshell-Config (das Herzstück der Shell)
_backup "$CONF/quickshell"
cp -r "$DOTS_DIR/dots/.config/quickshell" "$CONF/"
ok "quickshell/"

# Hyprland-Config
mkdir -p "$CONF/hypr"
for _f in hyprland.conf lock.conf monitors.conf workspaces.conf; do
    if [[ -f "$DOTS_DIR/dots/.config/hypr/$_f" ]]; then
        _backup "$CONF/hypr/$_f"
        cp "$DOTS_DIR/dots/.config/hypr/$_f" "$CONF/hypr/$_f"
        ok "hypr/$_f"
    fi
done
# hyprland/ Verzeichnis (Unterordner)
if [[ -d "$DOTS_DIR/dots/.config/hypr/hyprland" ]]; then
    _backup "$CONF/hypr/hyprland"
    cp -r "$DOTS_DIR/dots/.config/hypr/hyprland" "$CONF/hypr/"
    ok "hypr/hyprland/"
fi
# custom/ – nur anlegen wenn noch nicht vorhanden (user-Einstellungen)
if [[ ! -d "$CONF/hypr/custom" ]]; then
    if [[ -d "$DOTS_DIR/dots/.config/hypr/custom" ]]; then
        cp -r "$DOTS_DIR/dots/.config/hypr/custom" "$CONF/hypr/"
        ok "hypr/custom/ (neu angelegt)"
    fi
fi

# Weitere .config/-Verzeichnisse
for _dir in Kvantum fish fontconfig foot fuzzel kde-material-you-colors \
            kitty matugen mpv wlogout xdg-desktop-portal zshrc.d; do
    if [[ -d "$DOTS_DIR/dots/.config/$_dir" ]]; then
        _backup "$CONF/$_dir"
        cp -r "$DOTS_DIR/dots/.config/$_dir" "$CONF/"
        ok "$_dir/"
    fi
done

# Einzelne Config-Dateien
for _f in chrome-flags.conf code-flags.conf darklyrc dolphinrc \
           kdeglobals konsolerc starship.toml thorium-flags.conf; do
    if [[ -f "$DOTS_DIR/dots/.config/$_f" ]]; then
        cp "$DOTS_DIR/dots/.config/$_f" "$CONF/$_f"
        ok "$_f"
    fi
done

# Icons
if [[ -d "$DOTS_DIR/dots/.local/share/icons" ]]; then
    mkdir -p "$SHARE/icons"
    cp -r "$DOTS_DIR/dots/.local/share/icons/." "$SHARE/icons/"
    ok "icons/"
fi

# Konsole-Profile
if [[ -d "$DOTS_DIR/dots/.local/share/konsole" ]]; then
    mkdir -p "$SHARE/konsole"
    cp -r "$DOTS_DIR/dots/.local/share/konsole/." "$SHARE/konsole/"
    ok "konsole/"
fi

# ── hyprland.conf: Void-Linux-Anpassungen ─────────────────────────────────────
substep "Void-Linux-Anpassungen in hyprland.conf..."

HYPR_CONF_FILE="$CONF/hypr/hyprland.conf"
if [[ -f "$HYPR_CONF_FILE" ]]; then
    # PipeWire via exec-once starten (kein systemd user service auf Void)
    if ! grep -q "exec-once.*pipewire" "$HYPR_CONF_FILE"; then
        # Vor der ersten exec-once Zeile einfügen
        sed -i '/^exec-once/i # PipeWire (runit hat keinen systemd user service – manuell starten)\nexec-once = pipewire \&\nexec-once = sleep 1 \&\& wireplumber \&\n' \
            "$HYPR_CONF_FILE" 2>/dev/null || true
    fi
    # AMD-spezifische Env-Variablen ergänzen
    if ! grep -q "LIBVA_DRIVER_NAME" "$HYPR_CONF_FILE"; then
        cat >> "$HYPR_CONF_FILE" << 'AMDENV'

# ── Void Linux / AMD Anpassungen ────────────────────────────────────────────
env = LIBVA_DRIVER_NAME,radeonsi
env = WLR_RENDERER,vulkan
env = MOZ_ENABLE_WAYLAND,1
env = QT_QPA_PLATFORM,wayland;xcb
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
env = GDK_BACKEND,wayland,x11
env = SDL_VIDEODRIVER,wayland
env = CLUTTER_BACKEND,wayland
env = XDG_SESSION_TYPE,wayland
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_DESKTOP,Hyprland
AMDENV
    fi
    ok "hyprland.conf angepasst."
fi

# ── Bibata-Cursor installieren ────────────────────────────────────────────────
substep "Bibata Cursor Theme"
CURSOR_DIR="$SHARE/icons/Bibata-Modern-Classic"
if [[ ! -d "$CURSOR_DIR" ]]; then
    _TMPF=$(mktemp --suffix=.tar.xz)
    # Aktuellste Version aus GitHub Releases
    _CURSOR_URL=$(curl -fsSL https://api.github.com/repos/ful1e5/Bibata_Cursor/releases/latest \
        | grep -o '"browser_download_url": *"[^"]*Bibata-Modern-Classic\.tar\.xz"' \
        | grep -o 'https://[^"]*' | head -1)
    if [[ -n "$_CURSOR_URL" ]]; then
        curl -fsSL "$_CURSOR_URL" -o "$_TMPF"
        mkdir -p "$SHARE/icons"
        tar -xf "$_TMPF" -C "$SHARE/icons/"
        ok "Bibata Modern Classic Cursor installiert."
    else
        warn "Bibata Cursor – konnte Download-URL nicht ermitteln."
    fi
    rm -f "$_TMPF"
else
    ok "Bibata Cursor bereits vorhanden."
fi

# ═════════════════════════════════════════════════════════════════════════════
# Schritt 6 · runit-Services konfigurieren
# ═════════════════════════════════════════════════════════════════════════════
step "Schritt 6 · runit-Services konfigurieren"

_enable_svc() {
    local svc="$1"
    if [[ -d "/etc/sv/$svc" ]]; then
        if [[ -L "/var/service/$svc" ]]; then
            ok "Service '$svc' bereits aktiv."
        else
            sudo ln -s "/etc/sv/$svc" /var/service/
            ok "Service '$svc' aktiviert."
        fi
    else
        warn "Service '$svc' nicht gefunden in /etc/sv/"
    fi
}

_enable_svc dbus
_enable_svc seatd
_enable_svc elogind
_enable_svc upower

# Benutzer in _seatd Gruppe
if groups "$USER" | grep -q "_seatd"; then
    ok "Benutzer '$USER' ist bereits in '_seatd'."
else
    sudo usermod -aG _seatd "$USER"
    ok "Benutzer '$USER' zu '_seatd' hinzugefügt."
    warn "→ Abmelden + anmelden (oder neustarten) damit die Gruppe wirkt!"
fi

# NetworkManager aktivieren
_enable_svc NetworkManager

# ydotool als runit-Service einrichten
substep "ydotool als runit-Service einrichten..."
if [[ ! -d /etc/sv/ydotoold ]]; then
    sudo mkdir -p /etc/sv/ydotoold
    sudo tee /etc/sv/ydotoold/run > /dev/null << 'YDOTOOLD_RUN'
#!/bin/sh
exec /usr/local/bin/ydotoold
YDOTOOLD_RUN
    sudo chmod +x /etc/sv/ydotoold/run
    _enable_svc ydotoold
    ok "ydotoold Service eingerichtet."
else
    ok "ydotoold Service bereits vorhanden."
fi

# ═════════════════════════════════════════════════════════════════════════════
# Schritt 7 · SDDM + sddm-astronaut-theme
# ═════════════════════════════════════════════════════════════════════════════
step "Schritt 7 · SDDM installieren + sddm-astronaut-theme (hyprland_kath)"

# ── 7a. SDDM installieren ────────────────────────────────────────────────────
substep "Installiere SDDM..."
xinstall sddm

# LightDM deaktivieren falls aktiv (XFCE-Standard)
if [[ -L /var/service/lightdm ]]; then
    warn "LightDM wird deaktiviert (ersetzt durch SDDM)..."
    sudo rm /var/service/lightdm
    ok "LightDM deaktiviert."
fi

# ── 7b. Hyprland als Wayland-Session registrieren ────────────────────────────
substep "Hyprland-Session für SDDM registrieren..."
sudo mkdir -p /usr/share/wayland-sessions
if [[ ! -f /usr/share/wayland-sessions/hyprland.desktop ]]; then
    sudo tee /usr/share/wayland-sessions/hyprland.desktop > /dev/null << 'HYPR_DESKTOP'
[Desktop Entry]
Name=Hyprland
Comment=An intelligent dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
DesktopNames=Hyprland
Keywords=tiling;wayland;compositor
HYPR_DESKTOP
    ok "Hyprland Wayland-Session registriert."
else
    ok "Hyprland-Session bereits vorhanden."
fi

# XFCE-Session sicherstellen
if [[ ! -f /usr/share/xsessions/xfce.desktop ]]; then
    sudo mkdir -p /usr/share/xsessions
    sudo tee /usr/share/xsessions/xfce.desktop > /dev/null << 'XFCE_DESKTOP'
[Desktop Entry]
Name=Xfce Session
Comment=Xfce Desktop Environment
Exec=startxfce4
Type=Application
XFCE_DESKTOP
    ok "XFCE-Session registriert."
fi

# ── 7c. sddm-astronaut-theme klonen ──────────────────────────────────────────
substep "Installiere sddm-astronaut-theme..."
SDDM_THEME_DIR="/usr/share/sddm/themes/sddm-astronaut-theme"
if [[ -d "${SDDM_THEME_DIR}/.git" ]]; then
    sudo git -C "$SDDM_THEME_DIR" pull --ff-only || true
    ok "sddm-astronaut-theme aktualisiert."
else
    sudo git clone --depth=1 \
        https://github.com/keyitdev/sddm-astronaut-theme.git \
        "$SDDM_THEME_DIR"
    ok "sddm-astronaut-theme installiert."
fi
# Theme-eigene Fonts systemweit verfügbar machen
sudo cp -r "${SDDM_THEME_DIR}/Fonts/"* /usr/share/fonts/ 2>/dev/null || true
ok "Theme-Fonts installiert."

# ── 7d. Variante hyprland_kath aktivieren ────────────────────────────────────
# Verfügbare Varianten: astronaut · black_hole · japanese_aesthetic
#   pixel_sakura_static · purple_leaves · cyberpunk
#   post_apocalyptic_hacker · hyprland_kath · jake_the_dog
# → hyprland_kath wurde speziell für Hyprland-Setups gemacht
substep "Aktiviere Variante 'hyprland_kath'..."
SDDM_META="${SDDM_THEME_DIR}/metadata.desktop"
if [[ -f "$SDDM_META" ]]; then
    sudo sed -i 's|^ConfigFile=.*|ConfigFile=Themes/hyprland_kath.conf|' "$SDDM_META"
    ok "Variante 'hyprland_kath' aktiviert."
fi

# ── 7e. Theme-Farben auf Catppuccin Mocha anpassen ───────────────────────────
substep "Theme-Farben auf Catppuccin Mocha anpassen..."
SDDM_THEME_CONF="${SDDM_THEME_DIR}/Themes/hyprland_kath.conf"
if [[ -f "$SDDM_THEME_CONF" ]]; then
    # Backup der Original-Konfiguration
    sudo cp "$SDDM_THEME_CONF" "${SDDM_THEME_CONF}.orig"
    # Catppuccin Mocha Farbpalette + deutsche Lokalisierung
    sudo tee "$SDDM_THEME_CONF" > /dev/null << 'THEME_CONF'
[General]
Background="../Backgrounds/hyprland_kath.png"
ScreenWidth="1920"
ScreenHeight="1080"
DateFormat="dddd, dd. MMMM yyyy"
TimeFormat="HH:mm"
HourFormat="24"
LoginButtonText="Anmelden"
HeaderText="Willkommen"
InputColor="#1e1e2e"
InputActiveColor="#313244"
InputTextColor="#cdd6f4"
MainColor="#cdd6f4"
AccentColor="#89b4fa"
HighlightColor="#313244"
HighlightTextColor="#cdd6f4"
Font="JetBrainsMono Nerd Font"
FontSize="12"
Blur=true
BlurRadius="32"
RoundCorners="12"
FormPosition="center"
HideCompletePassword=false
ShowUsersByDefault=true
THEME_CONF
    ok "Catppuccin Mocha Farben gesetzt."
else
    warn "Theme-Konfig nicht gefunden – Standardfarben bleiben."
fi

# ── 7f. Haupt-SDDM-Konfiguration ─────────────────────────────────────────────
substep "Schreibe /etc/sddm.conf..."
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf > /dev/null << 'SDDM_MAIN'
[General]
HaltCommand=/usr/bin/loginctl poweroff
RebootCommand=/usr/bin/loginctl reboot
InputMethod=qtvirtualkeyboard
RememberLastUser=true
RememberLastSession=true

[Theme]
Current=sddm-astronaut-theme
ThemeDir=/usr/share/sddm/themes

[Users]
MaximumUid=60513
MinimumUid=1000
SDDM_MAIN
ok "/etc/sddm.conf geschrieben."

# Virtuelle Tastatur aktivieren
sudo tee /etc/sddm.conf.d/virtualkbd.conf > /dev/null << 'SDDM_KBD'
[General]
InputMethod=qtvirtualkeyboard
SDDM_KBD

# ── 7g. SDDM-Service über runit aktivieren ───────────────────────────────────
substep "SDDM runit-Service aktivieren..."
if [[ -d /etc/sv/sddm ]]; then
    if [[ ! -L /var/service/sddm ]]; then
        sudo ln -s /etc/sv/sddm /var/service/
        ok "SDDM-Service aktiviert (startet nach Neustart)."
    else
        ok "SDDM-Service bereits aktiv."
    fi
else
    warn "/etc/sv/sddm nicht gefunden – prüfe ob sddm korrekt installiert ist."
fi

# PATH ergänzen
mkdir -p "$HOME/.local/bin"
if ! grep -q '\.local/bin' "$HOME/.bash_profile" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bash_profile"
fi

# ═════════════════════════════════════════════════════════════════════════════
# Schritt 8 · xdg-user-dirs initialisieren
# ═════════════════════════════════════════════════════════════════════════════
step "Schritt 8 · xdg-user-dirs"
xdg-user-dirs-update || true
ok "XDG-Benutzerverzeichnisse aktualisiert."

# ═════════════════════════════════════════════════════════════════════════════
# Abschluss
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════╗"
echo -e "║      dots-hyprland erfolgreich installiert!                      ║"
echo -e "╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Nächste Schritte:${NC}"
echo -e ""
echo -e "  ${CYAN}1.${NC} ${BOLD}sudo reboot${NC}"
echo -e "     → SDDM startet automatisch als Login-Manager."
echo -e "     → Im Sessionsmenü: Hyprland (Wayland) oder Xfce w\u00e4hlen."
echo -e "     → Hyprland mit der Wayland-Session starten."
echo ""
echo -e "  ${CYAN}2.${NC} Beim ersten Start setzt Quickshell die Farben per Matugen."
echo -e "     Warte kurz – das ist normal."
echo ""
echo -e "${BOLD}Wichtige Tastenkürzel (Standard aus dots-hyprland):${NC}"
echo -e "  ${GREEN}SUPER + Return${NC}   Terminal"
echo -e "  ${GREEN}SUPER + /     ${NC}   Quickshell Launcher"
echo -e "  ${GREEN}SUPER + Tab   ${NC}   Übersicht / App-Switcher"
echo -e "  ${GREEN}Print         ${NC}   Screenshot"
echo -e "  ${GREEN}SUPER + 1–0   ${NC}   Workspace wechseln"
echo ""
echo -e "${BOLD}Konfigurationsordner:${NC}"
echo -e "  Hyprland: ${CYAN}~/.config/hypr/${NC}"
echo -e "  Shell:    ${CYAN}~/.config/quickshell/ii/${NC}"
echo -e "  Matugen:  ${CYAN}~/.config/matugen/${NC}"
echo ""
echo -e "${BOLD}SDDM Theme:${NC}"
echo -e "  Theme:    ${CYAN}sddm-astronaut-theme (hyprland_kath)${NC}"
echo -e "  Farben:   ${CYAN}Catppuccin Mocha${NC}"
echo -e "  Config:   ${CYAN}/usr/share/sddm/themes/sddm-astronaut-theme/Themes/hyprland_kath.conf${NC}"
echo -e "  Variante wechseln (z.B. japanese_aesthetic):"
echo -e "  ${CYAN}sudo sed -i 's|ConfigFile=.*|ConfigFile=Themes/japanese_aesthetic.conf|'${NC}"
echo -e "  ${CYAN}  /usr/share/sddm/themes/sddm-astronaut-theme/metadata.desktop${NC}"
echo ""
echo -e "${BOLD}Selbst gebaute Programme:${NC}"
echo -e "  /usr/local/bin/songrec   (Song-Erkennung)"
echo -e "  /usr/local/bin/ydotoold  (Tool-Daemon)"
echo -e "  /usr/local/bin/hyprshot  (Screenshot-Script)"
echo -e "  /opt/MicroTeX/LaTeX      (LaTeX-Renderer)"
echo -e "  ~/.local/share/themes/adw-gtk3/ (GTK3-Theme)"
echo ""
echo -e "Log: ${CYAN}$LOGFILE${NC}"
echo ""
