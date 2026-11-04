#!/usr/bin/env bash
# Upgrade every installed PHP version to the patched packages of the latest release.
# For each version: back up the installed packages, download and verify the archive,
# upgrade only the packages already installed, restart the services and check the result.
set -euo pipefail

RELEASE_URL="${RELEASE_URL:-https://github.com/nanoarmando/php-focal-backports/releases/latest/download}"
WORK_DIR="${WORK_DIR:-$HOME/php-focal-backports}"
SUPPORTED="5.6 7.3 7.4 8.0 8.1"

fail() { echo "ERROR: $*" >&2; exit 1; }

installed_packages() {
  { dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' "php$1*" "libapache2-mod-php$1" "libphp$1-embed" 2>/dev/null || true; } \
    | awk '$1 == "ii" {print $2}'
}

not_backported() {
  { dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' "php$1*" "libapache2-mod-php$1" "libphp$1-embed" 2>/dev/null || true; } \
    | awk '$1 == "ii" && $3 !~ /\+backport[0-9]+$/ {print $2, $3}'
}

[ "$(id -u)" -eq 0 ] || fail "run as root: sudo bash $0"
. /etc/os-release
[ "$VERSION_ID" = "20.04" ] || fail "Ubuntu 20.04 required, found $PRETTY_NAME"
[ "$(dpkg --print-architecture)" = amd64 ] || fail "amd64 required"

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
  mkdir -p "rollback/php$v"
  (cd "rollback/php$v" && dpkg-repack $packages > /dev/null)
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

echo "=== Restarting services"
for v in "${versions[@]}"; do
  if systemctl is-active --quiet "php$v-fpm"; then systemctl restart "php$v-fpm" && echo "restarted php$v-fpm"; fi
done
if systemctl is-active --quiet apache2; then systemctl restart apache2 && echo "restarted apache2"; fi

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
echo "To roll back one version: sudo dpkg -i $WORK_DIR/rollback/php<version>/*.deb, then restart its services."
exit $status
