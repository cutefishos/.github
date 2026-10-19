#!/usr/bin/env bash
# Builds and installs the dependencies, then builds the project and runs its
# tests, leaving out those labelled timing.
#
# Usage: build.sh <project> [dependency...]
#
# Every repository is checked out under src/ of the current directory and
# built under build/; dependencies are built in the order given. Tests run as
# an unprivileged user on a private session bus.
set -Eeuo pipefail

if (( $# < 1 )); then
  echo "Usage: $0 <project> [dependency...]" >&2
  exit 2
fi

PROJECT=$1
shift
DEPENDENCIES=("$@")
ROOT=$PWD
JOBS=$(nproc)
TEST_USER=cutefish-ci

launcher_options=()
if command -v ccache >/dev/null; then
  launcher_options=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
fi

build_project() {
  local project=$1
  local testing=$2
  local src=$ROOT/src/$project
  local build=$ROOT/build/$project

  echo "::group::$project"

  if [[ -x "$src/scripts/fetch-skia.sh" ]]; then
    "$src/scripts/fetch-skia.sh"
  fi

  cmake -S "$src" -B "$build" -G Ninja \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING="$testing" \
    "${launcher_options[@]}"
  cmake --build "$build" --parallel "$JOBS"
  cmake --install "$build"

  echo "::endgroup::"
}

for dependency in "${DEPENDENCIES[@]}"; do
  build_project "$dependency" OFF
done

build_project "$PROJECT" ON

if ! id "$TEST_USER" >/dev/null 2>&1; then
  useradd --create-home "$TEST_USER"
fi
uid=$(id -u "$TEST_USER")
runtime_dir=/run/user/$uid
install -d -m 700 -o "$TEST_USER" -g "$TEST_USER" "$runtime_dir"
chown -R "$TEST_USER:" "$ROOT/build/$PROJECT"

# The locale a desktop session has; the bare C locale is not what the tests
# expect.
sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen >/dev/null
echo "LANG=en_US.UTF-8" > /etc/default/locale

# The font settings a Cutefish session writes, which the text tests measure
# against.
fontconfig_dir=/home/$TEST_USER/.config/fontconfig/conf.d
install -d -o "$TEST_USER" -g "$TEST_USER" "/home/$TEST_USER/.config" \
  "/home/$TEST_USER/.config/fontconfig" "$fontconfig_dir"
install -m 644 -o "$TEST_USER" -g "$TEST_USER" "$(dirname "$0")/99-cutefish.conf" "$fontconfig_dir"

runuser -u "$TEST_USER" -- env HOME="/home/$TEST_USER" XDG_RUNTIME_DIR="$runtime_dir" LANG=en_US.UTF-8 \
  dbus-run-session -- \
  ctest --test-dir "$ROOT/build/$PROJECT" --label-exclude timing --output-on-failure \
  --parallel "$JOBS"
