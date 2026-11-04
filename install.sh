#!/usr/bin/env bash
# Upgrade every installed PHP version to the patched packages of the latest release.
# For each version: back up the installed packages, download and verify the archive,
# upgrade only the packages already installed, restart the services and check the result.
#
# Usage: install.sh                       upgrade every installed version not yet patched
#        install.sh --rollback [X.Y ...]  reinstall the backed-up packages (default: every backup)
set -euo pipefail

RELEASE_URL="${RELEASE_URL:-https://github.com/nanoarmando/php-focal-backports/releases/latest/download}"
WORK_DIR="${WORK_DIR:-$HOME/php-focal-backports}"
SUPPORTED="5.6 7.3 7.4 8.0 8.1"

fail() { echo "ERROR: $*" >&2; exit 1; }

package_list() {
  { dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' "php$1*" "libapache2-mod-php$1" "libphp$1-embed" 2>/dev/null || true; } \
    | awk '$1 == "ii" {print $2, $3}'
}
installed_packages() { package_list "$1" | awk '{print $1}'; }
not_backported() { package_list "$1" | awk '$2 !~ /\+backport[0-9]+$/'; }
backported() { package_list "$1" | awk '$2 ~ /\+backport[0-9]+$/'; }

restart_services() {
  echo "=== Restarting services"
  for v in "$@"; do
    if systemctl is-active --quiet "php$v-fpm"; then systemctl restart "php$v-fpm" && echo "restarted php$v-fpm"; fi
  done
  if systemctl is-active --quiet apache2; then systemctl restart apache2 && echo "restarted apache2"; fi
}

rollback() {
  local versions=("$@")
  if [ ${#versions[@]} -eq 0 ]; then
    for v in $SUPPORTED; do
      if [ -d "$WORK_DIR/rollback/php$v" ]; then versions+=("$v"); fi
    done
  fi
  [ ${#versions[@]} -gt 0 ] || fail "no backups found in $WORK_DIR/rollback"

  for v in "${versions[@]}"; do
    local debs=("$WORK_DIR/rollback/php$v"/*.deb)
    [ -e "${debs[0]}" ] || fail "no backup for PHP $v in $WORK_DIR/rollback/php$v"
    echo "=== Rolling back PHP $v (${#debs[@]} packages, local configuration files are kept)"
    DEBIAN_FRONTEND=noninteractive UCF_FORCE_CONFFOLD=1 \
      dpkg -i --force-confdef --force-confold "${debs[@]}"
  done

  restart_services "${versions[@]}"

  echo "=== Result"
  local status=0
  for v in "${versions[@]}"; do
    local left
    left=$(backported "$v")
    if [ -n "$left" ]; then
      echo "PHP $v: still patched:"; echo "$left"; status=1
    else
      echo "PHP $v: rolled back to $(dpkg-query -W -f='${Version}' "php$v-common")"
    fi
  done
  exit $status
}

[ "$(id -u)" -eq 0 ] || fail "run as root with sudo"
. /etc/os-release
[ "$VERSION_ID" = "20.04" ] || fail "Ubuntu 20.04 required, found $PRETTY_NAME"
[ "$(dpkg --print-architecture)" = amd64 ] || fail "amd64 required"

if [ "${1:-}" = "--rollback" ]; then
  shift
  rollback "$@"
fi
[ $# -eq 0 ] || fail "unknown arguments: $* (usage: install.sh [--rollback [X.Y ...]])"

versions=()
for v in $SUPPORTED; do
  if [ -n "$(not_backported "$v")" ]; then versions+=("$v"); fi
done
[ ${#versions[@]} -gt 0 ] || { echo "Nothing to upgrade: every installed PHP version is already patched."; exit 0; }
echo "PHP versions to upgrade: ${versions[*]}"

command -v dpkg-repack > /dev/null || apt-get install -y --no-install-recommends dpkg-repack
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
curl -fsSLO "$RELEASE_URL/SHA256SUMS"

for v in "${versions[@]}"; do
  echo "=== PHP $v"
  packages=$(installed_packages "$v")

  echo "--- Backing up to $WORK_DIR/rollback/php$v"
  rm -rf "rollback/php$v" && mkdir -p "rollback/php$v"
  (cd "rollback/php$v" && dpkg-repack $packages > /dev/null)
  for p in $packages; do
    ls "rollback/php$v/${p}"_*.deb > /dev/null 2>&1 \
      || fail "the backup of $p could not be created; nothing was changed for PHP $v"
  done
  tar -czf "rollback/php$v-etc.tar.gz" -C / "etc/php/$v" 2> /dev/null || true

  echo "--- Downloading and verifying php$v-focal-amd64.tar.gz"
  curl -fsSLO "$RELEASE_URL/php$v-focal-amd64.tar.gz"
  grep " php$v-focal-amd64.tar.gz\$" SHA256SUMS | sha256sum --check --quiet
  rm -rf "php$v" && mkdir "php$v" && tar -xzf "php$v-focal-amd64.tar.gz" -C "php$v"

  debs=()
  for p in $packages; do
    deb=$(ls "php$v/${p}"_*.deb 2> /dev/null | head -1) || true
    [ -n "$deb" ] || fail "$p is installed but not included in the release; nothing was changed for PHP $v"
    debs+=("./$deb")
  done

  echo "--- Installing ${#debs[@]} packages (local configuration files are kept)"
  DEBIAN_FRONTEND=noninteractive UCF_FORCE_CONFFOLD=1 apt-get install -y --no-install-recommends --no-remove \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "${debs[@]}"
done

restart_services "${versions[@]}"

echo "=== Result"
status=0
for v in "${versions[@]}"; do
  left=$(not_backported "$v")
  if [ -n "$left" ]; then
    echo "PHP $v: NOT patched:"; echo "$left"; status=1
  else
    echo "PHP $v: OK, $("php$v" -r 'echo PHP_VERSION;') ($(dpkg-query -W -f='${Version}' "php$v-common"))"
  fi
done

echo
echo "To roll back: sudo bash install.sh --rollback [X.Y ...]"
exit $status
