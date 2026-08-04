#!/bin/bash
set -e

mkdir -p config/includes.chroot/etc/skel

cat << 'EOF' > config/hooks/normal/0100-install-packages.hook.chroot
#!/bin/bash
apt-get update
apt-get install -y lightdm xfce4 xfce4-whiskermenu-plugin picom desktop-base
EOF

chmod +x config/hooks/normal/0100-install-packages.hook.chroot
