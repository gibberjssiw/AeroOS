#!/bin/bash
set -e

cat << 'EOF' > config/hooks/normal/0200-setup-plymouth.hook.chroot
#!/bin/bash
apt-get install -y plymouth plymouth-themes
plymouth-set-default-theme spinner || true
EOF

chmod +x config/hooks/normal/0200-setup-plymouth.hook.chroot
