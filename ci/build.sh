#!/usr/bin/env bash
# Builds and installs the dependencies, then builds the project and runs its
# tests, leaving out those labelled timing.
#
# Usage: build.sh [--test-project <path>]... <project> [dependency...]
#
# Every repository is checked out under src/ of the current directory and
# built under build/; dependencies are built in the order given. A test
# project is a directory of the project with a CMake project of its own,
# built and run after the project. Tests run as an unprivileged user on a
# private session bus.
set -Eeuo pipefail

usage() {
  echo "Usage: $0 [--test-project <path>]... <project> [dependency...]" >&2
  exit 2
}

TEST_PROJECTS=()
while (( $# > 0 )) && [[ "$1" == --* ]]; do
  case "$1" in
    --test-project)
      (( $# >= 2 )) || usage
      TEST_PROJECTS+=("$2")
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done
(( $# >= 1 )) || usage

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

test_dirs=("$ROOT/build/$PROJECT")
for test_project in "${TEST_PROJECTS[@]}"; do
  echo "::group::$PROJECT/$test_project"
  build=$ROOT/build/$PROJECT-tests/$test_project
  cmake -S "$ROOT/src/$PROJECT/$test_project" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    "${launcher_options[@]}"
  cmake --build "$build" --parallel "$JOBS"
  test_dirs+=("$build")
  echo "::endgroup::"
done

if ! id "$TEST_USER" >/dev/null 2>&1; then
  useradd --create-home "$TEST_USER"
fi
uid=$(id -u "$TEST_USER")
runtime_dir=/run/user/$uid
install -d -m 700 -o "$TEST_USER" -g "$TEST_USER" "$runtime_dir"
chown -R "$TEST_USER:" "${test_dirs[@]}"

# The locale a desktop session has; the bare C locale is not what the tests
# expect.
sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen >/dev/null
echo "LANG=en_US.UTF-8" > /etc/default/locale

# A city's time zone, as a desktop has, rather than the container's UTC.
ln -sf /usr/share/zoneinfo/Asia/Singapore /etc/localtime
echo "Asia/Singapore" > /etc/timezone

# The font settings a Cutefish session writes, which the text tests measure
# against.
fontconfig_dir=/home/$TEST_USER/.config/fontconfig/conf.d
install -d -o "$TEST_USER" -g "$TEST_USER" "/home/$TEST_USER/.config" \
  "/home/$TEST_USER/.config/fontconfig" "$fontconfig_dir"
install -m 644 -o "$TEST_USER" -g "$TEST_USER" "$(dirname "$0")/99-cutefish.conf" "$fontconfig_dir"

status=0
for dir in "${test_dirs[@]}"; do
  runuser -u "$TEST_USER" -- env HOME="/home/$TEST_USER" XDG_RUNTIME_DIR="$runtime_dir" LANG=en_US.UTF-8 \
    dbus-run-session -- \
    ctest --test-dir "$dir" --label-exclude timing --output-on-failure --parallel "$JOBS" || status=1
done
exit "$status"
