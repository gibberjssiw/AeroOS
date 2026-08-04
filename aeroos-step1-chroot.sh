#!/bin/bash
###############################################################################
# AeroOS - Step 1: Chroot Customization Script
# Run this INSIDE a Cubic chroot environment (or as a live-build chroot hook).
# It configures the GNOME desktop to mimic Windows 7 "Aero" aesthetics.
#
# Target:  Ubuntu 24.04 LTS (Noble Numbat) minimal base
# Constraints: 2GB RAM minimum, 16GB storage minimum
###############################################################################
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# 0.  Housekeeping
# ─────────────────────────────────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
LOG="/var/log/aeroos-build.log"
exec > >(tee -a "$LOG") 2>&1

echo "================================================"
echo " AeroOS Step 1 — Chroot Customization"
echo " $(date)"
echo "================================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ─────────────────────────────────────────────────────────────────────────────
# 1.  Purge heavy / unnecessary components  (RAM & storage diet)
# ─────────────────────────────────────────────────────────────────────────────
info "Purging heavy GNOME components and unnecessary packages…"

PURGE_PKGS=(
    # Office suite — far too heavy for a 2GB-RAM target
    libreoffice-core libreoffice-common libreoffice-gnome
    libreoffice-style-colibre libreoffice-style-yaru
    # Email & calendar
    thunderbird evolution evolution-data-server
    # Games
    gnome-games gnome-mines gnome-sudoku gnome-tetravex
    gnome-2048 gnome-nibbles gnome-robots gnome-taquin
    gnome-klotski gnome-taquin gnome-mahjongg
    # Media players we don't need (Totem is lightweight; Rhythmbox is not)
    rhythmbox rhythmbox-plugins
    # Social / chat
    transmission-common transmission-gtk
    # Accessibility tools that consume memory at startup
    orca
    # Snap runtime — we use apt only inside the ISO
    snapd
    # Printer stack (not needed on a live ISO)
    cups cups-daemon system-config-printer-common
    # Speech dispatcher
    speech-dispatcher espeak-ng
    # Modem manager (no mobile broadband on desktop ISO)
    modemmanager
    # Geo location service
    geoclue-2.0
    # Ubuntu report / apport (telemetry & crash popups)
    ubuntu-report apport
    # GNOME initial setup wizard (we pre-configure everything)
    gnome-initial-setup
    # Yelp help viewer
    yelp
    # Cheese webcam app
    cheese cheese-common
    # GNOME contacts, maps, weather, calendar, clocks (heavy + online)
    gnome-contacts gnome-maps gnome-weather gnome-calendar gnome-clocks
    # Deja-dup backup tool
    deja-dup
    # GNOME tour
    gnome-tour
)

apt-get purge -y "${PURGE_PKGS[@]}" 2>/dev/null || warn "Some packages were not installed; purge continued."
apt-get autoremove --purge -y
ok "Heavy packages purged."

# ─────────────────────────────────────────────────────────────────────────────
# 2.  Install core desktop + lightweight app set
# ─────────────────────────────────────────────────────────────────────────────
info "Installing GNOME Shell (minimal) and essential packages…"

INSTALL_PKGS=(
    # Minimal GNOME Shell (no full meta-package to keep it lean)
    gnome-shell
    gnome-session
    gdm3
    # Control center & settings daemons
    gnome-control-center
    gnome-settings-daemon
    # File manager + basic apps
    nautilus
    gnome-text-editor
    gnome-system-monitor
    eog                       # image viewer
    evince                    # document viewer (PDF)
    # Terminal
    gnome-terminal
    gnome-terminal-data
    # Web browser — Firefox is the only "heavy" app we keep
    firefox
    # GNOME extension tooling
    gnome-shell-extension-manager
    # dconf CLI for schema overrides
    dconf-cli
    dconf-editor
    # Plymouth for boot animation (Step 2 will configure the theme)
    plymouth
    plymouth-themes
    # Fonts
    fonts-cantarell
    fonts-dejavu-core
    fonts-liberation
    # X11 / Wayland essentials
    xserver-xorg
    xwayland
    # Network
    network-manager
    network-manager-gnome
    # Audio
    pipewire
    pipewire-pulse
    pipewire-alsa
    wireplumber
    # Misc utilities
    curl
    wget
    ca-certificates
    unzip
    jq
    # GNOME tweaks
    gnome-tweaks
    # GSettings desktop schemas (required for dconf overrides)
    gsettings-desktop-schemas
)

apt-get update -y
apt-get install -y "${INSTALL_PKGS[@]}"
ok "Core packages installed."

# ─────────────────────────────────────────────────────────────────────────────
# 3.  Install GNOME Extensions
#     Dash to Panel  — via apt (universe)
#     Arc Menu       — manual from GitHub (not packaged in apt)
#     Blur my Shell  — manual from GitHub (not packaged in apt)
# ─────────────────────────────────────────────────────────────────────────────
info "Installing GNOME extensions…"

# 3a. Dash to Panel (available in Ubuntu universe)
apt-get install -y gnome-shell-extension-dash-to-panel || warn "dash-to-panel not in apt; will install manually."

# 3b. Helper: install extension from GitHub release zip
install_extension_from_url() {
    local url="$1"
    local ext_uuid="$2"   # e.g. "dash-to-panel@jderose9.github.com"
    local tmp_zip="/tmp/${ext_uuid}.zip"
    local ext_dir="/usr/share/gnome-shell/extensions/${ext_uuid}"

    info "Fetching extension: ${ext_uuid}"
    wget -q -O "$tmp_zip" "$url" || { err "Failed to download $url"; return 1; }

    mkdir -p "$ext_dir"
    unzip -q -o "$tmp_zip" -d "$ext_dir"
    rm -f "$tmp_zip"

    # Ensure metadata is at the right level
    if [ ! -f "${ext_dir}/metadata.json" ]; then
        # Some zips have a top-level folder; flatten
        local top_dir
        top_dir=$(find "$ext_dir" -maxdepth 1 -type d -not -path "$ext_dir" | head -1)
        if [ -n "$top_dir" ] && [ -f "${top_dir}/metadata.json" ]; then
            cp -r "${top_dir}"/* "$ext_dir"/
            rm -rf "$top_dir"
        fi
    fi

    ok "Installed: ${ext_uuid}"
}

# 3c. Arc Menu (latest release from GitHub)
#     Repository: https://github.com/arc-menu/ArcMenu
ARC_MENU_URL="https://github.com/arc-menu/ArcMenu/releases/latest/download/arc-menu.zip"
# Fallback: direct versioned URL if 'latest' alias doesn't resolve
ARC_MENU_FALLBACK="https://extensions.gnome.org/extension-data/arcmenu@arcmenu.com.shell-extension.zip"

install_extension_from_url "$ARC_MENU_URL" "arcmenu@arcmenu.com" \
    || install_extension_from_url "$ARC_MENU_FALLBACK" "arcmenu@arcmenu.com" \
    || warn "Arc Menu manual install failed — will be available via Extension Manager."

# 3d. Blur my Shell (latest release from GitHub)
#     Repository: https://github.com/aunetx/blur-my-shell
BLUR_URL="https://github.com/aunetx/blur-my-shell/releases/latest/download/blur-my-shell.zip"
BLUR_FALLBACK="https://extensions.gnome.org/extension-data/blur-my-shell@aunetx.com.shell-extension.zip"

install_extension_from_url "$BLUR_URL" "blur-my-shell@aunetx.com" \
    || install_extension_from_url "$BLUR_FALLBACK" "blur-my-shell@aunetx.com" \
    || warn "Blur my Shell manual install failed — will be available via Extension Manager."

# 3e. Compile GNOME shell schemas so extensions register properly
glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>/dev/null || true
ok "GNOME extensions installed."

# ─────────────────────────────────────────────────────────────────────────────
# 4.  dconf schema overrides — Windows 7 layout out-of-the-box
# ─────────────────────────────────────────────────────────────────────────────
info "Writing dconf schema overrides for Windows 7 layout…"

# 4a. Create the dconf profile that reads our overrides
mkdir -p /etc/dconf/profile
cat > /etc/dconf/profile/user <<'PROFILE'
user-db:user
system-db:local
PROFILE

# 4b. Create the directory for system-level overrides
mkdir -p /etc/dconf/db/local.d

# 4c. --- Dash to Panel: bottom taskbar, window buttons on right, app icons ---
cat > /etc/dconf/db/local.d/00-dash-to-panel <<'DTP'
# Dash to Panel — Windows 7 taskbar layout
[/org/gnome/shell/extensions/dash-to-panel/]
panel-position='BOTTOM'
panel-size=40
location-clock='RIGHT'
show-show-apps-button=false
show-appmenu=false
show-favorites=true
show-running-apps=true
isolate-workspaces=false
transparency-mode='DYNAMIC'
panel-element-positions='{"left":[{"element":"showApps","visible":false,"position":0},{"element":"activitiesButton","visible":false,"position":0},{"element":"leftbox","visible":true,"position":1},{"element":"taskbar","visible":true,"position":2}],"center":[],"right":[{"element":"systemmenu","visible":true,"position":0},{"element":"dateMenu","visible":true,"position":1},{"element":"rightbox","visible":true,"position":2}]}'
window-preview-title-position='TOP'
window-preview-show-title=true
window-preview-fixed-x-position=0
window-preview-use-custom-opacity=true
window-preview-custom-opacity=0.85
group-apps=true
group-apps-use-launchers=true
scroll-panel-action='SWITCH_WORKSPACE'
scroll-icon-action='CYCLE_WINDOWS'
intellihide=false
stockgs-keep-top-panel=false
animate-window-switch-to-workspace=true
animate-window-switch-to-app=true
DTP

# 4d. --- Arc Menu: Windows 7-style Start Menu ---
cat > /etc/dconf/db/local.d/01-arc-menu <<'ARC'
# Arc Menu — Windows 7 Start Menu style
[/org/gnome/shell/extensions/arcmenu/]
arc-menu-placement='DTP'
menu-button-icon='aeroos-logo.svg'
menu-button-icon-type='SYSTEM'
menu-button-position='LEFT'
menu-button-text=''
menu-button-favicon-path='/usr/share/icons/aeroos/aeroos-logo.svg'
menu-layout='Windows_7'
menu-hotkey='Super_L'
windows7-search-bar=true
windows7-show-power-options=true
windows7-show-settings=true
windows7-show-devices=true
windows7-show-default-places=true
windows7-show-recent-files=true
windows7-show-bookmarks=true
shortcuts-list=['files', 'terminal', 'firefox', 'text-editor', 'system-monitor']
enable-custom-arc-menu=true
disable-recent-items=false
category-directories=true
power-options-placement='bottom'
show-search-box=true
search-bar-default-open=true
menu-width=450
menu-height=500
ARC

# 4e. --- Blur my Shell: translucent panel & app headers (Aero Glass) ---
cat > /etc/dconf/db/local.d/02-blur-my-shell <<'BMS'
# Blur my Shell — Aero Glass translucency
[/org/gnome/shell/extensions/blur-my-shell/panel/]
blur=true
sigma=20
brightness=0.6
static-blur=true
style-transparency=0.85

[/org/gnome/shell/extensions/blur-my-shell/overview/]
blur=true
sigma=15
brightness=0.65

[/org/gnome/shell/extensions/blur-my-shell/appfolder/]
blur=true
sigma=15

[/org/gnome/shell/extensions/blur-my-shell/lockscreen/]
blur=true
sigma=20

[/org/gnome/shell/extensions/blur-my-shell/screenshot/]
blur=true
sigma=15

[/org/gnome/shell/extensions/blur-my-shell/window-list/]
blur=true
sigma=15
BMS

# 4f. --- GNOME Shell global: disable Ubuntu dock, enable extensions, desktop icons ---
cat > /etc/dconf/db/local.d/03-gnome-shell <<'GS'
# GNOME Shell — global desktop settings for AeroOS
[/org/gnome/shell/]
disabled-extensions=['ubuntu-dock@ubuntu.com', 'ding@rastersoft.com']
enabled-extensions=['dash-to-panel@jderose9.github.com', 'arcmenu@arcmenu.com', 'blur-my-shell@aunetx.com', 'desktop-icons@rastersoft.com']
favorite-apps=['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.TextEditor.desktop', 'org.gnome.SystemMonitor.desktop']

[/org/gnome/shell/extensions/desktop-icons/]
show-home=true
show-trash=true
icon-size='large'

[/org/gnome/desktop/background/]
picture-uri='file:///usr/share/backgrounds/aeroos/aeroos-wallpaper.png'
picture-uri-dark='file:///usr/share/backgrounds/aeroos/aeroos-wallpaper.png'
picture-options='zoom'

[/org/gnome/desktop/interface/]
gtk-theme='Yaru'
icon-theme='Yaru'
font-name='Cantarell 11'
monospace-font-name='DejaVu Sans Mono 11'
color-scheme='default'

[/org/gnome/desktop/wm/preferences/]
button-layout=':minimize,maximize,close'
titlebar-font='Cantarell Bold 11'

[/org/gnome/mutter/]
attach-modal-dialogs=true
center-new-windows=true
workspaces-only-on-primary=true

[/org/gnome/desktop/session/]
idle-delay=0

[/org/gnome/settings-daemon/plugins/power/]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
GS

# 4g. --- GNOME Terminal profile: Windows Command Prompt style ---
cat > /etc/dconf/db/local.d/04-terminal <<'TERM'
# GNOME Terminal — Windows Command Prompt styling
[/org/gnome/terminal/legacy/]
schema-version=3

[/org/gnome/terminal/legacy/profiles:/:aeroos-cmd/]
visible-name='AeroOS Command Prompt'
foreground-color='rgb(255,255,255)'
background-color='rgb(0,0,0)'
use-theme-colors=false
use-system-font=false
font='DejaVu Sans Mono 12'
scrollbar-policy='never'
scroll-on-output=true
scroll-on-keystroke=true
login-shell=false
bold-is-bright=true
cursor-shape='block'
cursor-blink-mode='on'
backspace-binding='ascii-delete'
delete-binding='ascii-delete'
title-mode='ignore'
title='Command Prompt - AeroOS'
custom-command=''
use-custom-command=false
palette=['rgb(12,12,12)', 'rgb(204,0,0)', 'rgb(78,154,6)', 'rgb(196,160,0)', 'rgb(52,101,164)', 'rgb(117,80,123)', 'rgb(6,152,154)', 'rgb(211,215,207)', 'rgb(85,87,83)', 'rgb(239,41,41)', 'rgb(138,226,52)', 'rgb(252,233,79)', 'rgb(114,159,207)', 'rgb(173,127,168)', 'rgb(52,226,226)', 'rgb(238,238,236)']
TERM

# 4h. Set the default terminal profile to our AeroOS Command Prompt
cat >> /etc/dconf/db/local.d/04-terminal <<'TERM_DEFAULT'
[/org/gnome/terminal/legacy/profiles:/]
default='aeroos-cmd'
list=['aeroos-cmd']
TERM_DEFAULT

# 4i. Compile dconf databases
dconf update
ok "dconf overrides written and compiled."

# ─────────────────────────────────────────────────────────────────────────────
# 5.  Autostart: Command Prompt terminal on login
# ─────────────────────────────────────────────────────────────────────────────
info "Creating autostart entry for Command Prompt terminal…"

mkdir -p /etc/xdg/autostart

cat > /etc/xdg/autostart/aeroos-command-prompt.desktop <<'AUTOSTART'
[Desktop Entry]
Type=Application
Name=AeroOS Command Prompt
Comment=Automatically launch a Windows-style Command Prompt on login
Exec=gnome-terminal --profile=aeroos-cmd --title="Command Prompt - AeroOS" --geometry=80x24+50+50
Icon=utilities-terminal
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
NoDisplay=false
Categories=System;
StartupNotify=false
AUTOSTART

ok "Autostart .desktop created at /etc/xdg/autostart/aeroos-command-prompt.desktop"

# ─────────────────────────────────────────────────────────────────────────────
# 6.  Custom Branding — /etc/os-release
# ─────────────────────────────────────────────────────────────────────────────
info "Writing AeroOS branding to /etc/os-release…"

cat > /etc/os-release <<'OSRELEASE'
NAME="AeroOS"
VERSION="1.0 (Noble Numbat)"
ID=aeroos
ID_LIKE=ubuntu
PRETTY_NAME="AeroOS 1.0"
VERSION_ID="1.0"
HOME_URL="https://aeroos.example.com"
SUPPORT_URL="https://aeroos.example.com/support"
BUG_REPORT_URL="https://aeroos.example.com/bugs"
PRIVACY_POLICY_URL="https://aeroos.example.com/privacy"
VERSION_CODENAME=noble
UBUNTU_CODENAME=noble
OSRELEASE

# Also update lsb-release if it exists
if [ -f /etc/lsb-release ]; then
    cat > /etc/lsb-release <<'LSB'
DISTRIB_ID=AeroOS
DISTRIB_RELEASE=1.0
DISTRIB_CODENAME=noble
DISTRIB_DESCRIPTION="AeroOS 1.0 (Noble Numbat)"
LSB
fi

# Update hostname
echo "aeroos" > /etc/hostname

ok "Branding applied to /etc/os-release and /etc/lsb-release."

# ─────────────────────────────────────────────────────────────────────────────
# 7.  Wallpaper & Logo placeholders
# ─────────────────────────────────────────────────────────────────────────────
info "Creating wallpaper and logo placeholders…"

mkdir -p /usr/share/backgrounds/aeroos
mkdir -p /usr/share/icons/aeroos

# 7a. Generate a placeholder wallpaper using ImageMagick if available,
#     otherwise create a simple SVG that GNOME can render.
if command -v convert &>/dev/null; then
    # Create a 1920x1080 gradient wallpaper with AeroOS text
    convert -size 1920x1080 \
        gradient:'#003366'-'#0066cc' \
        -fill 'rgba(255,255,255,0.15)' \
        -draw "roundrectangle 100,400 1820,680 20" \
        -font DejaVu-Sans-Bold -pointsize 120 -fill white \
        -gravity center -annotate +0-50 "AeroOS" \
        -pointsize 32 -fill 'rgba(255,255,255,0.7)' \
        -annotate +0+60 "Aero Glass Edition" \
        /usr/share/backgrounds/aeroos/aeroos-wallpaper.png 2>/dev/null \
        || warn "ImageMagick wallpaper generation failed; using SVG fallback."
fi

# 7b. SVG fallback wallpaper (always create as backup)
cat > /usr/share/backgrounds/aeroos/aeroos-wallpaper.svg <<'WALLPAPER_SVG'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#001a33"/>
      <stop offset="50%" style="stop-color:#003366"/>
      <stop offset="100%" style="stop-color:#0066cc"/>
    </linearGradient>
    <linearGradient id="glass" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:rgba(255,255,255,0.20)"/>
      <stop offset="100%" style="stop-color:rgba(255,255,255,0.05)"/>
    </linearGradient>
    <filter id="blur">
      <feGaussianBlur stdDeviation="3"/>
    </filter>
  </defs>
  <rect width="1920" height="1080" fill="url(#bg)"/>
  <!-- Glass panel -->
  <rect x="200" y="380" width="1520" height="320" rx="15" fill="url(#glass)" filter="url(#blur)"/>
  <rect x="200" y="380" width="1520" height="320" rx="15" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="2"/>
  <!-- Logo orb (simplified Windows 7-style flag placeholder) -->
  <g transform="translate(960,460)">
    <circle cx="0" cy="0" r="55" fill="rgba(255,255,255,0.15)" stroke="rgba(255,255,255,0.4)" stroke-width="2"/>
    <path d="M-30,-20 L-5,-25 L-5,0 L-30,0 Z M5,-25 L30,-20 L30,0 L5,0 Z M-30,5 L-5,5 L-5,30 L-30,25 Z M5,5 L30,5 L30,25 L5,30 Z"
          fill="rgba(255,255,255,0.6)"/>
  </g>
  <!-- Text -->
  <text x="960" y="580" text-anchor="middle" font-family="Cantarell, sans-serif" font-size="72" font-weight="bold" fill="white" opacity="0.95">AeroOS</text>
  <text x="960" y="630" text-anchor="middle" font-family="Cantarell, sans-serif" font-size="28" fill="rgba(255,255,255,0.6)">Aero Glass Edition</text>
</svg>
WALLPAPER_SVG

# If PNG wasn't created, symlink the SVG as the wallpaper
if [ ! -f /usr/share/backgrounds/aeroos/aeroos-wallpaper.png ]; then
    # Update dconf to point to SVG
    sed -i 's|aeroos-wallpaper.png|aeroos-wallpaper.svg|g' /etc/dconf/db/local.d/03-gnome-shell
    dconf update
fi

# 7c. Create the AeroOS logo SVG (used by Arc Menu start button)
cat > /usr/share/icons/aeroos/aeroos-logo.svg <<'LOGO_SVG'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
  <defs>
    <radialGradient id="orb" cx="50%" cy="50%" r="50%">
      <stop offset="0%" style="stop-color:rgba(120,180,255,0.9)"/>
      <stop offset="60%" style="stop-color:rgba(40,100,200,0.7)"/>
      <stop offset="100%" style="stop-color:rgba(0,40,100,0.5)"/>
    </radialGradient>
  </defs>
  <circle cx="24" cy="24" r="22" fill="url(#orb)" stroke="rgba(255,255,255,0.5)" stroke-width="1.5"/>
  <g transform="translate(24,24)">
    <path d="M-14,-10 L-2,-12 L-2,0 L-14,0 Z M2,-12 L14,-10 L14,0 L2,0 Z M-14,2 L-2,2 L-2,12 L-14,10 Z M2,2 L14,2 L14,10 L2,12 Z"
          fill="rgba(255,255,255,0.8)"/>
  </g>
</svg>
LOGO_SVG

ok "Wallpaper and logo placeholders created."

# ─────────────────────────────────────────────────────────────────────────────
# 8.  GDM / Login screen configuration
# ─────────────────────────────────────────────────────────────────────────────
info "Configuring GDM login screen…"

# 8a. GDM dconf overrides (login screen uses its own dconf database)
mkdir -p /etc/dconf/profile
cat > /etc/dconf/profile/gdm <<'GDM_PROFILE'
user-db:gdm
system-db:gdm
GDM_PROFILE

mkdir -p /etc/dconf/db/gdm.d
cat > /etc/dconf/db/gdm.d/00-aeroos-login <<'GDM_LOGIN'
# GDM login screen — AeroOS branding
[/org/gnome/desktop/background/]
picture-uri='file:///usr/share/backgrounds/aeroos/aeroos-wallpaper.svg'
picture-options='zoom'

[/org/gnome/login-screen/]
logo='/usr/share/icons/aeroos/aeroos-logo.svg'
disable-user-list=false
banner-message-enabled=true
banner-message-text='Welcome to AeroOS — Aero Glass Edition'
GDM_LOGIN

dconf update
ok "GDM login screen configured."

# ─────────────────────────────────────────────────────────────────────────────
# 9.  Enable/disable systemd services for low-RAM optimization
# ─────────────────────────────────────────────────────────────────────────────
info "Tuning systemd services for low-RAM operation…"

# Disable services we don't need on a lightweight desktop ISO
SERVICES_TO_DISABLE=(
    apport.service
    speech-dispatcher.service
    modemmanager.service
    geoclue.service
    cups.service
    cups-browsed.service
    fwupd.service
    packagekit.service
    switcheroo-control.service
    avahi-daemon.service
    colord.service
    udisks2.service        # re-enabled by GNOME if needed
)

for svc in "${SERVICES_TO_DISABLE[@]}"; do
    systemctl disable "$svc" 2>/dev/null || true
done

# Enable essential services
systemctl enable NetworkManager 2>/dev/null || true
systemctl enable gdm 2>/dev/null || true
systemctl enable pipewire pipewire-pulse wireplumber 2>/dev/null || true

ok "Systemd services tuned."

# ─────────────────────────────────────────────────────────────────────────────
# 10.  Swappiness & kernel tuning for 2GB RAM
# ─────────────────────────────────────────────────────────────────────────────
info "Applying kernel tuning for 2GB RAM target…"

cat > /etc/sysctl.d/99-aeroos.conf <<'SYSCTL'
# AeroOS — optimized for 2GB RAM / 16GB storage
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5
# Reduce watchdog timers (saves CPU)
kernel.watchdog=0
# ZRAM-friendly settings
vm.watermark_boost_factor=1
SYSCTL

ok "Kernel tuning applied."

# ─────────────────────────────────────────────────────────────────────────────
# 11.  Create the default user's desktop shortcuts
# ─────────────────────────────────────────────────────────────────────────────
info "Setting up desktop shortcut capabilities…"

# Ensure the desktop icons extension data directory exists
mkdir -p /usr/share/gnome-shell/extensions

# Create a skel directory entry for desktop shortcuts that will appear
# for every new user on first login
mkdir -p /etc/skel/Desktop

# Firefox shortcut
cat > /etc/skel/Desktop/firefox.desktop <<'FF_DESKTOP'
[Desktop Entry]
Type=Application
Name=Mozilla Firefox
Comment=Web Browser
Exec=firefox
Icon=firefox
Terminal=false
Categories=Network;WebBrowser;
FF_DESKTOP

# Files (Nautilus) shortcut
cat > /etc/skel/Desktop/nautilus.desktop <<'NAU_DESKTOP'
[Desktop Entry]
Type=Application
Name=Files
Comment=File Manager
Exec=nautilus
Icon=org.gnome.Nautilus
Terminal=false
Categories=System;FileManager;
NAU_DESKTOP

# Terminal shortcut
cat > /etc/skel/Desktop/terminal.desktop <<'TERM_DESKTOP'
[Desktop Entry]
Type=Application
Name=Command Prompt
Comment=AeroOS Command Prompt
Exec=gnome-terminal --profile=aeroos-cmd --title="Command Prompt - AeroOS"
Icon=utilities-terminal
Terminal=false
Categories=System;TerminalEmulator;
TERM_DESKTOP

chmod +x /etc/skel/Desktop/*.desktop

ok "Desktop shortcuts created in /etc/skel/Desktop."

# ─────────────────────────────────────────────────────────────────────────────
# 12.  Clean up — remove caches, reduce ISO size
# ─────────────────────────────────────────────────────────────────────────────
info "Cleaning up to reduce ISO size…"

apt-get clean
apt-get autoremove --purge -y
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*.deb
rm -rf /tmp/*
rm -rf /var/tmp/*
rm -rf /var/log/*.log
rm -rf /var/log/apt/*
# Remove doc and man pages to save space (optional but helps hit 16GB target)
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
rm -rf /usr/share/info/*
rm -rf /usr/share/lintian/*
ok "Cleanup complete."

# ─────────────────────────────────────────────────────────────────────────────
# 13.  Final summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "================================================"
echo " AeroOS Step 1 — COMPLETE"
echo "================================================"
echo ""
echo " What was configured:"
echo "   ✓ Heavy GNOME packages purged (LibreOffice, Thunderbird, games, etc.)"
echo "   ✓ GNOME Shell (minimal) + GDM3 installed"
echo "   ✓ GNOME Extensions installed:"
echo "       - Dash to Panel  (bottom taskbar)"
echo "       - Arc Menu       (Windows 7 Start Menu)"
echo "       - Blur my Shell  (Aero Glass translucency)"
echo "   ✓ dconf overrides written to /etc/dconf/db/local.d/"
echo "   ✓ Command Prompt autostart at /etc/xdg/autostart/"
echo "   ✓ AeroOS branding in /etc/os-release"
echo "   ✓ Wallpaper & logo placeholders created"
echo "   ✓ GDM login screen branded"
echo "   ✓ Kernel tuned for 2GB RAM"
echo "   ✓ Desktop shortcuts in /etc/skel/Desktop/"
echo ""
echo " Next: Step 2 — Plymouth boot animation (Windows 7 orb)"
echo "        Step 3 — ISO compilation & packaging"
echo "================================================"
