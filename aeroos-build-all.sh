#!/bin/bash
set -e

mkdir -p aeroos-build
cd aeroos-build

sudo lb clean --purge || true

lb config \
  --mode ubuntu \
  --distribution noble \
  --architectures amd64 \
  --bootstrap-qemu-static-path /usr/bin/qemu-x86_64-static \
  --archive-areas "main restricted universe multiverse" \
  --debian-installer false \
  --updates false \
  --security false

if [ -f "../aeroos-step1-chroot.sh" ]; then
    bash ../aeroos-step1-chroot.sh
fi

if [ -f "../aeroos-step2-plymouth.sh" ]; then
    bash ../aeroos-step2-plymouth.sh
fi

if [ -f "../aeroos-step3-iso-build.sh" ]; then
    bash ../aeroos-step3-iso-build.sh
else
    sudo lb build
fi
