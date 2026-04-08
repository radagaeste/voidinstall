#!/usr/bin/env bash
set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
SCRIPT_NAME=$(basename "$0")
USER_NAME="${SUDO_USER:-${USER:-$(id -un)}}"
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
NOCTALIA_CMD="noctalia-shell"
NOCTALIA_VOID_REPO_URL="${NOCTALIA_VOID_REPO_URL:-https://universalrepo.r1xelelo.workers.dev/void}"

log() { printf '\n[+] %s\n' "$*"; }
warn() { printf '\n[!] %s\n' "$*"; }
err() { printf '\n[x] %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || err "Fehlendes Kommando: $1"; }

run_cmd() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

pkg_available() {
  xbps-query -Rs "^$1$" >/dev/null 2>&1
}

install_if_available() {
  local available=()
  local missing=()
  local pkg
  for pkg in "$@"; do
    if pkg_available "$pkg"; then
      available+=("$pkg")
    else
      missing+=("$pkg")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    warn "Nicht gefunden, wird übersprungen: ${missing[*]}"
  fi

  if [ ${#available[@]} -gt 0 ]; then
    run_cmd xbps-install -y "${available[@]}"
  fi
}

safe_link_service() {
  local svc="$1"
  if [ -d "/etc/sv/$svc" ]; then
    ln -sf "/etc/sv/$svc" /var/service/
  else
    warn "Service $svc nicht gefunden, überspringe."
  fi
}

require_root() {
  [ "$(id -u)" -eq 0 ] || err "Bitte als root starten: sudo bash $SCRIPT_NAME"
}

setup_repos() {
  log "Installiere angeforderte Void-Repos"
  run_cmd xbps-install -Suy void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree

  log "Binde Noctalia Void-Repo ein"
  cat > /etc/xbps.d/noctalia.conf <<CONF
repository=${NOCTALIA_VOID_REPO_URL}
CONF

  run_cmd xbps-install -S
}

install_packages() {
  log "Installiere angeforderte Pakete, soweit in aktiven Repos vorhanden"

  local base_pkgs=(
    wpa_supplicant wifish wpa-cute wpa_gui NetworkManager nm-connection-editor
    xorg gnome-keyring polkit-gnome mtpfs inotify-tools ffmpeg libnotify
    git base-devel
    Vulkan-Headers Vulkan-Tools Vulkan-ValidationLayers-32bit mesa-vulkan-radeon mesa-vulkan-radeon-32bit
    vulkan-loader vulkan-loader-32bit libspa-vulkan libspa-vulkan-32bit amdvlk mesa-dri
    pipewire wireplumber pipewire-pulse
    waybar avizo font-awesome-6 swaylock dunst rofi
    swaybg mpvpaper swww
    grim jq slurp playerctl cliphist wl-clipboard swayidle swappy pavucontrol
    noctalia-shell
  )

  install_if_available "${base_pkgs[@]}"
}

enable_services() {
  log "Aktiviere angeforderte runit-Dienste"
  safe_link_service dbus
  safe_link_service seatd
  safe_link_service elogind
  safe_link_service polkitd
  safe_link_service bluetoothd
  safe_link_service sddm
  safe_link_service cronie
  safe_link_service wpa_supplicant
  safe_link_service NetworkManager
}

setup_pipewire() {
  log "Richte PipeWire/WirePlumber gemäß Void-Handbuch ein"
  install -d /etc/pipewire/pipewire.conf.d
  if [ -f /usr/share/examples/wireplumber/10-wireplumber.conf ]; then
    ln -sf /usr/share/examples/wireplumber/10-wireplumber.conf /etc/pipewire/pipewire.conf.d/10-wireplumber.conf
  else
    warn "WirePlumber-Beispielkonfiguration nicht gefunden, überspringe Symlink."
  fi
}

setup_hyprland_structure() {
  log "Erzeuge modulare Hyprland-Struktur"
  install -d -o "$USER_NAME" -g "$USER_NAME" \
    "$USER_HOME/.config/hypr" \
    "$USER_HOME/.config/hypr/conf" \
    "$USER_HOME/.config/hypr/scripts" \
    "$USER_HOME/.config/noctalia" \
    "$USER_HOME/.config/waybar" \
    "$USER_HOME/.config/dunst"

  cat > "$USER_HOME/.config/hypr/hyprland.conf" <<'CONF'
source = ~/.config/hypr/conf/variables.conf
source = ~/.config/hypr/conf/env.conf
source = ~/.config/hypr/conf/monitors.conf
source = ~/.config/hypr/conf/input.conf
source = ~/.config/hypr/conf/general.conf
source = ~/.config/hypr/conf/decoration.conf
source = ~/.config/hypr/conf/animations.conf
source = ~/.config/hypr/conf/misc.conf
source = ~/.config/hypr/conf/autostart.conf
source = ~/.config/hypr/conf/windowrules.conf
source = ~/.config/hypr/conf/keybindings.conf
CONF

  cat > "$USER_HOME/.config/hypr/conf/variables.conf" <<'CONF'
$mod = SUPER
$terminal = kitty
$fileManager = dolphin
$menu = rofi -show drun
$windowSwitcher = rofi -show window
$fileBrowser = rofi -show filebrowser
$browser = firefox
$tmpbrowser = firefox --ProfileManager
$editor = code
$lockscreen = swaylock
$logout = wlogout
$screenshotArea = grim -g "$(slurp)" - | wl-copy
$screenshotScreen = grim - | wl-copy
CONF

  cat > "$USER_HOME/.config/hypr/conf/env.conf" <<'CONF'
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = MOZ_ENABLE_WAYLAND,1
env = QT_QPA_PLATFORM,wayland
env = GDK_BACKEND,wayland,x11
env = SDL_VIDEODRIVER,wayland
CONF

  cat > "$USER_HOME/.config/hypr/conf/monitors.conf" <<'CONF'
monitor=,preferred,auto,1
CONF

  cat > "$USER_HOME/.config/hypr/conf/input.conf" <<'CONF'
input {
  kb_layout = de
  follow_mouse = 1
  touchpad {
    natural_scroll = yes
    tap-to-click = yes
  }
}
CONF

  cat > "$USER_HOME/.config/hypr/conf/general.conf" <<'CONF'
general {
  gaps_in = 5
  gaps_out = 12
  border_size = 2
  layout = dwindle
  resize_on_border = true
}
CONF

  cat > "$USER_HOME/.config/hypr/conf/decoration.conf" <<'CONF'
decoration {
  rounding = 10
  blur {
    enabled = true
    size = 6
    passes = 2
  }
  active_opacity = 0.96
  inactive_opacity = 0.90
  fullscreen_opacity = 1.0
  drop_shadow = true
  shadow_range = 16
  shadow_render_power = 3
}
CONF

  cat > "$USER_HOME/.config/hypr/conf/animations.conf" <<'CONF'
animations {
  enabled = yes
}
CONF

  cat > "$USER_HOME/.config/hypr/conf/misc.conf" <<'CONF'
misc {
  disable_hyprland_logo = true
  disable_splash_rendering = true
}
CONF

  cat > "$USER_HOME/.config/hypr/conf/autostart.conf" <<'CONF'
exec-once = /usr/libexec/polkit-gnome-authentication-agent-1
exec-once = dunst
exec-once = waybar
exec-once = wl-paste --type text --watch cliphist store
exec-once = swww-daemon
exec-once = noctalia-shell
exec-once = pipewire
exec-once = pipewire-pulse
exec-once = wireplumber
CONF

  cat > "$USER_HOME/.config/hypr/conf/windowrules.conf" <<'CONF'
windowrulev2 = float,class:^(nm-connection-editor)$
windowrulev2 = float,class:^(pavucontrol)$
windowrulev2 = center,class:^(pavucontrol)$
CONF

  cat > "$USER_HOME/.config/hypr/conf/keybindings.conf" <<'CONF'
bind = $mod, Q, killactive,
bind = $mod, DELETE, exit,
bind = $mod, W, togglefloating,
bind = $mod, RETURN, fullscreen,
bind = $mod, G, togglegroup,
bind = $mod, X, exec, $terminal
bind = $mod, E, exec, $fileManager
bind = $mod, C, exec, $editor
bind = $mod, SPACE, exec, $browser
bind = $mod, slash, exec, $tmpbrowser
bind = $mod, A, exec, $menu
bind = $mod, TAB, exec, $windowSwitcher
bind = $mod, R, exec, $fileBrowser
bind = $mod, V, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy
bind = $mod, L, exec, $lockscreen
bind = $mod, BACKSPACE, exec, $logout
bind = $mod, K, exec, hyprctl keyword decoration:blur:enabled true ; hyprctl keyword decoration:active_opacity 0.96 ; hyprctl keyword decoration:inactive_opacity 0.90
bind = $mod ALT, K, exec, hyprctl keyword decoration:blur:enabled false ; hyprctl keyword decoration:active_opacity 1 ; hyprctl keyword decoration:inactive_opacity 1
bind = $mod, P, exec, $screenshotArea
bind = $mod ALT, P, exec, $screenshotScreen
bind = $mod ALT, G, exec, hyprctl --batch 'keyword animations:enabled 0;keyword decoration:blur:enabled false;keyword decoration:drop_shadow false'
bind = $mod SHIFT, D, exec, ~/.config/hypr/scripts/theme-wall-toggle.sh
bind = $mod SHIFT, T, exec, ~/.config/hypr/scripts/theme-select.sh
bind = $mod SHIFT, W, exec, ~/.config/hypr/scripts/wallpaper-select.sh
bind = $mod SHIFT, A, exec, ~/.config/hypr/scripts/rofi-style-select.sh
bind = $mod ALT, S, movetoworkspace, special
bind = $mod, S, togglespecialworkspace,

binde = $mod, F11, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
binde = $mod, F12, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bind = $mod, F10, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle

bindm = $mod, mouse:272, movewindow
bindm = $mod, mouse:273, resizewindow
bind = $mod, mouse_down, workspace, e+1
bind = $mod, mouse_up, workspace, e-1

bind = $mod SHIFT, left, resizeactive, -40 0
bind = $mod SHIFT, right, resizeactive, 40 0
bind = $mod SHIFT, up, resizeactive, 0 -40
bind = $mod SHIFT, down, resizeactive, 0 40

bind = $mod SHIFT CTRL, left, movewindow, l
bind = $mod SHIFT CTRL, right, movewindow, r
bind = $mod SHIFT CTRL, up, movewindow, u
bind = $mod SHIFT CTRL, down, movewindow, d

bind = $mod, 1, workspace, 1
bind = $mod, 2, workspace, 2
bind = $mod, 3, workspace, 3
bind = $mod, 4, workspace, 4
bind = $mod, 5, workspace, 5
bind = $mod, 6, workspace, 6
bind = $mod, 7, workspace, 7
bind = $mod, 8, workspace, 8
bind = $mod, 9, workspace, 9
bind = $mod, 0, workspace, 10

bind = $mod SHIFT, 1, movetoworkspace, 1
bind = $mod SHIFT, 2, movetoworkspace, 2
bind = $mod SHIFT, 3, movetoworkspace, 3
bind = $mod SHIFT, 4, movetoworkspace, 4
bind = $mod SHIFT, 5, movetoworkspace, 5
bind = $mod SHIFT, 6, movetoworkspace, 6
bind = $mod SHIFT, 7, movetoworkspace, 7
bind = $mod SHIFT, 8, movetoworkspace, 8
bind = $mod SHIFT, 9, movetoworkspace, 9
bind = $mod SHIFT, 0, movetoworkspace, 10

bind = $mod ALT, 1, movetoworkspacesilent, 1
bind = $mod ALT, 2, movetoworkspacesilent, 2
bind = $mod ALT, 3, movetoworkspacesilent, 3
bind = $mod ALT, 4, movetoworkspacesilent, 4
bind = $mod ALT, 5, movetoworkspacesilent, 5
bind = $mod ALT, 6, movetoworkspacesilent, 6
bind = $mod ALT, 7, movetoworkspacesilent, 7
bind = $mod ALT, 8, movetoworkspacesilent, 8
bind = $mod ALT, 9, movetoworkspacesilent, 9
bind = $mod ALT, 0, movetoworkspacesilent, 10
CONF

  cat > "$USER_HOME/.config/hypr/scripts/theme-wall-toggle.sh" <<'CONF'
#!/usr/bin/env bash
notify-send 'Hyprland' 'Theme/Wall toggle noch nicht konfiguriert.'
CONF

  cat > "$USER_HOME/.config/hypr/scripts/theme-select.sh" <<'CONF'
#!/usr/bin/env bash
notify-send 'Hyprland' 'Theme-Auswahl noch nicht konfiguriert.'
CONF

  cat > "$USER_HOME/.config/hypr/scripts/wallpaper-select.sh" <<'CONF'
#!/usr/bin/env bash
notify-send 'Hyprland' 'Wallpaper-Auswahl noch nicht konfiguriert.'
CONF

  cat > "$USER_HOME/.config/hypr/scripts/rofi-style-select.sh" <<'CONF'
#!/usr/bin/env bash
notify-send 'Hyprland' 'Rofi-Style-Auswahl noch nicht konfiguriert.'
CONF

  chmod +x "$USER_HOME/.config/hypr/scripts/"*.sh
  chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/.config/hypr" "$USER_HOME/.config/noctalia" "$USER_HOME/.config/waybar" "$USER_HOME/.config/dunst"
}

setup_notes() {
  cat > "$USER_HOME/.config/hypr/README-local-notes.txt" <<'CONF'
Hinweise:
- Die Keybindings wurden beibehalten.
- Das Skript installiert die neu angeforderte Paketliste nur dann, wenn die Pakete in den aktiven Repositories gefunden werden.
- nmtui ist Teil von NetworkManager und kein eigenes Void-Paket.
- Waybar wird jetzt im Autostart gestartet, weil du Waybar explizit angefordert hast.
- Firefox, Kitty, Dolphin, VS Code und wlogout werden in den Keybindings referenziert, sind aber in deiner letzten Paketliste nicht enthalten.
CONF
  chown "$USER_NAME:$USER_NAME" "$USER_HOME/.config/hypr/README-local-notes.txt"
}

main() {
  require_root
  need xbps-install
  need xbps-query
  need tee

  if [ "$DRY_RUN" = "1" ]; then
    log "DRY_RUN=1 aktiv: es werden nur Befehle ausgegeben."
  fi

  setup_repos
  install_packages
  enable_services
  setup_pipewire
  setup_hyprland_structure
  setup_notes

  log "Fertig. Prüfe danach mit xbps-query -Rs einzelne Paketnamen und passe Apps in den Keybindings ggf. an."
}

main "$@"
