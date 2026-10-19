#!/usr/bin/env bash
# Installs on Debian 13 what every project needs to build and run its tests,
# plus the packages given as arguments.
set -Eeuo pipefail

packages=(
  ca-certificates git cmake ninja-build pkg-config g++ clang python3 gettext ccache
  libwayland-dev libwayland-bin wayland-protocols
  libegl-dev libgles-dev libgbm-dev libdrm-dev
  libxkbcommon-dev libinput-dev libseat-dev libudev-dev libsystemd-dev libpam0g-dev
  libfontconfig-dev libfreetype-dev libharfbuzz-dev libicu-dev libexpat1-dev
  libpng-dev libjpeg-dev zlib1g-dev libwebp-dev libtiff-dev libheif-dev libjxl-dev
  libpipewire-0.3-dev libspa-0.2-dev
  libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libva-dev
  libxcb1-dev libxcb-composite0-dev libxcb-xfixes0-dev libxcb-shape0-dev libxcb-sync-dev
  libarchive-dev libfuse3-dev libmtp-dev libsmbclient-dev libssh-dev libzip-dev
  libcrypt-dev libxcursor-dev libpcre2-dev gtk-update-icon-cache

  # Tests: a private session bus, a locale, software rendering and the fonts the
  # pixel and text tests compare against.
  libgtest-dev dbus locales libegl-mesa0 libgl1-mesa-dri
  fonts-noto-core fonts-noto-mono fonts-noto-ui-core fonts-noto-extra fonts-noto-cjk fonts-noto-color-emoji
  fonts-dejavu-core fonts-dejavu-mono
)

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q --no-install-recommends "${packages[@]}" "$@"
