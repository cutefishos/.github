#!/usr/bin/env bash
# Builds and installs packages that cutefishos/packaging builds from pinned
# upstream release tarballs, such as cutefish-ghostty-vt, with the same
# scripts the package builds use. Tests of those packages are left to the
# package builds.
#
# Usage: build-released.sh <package>...
set -Eeuo pipefail

(( $# >= 1 )) || { echo "Usage: $0 <package>..." >&2; exit 2; }

export DEBIAN_FRONTEND=noninteractive
apt-get install -y -q --no-install-recommends build-essential devscripts equivs minisign xz-utils

git clone --quiet --depth 1 https://github.com/cutefishos/packaging.git packaging
git config --global --add safe.directory "*"

for package in "$@"; do
  # Zig is not packaged in Debian; the package pins the release it builds with.
  if [[ -x "packaging/debian/$package/fetch-zig.sh" ]]; then
    PATH="$("packaging/debian/$package/fetch-zig.sh" /opt):$PATH"
  fi
done

DEB_BUILD_OPTIONS=nocheck packaging/debian/build.sh --install "$@"
