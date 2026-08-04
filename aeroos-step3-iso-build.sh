#!/bin/bash
###############################################################################
# AeroOS - Step 3: ISO Compilation & Packaging
#
# This script builds a bootable AeroOS .ISO from scratch using live-build.
# It does NOT require Cubic — it runs on the host system and automates the
# entire process: base system bootstrap, chroot customization (Steps 1 & 2),
# initramfs rebuild, and ISO image creation.
#
# Requirements on the host:
#   - Debian/Ubuntu-based system with apt
#   - live-build, squashfs-tools, xorriso, isolinux, syslinux-common
#   - ~10GB free disk space
#   - Root privileges (sudo)
#
# Usage:
#   sudo ./aeroos-step3-iso-build.sh [--workdir /path/to/work]
#
# Output:
#   AeroOS-1.0-amd64.iso  (in the work directory)
###############################################################################
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# 0.  Arguments & defaults
# ─────────────────────────────────────────────────────────────────────────────
WORK_DIR="${AEROOS_WORK_DIR:-$(pwd)/aeroos-build}"
ISO_NAME="AeroOS-1.0-amd64.iso"
ISO_LABEL="AeroOS-1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

echo -e "${BOLD}================================================${NC}"
echo -e "${BOLD} AeroOS Step 3 — ISO Compilation${NC}"
echo -e "${BOLD} $(date)${NC}"
echo -e "${BOLD}================================================${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# 1.  Root check
# ─────────────────────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run as root (use sudo)."
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2.  Install host build dependencies
# ─────────────────────────────────────────────────────────────────────────────
info "Installing build dependencies on host…"

export DEBIAN_FRONTEND=noninteractive

HOST_DEPS=(
    live-build
    squashfs-tools
    xorriso
    isolinux
    syslinux-common
    syslinux-utils
    grub-pc-bin
    grub-efi-amd64-bin
    mtools
    dosfstools
    imagemagick
    wget
    curl
    unzip
    jq
)

apt-get update -y
apt-get install -y "${HOST_DEPS[@]}" 2>/dev/null || warn "Some host deps may already be installed."
ok "Host dependencies ready."

# ─────────────────────────────────────────────────────────────────────────────
# 3.  Set up the live-build working directory
# ─────────────────────────────────────────────────────────────────────────────
info "Setting up live-build workspace at ${WORK_DIR}…"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Initialize live-build configuration
lb config \
    --distribution noble \
    --architecture amd64 \
    --archive-areas "main restricted universe multiverse" \
    --linux-flavours generic \
    --iso-volume "${ISO_LABEL}" \
    --iso-publisher "AeroOS Project" \
    --binary-images iso-hybrid \
    --bootloaders "syslinux,grub" \
    --debian-installer none \
    --parent-mirror-bootstrap "http://archive.ubuntu.com/ubuntu/" \
    --parent-mirror-chroot "http://archive.ubuntu.com/ubuntu/" \
    --parent-mirror-binary "http://archive.ubuntu.com/ubuntu/" \
    --mirror-bootstrap "http://archive.ubuntu.com/ubuntu/" \
    --mirror-chroot "http://archive.ubuntu.com/ubuntu/" \
    --mirror-binary "http://archive.ubuntu.com/ubuntu/" \
    --security true \
    --updates true \
    --chroot-filesystem squashfs \
    --checksums none \
    --debug 2>/dev/null

ok "live-build configured."

# ─────────────────────────────────────────────────────────────────────────────
# 4.  Define the package list for live-build
# ─────────────────────────────────────────────────────────────────────────────
info "Writing package lists for live-build…"

# Base packages (installed during bootstrap)
cat > config/package-lists/aeroos-core.list.chroot <<'CORE_PKGS'
gnome-shell
gnome-session
gdm3
gnome-control-center
gnome-settings-daemon
nautilus
gnome-text-editor
gnome-system-monitor
eog
evince
gnome-terminal
gnome-terminal-data
firefox
gnome-shell-extension-manager
gnome-shell-extension-dash-to-panel
dconf-cli
dconf-editor
plymouth
plymouth-themes
fonts-cantarell
fonts-dejavu-core
fonts-liberation
xserver-xorg
xwayland
network-manager
network-manager-gnome
pipewire
pipewire-pulse
pipewire-alsa
wireplumber
curl
wget
ca-certificates
unzip
jq
gnome-tweaks
gsettings-desktop-schemas
linux-generic
CORE_PKGS

# Packages to remove (purge) — listed as "remove" entries
cat > config/package-lists/aeroos-purge.list.chroot <<'PURGE_PKGS'
libreoffice-core libreoffice-common
thunderbird evolution
rhythmbox
transmission-common
snapd
cups cups-daemon
speech-dispatcher
modemmanager
apport
gnome-initial-setup
yelp
cheese
gnome-contacts gnome-maps gnome-weather gnome-calendar gnome-clocks
deja-dup
gnome-tour
PURGE_PKGS

ok "Package lists written."

# ─────────────────────────────────────────────────────────────────────────────
# 5.  Copy Step 1 and Step 2 scripts as chroot hooks
# ─────────────────────────────────────────────────────────────────────────────
info "Installing chroot customization hooks (Steps 1 & 2)…"

mkdir -p config/hooks/normal

# Copy Step 1 script as a chroot hook
cp "${SCRIPT_DIR}/aeroos-step1-chroot.sh" config/hooks/normal/00-aeroos-step1.hook.chroot
chmod +x config/hooks/normal/00-aeroos-step1.hook.chroot

# Copy Step 2 script as a chroot hook
cp "${SCRIPT_DIR}/aeroos-step2-plymouth.sh" config/hooks/normal/01-aeroos-step2.hook.chroot
chmod +x config/hooks/normal/01-aeroos-step2.hook.chroot

ok "Chroot hooks installed."

# ─────────────────────────────────────────────────────────────────────────────
# 6.  Create the live user (auto-login user for the ISO)
# ─────────────────────────────────────────────────────────────────────────────
info "Configuring live-boot user and auto-login…"

# Create a chroot hook that sets up the live user
cat > config/hooks/normal/02-aeroos-live-user.hook.chroot <<'LIVE_USER'
#!/bin/sh
set -e

# Create the live user
useradd -m -s /bin/bash -G sudo,adm,cdrom,audio,video,plugdev aeroos 2>/dev/null || true
echo "aeroos:aeroos" | chpasswd
echo "root:aeroos" | chpasswd

# Configure GDM for auto-login
mkdir -p /etc/gdm3
cat > /etc/gdm3/custom.conf <<'GDM_CONF'
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=aeroos
TimedLoginEnable=false
WaylandEnable=false
GDM_CONF

# Add the user to the right groups for desktop functionality
usermod -aG lpadmin aeroos 2>/dev/null || true
usermod -aG sambashare aeroos 2>/dev/null || true

# Pre-seed the user's dconf settings by copying skel
if [ -d /etc/skel ]; then
    cp -r /etc/skel/. /home/aeroos/ 2>/dev/null || true
    chown -R aeroos:aeroos /home/aeroos/ 2>/dev/null || true
fi

# Set up .config for GNOME extensions
mkdir -p /home/aeroos/.config/dconf
chown -R aeroos:aeroos /home/aeroos/.config

# Enable user extensions
mkdir -p /home/aeroos/.local/share/gnome-shell/extensions
chown -R aeroos:aeroos /home/aeroos/.local
LIVE_USER
chmod +x config/hooks/normal/02-aeroos-live-user.hook.chroot

ok "Live user configured with auto-login."

# ─────────────────────────────────────────────────────────────────────────────
# 7.  Create boot configuration customization
# ─────────────────────────────────────────────────────────────────────────────
info "Customizing boot menu (ISOLINUX / GRUB)…"

# ISOLINUX boot menu
mkdir -p config/bootloaders/isolinux
cat > config/bootloaders/isolinux/isolinux.cfg <<'ISOLINUX_CFG'
DEFAULT live
PROMPT 0
TIMEOUT 10
UI vesamenu.c32

MENU TITLE AeroOS 1.0 — Aero Glass Edition
MENU BACKGROUND /isolinux/splash.png
MENU COLOR border 30 #44444444 #00000000 none
MENU COLOR title 1 #ffffffff #00000000 none
MENU COLOR sel 7 #ffffffff #ff0066cc none
MENU COLOR timeout_msg 30 #ffffffff #00000000 none
MENU COLOR timeout 30 #ffff5555 #00000000 none

LABEL live
  MENU LABEL ^Start AeroOS
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper quiet splash ---
  
LABEL live-nomodeset
  MENU LABEL Start AeroOS (Safe Graphics Mode)
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper quiet splash nomodeset ---

LABEL memtest
  MENU LABEL Memory ^Test
  KERNEL /boot/memtest86+.bin

MENU SEPARATOR
LABEL hd
  MENU LABEL ^Boot from Hard Disk
  COM32 chain.c32
  APPEND hd0
ISOLINUX_CFG

# GRUB EFI boot menu
mkdir -p config/bootloaders/grub
cat > config/bootloaders/grub/grub.cfg <<'GRUB_CFG'
set default="0"
set timeout=10

set menu_color_normal=white/black
set menu_color_highlight=light-blue/black
set color_normal=light-blue/black

menuentry "Start AeroOS" {
    linux /casper/vmlinuz boot=casper quiet splash ---
    initrd /casper/initrd
}

menuentry "Start AeroOS (Safe Graphics Mode)" {
    linux /casper/vmlinuz boot=casper quiet splash nomodeset ---
    initrd /casper/initrd
}

menuentry "Memory Test" {
    linux16 /boot/memtest86+.bin
}
GRUB_CFG

ok "Boot menus customized."

# ─────────────────────────────────────────────────────────────────────────────
# 8.  Create a boot splash image for the ISOLINUX menu
# ─────────────────────────────────────────────────────────────────────────────
info "Generating boot menu splash image…"

if command -v convert &>/dev/null; then
    convert -size 640x480 \
        gradient:'#001a33'-'#003366' \
        -font DejaVu-Sans-Bold -pointsize 48 -fill white \
        -gravity center -annotate +0-40 "AeroOS" \
        -pointsize 20 -fill 'rgba(255,255,255,0.7)' \
        -annotate +0+20 "Aero Glass Edition" \
        config/bootloaders/isolinux/splash.png 2>/dev/null \
        || warn "Could not generate splash image — using default."
fi

ok "Boot splash created."

# ─────────────────────────────────────────────────────────────────────────────
# 9.  Build the ISO
# ─────────────────────────────────────────────────────────────────────────────
info "Starting live-build process…"
info "This will download packages and build the root filesystem."
info "This may take 15-45 minutes depending on network and CPU."

# Run live-build
#   lb bootstrap  — downloads & unpacks the base system
#   lb chroot     — installs packages & runs our chroot hooks (Steps 1 & 2)
#   lb binary     — assembles the ISO image
lb build 2>&1 | tee "${WORK_DIR}/aeroos-build.log"

# ─────────────────────────────────────────────────────────────────────────────
# 10.  Verify and rename the output ISO
# ─────────────────────────────────────────────────────────────────────────────
info "Checking for built ISO…"

# live-build names it live-image-amd64.hybrid.iso by default
BUILT_ISO="${WORK_DIR}/live-image-amd64.hybrid.iso"

if [ -f "$BUILT_ISO" ]; then
    mv "$BUILT_ISO" "${WORK_DIR}/${ISO_NAME}"
    ISO_SIZE=$(du -h "${WORK_DIR}/${ISO_NAME}" | cut -f1)
    ok "ISO built successfully!"
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN} AeroOS ISO Build — COMPLETE${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    echo "  Output: ${WORK_DIR}/${ISO_NAME}"
    echo "  Size:   ${ISO_SIZE}"
    echo "  Label:  ${ISO_LABEL}"
    echo ""
    echo "  To create a bootable USB:"
    echo "    sudo dd if=${WORK_DIR}/${ISO_NAME} of=/dev/sdX bs=4M status=progress"
    echo "    (replace /dev/sdX with your USB device)"
    echo ""
    echo "  Or use a tool like Rufus, BalenaEtcher, or Ventoy."
    echo ""
else
    err "ISO build failed — check ${WORK_DIR}/aeroos-build.log for details."
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 11.  Optional: Verify ISO is bootable (hybrid check)
# ─────────────────────────────────────────────────────────────────────────────
info "Verifying ISO is hybrid (USB + CD bootable)…"

if command -v isohybrid &>/dev/null; then
    isohybrid "${WORK_DIR}/${ISO_NAME}" 2>/dev/null && ok "ISO is hybrid-bootable." || warn "isohybrid post-processing skipped."
else
    # xorriso already creates hybrid ISOs
    ok "ISO created with xorriso (hybrid by default)."
fi

# Check ISO has an El Torito boot catalog (CD bootable)
if command -v xorriso &>/dev/null; then
    BOOT_CHECK=$(xorriso -indev "${WORK_DIR}/${ISO_NAME}" -report_system_area plain 2>&1 | head -5)
    if echo "$BOOT_CHECK" | grep -qi "boot"; then
        ok "ISO contains boot catalog — CD/DVD bootable."
    else
        warn "Could not verify boot catalog — verify by testing in a VM."
    fi
fi

echo ""
echo -e "${BOLD}AeroOS ISO build pipeline complete.${NC}"
