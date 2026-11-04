<div align="center">

# php-focal-backports

**Patched PHP packages for Ubuntu 20.04 servers that the ondrej/php PPA no longer covers.**

[![Build](https://github.com/nanoarmando/php-focal-backports/actions/workflows/build.yml/badge.svg)](https://github.com/nanoarmando/php-focal-backports/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/nanoarmando/php-focal-backports?label=release)](https://github.com/nanoarmando/php-focal-backports/releases/latest)
![Ubuntu 20.04](https://img.shields.io/badge/Ubuntu-20.04%20focal-E95420?logo=ubuntu&logoColor=white)
![amd64](https://img.shields.io/badge/arch-amd64-informational)
![PHP](https://img.shields.io/badge/PHP-5.6%20%7C%207.3%20%7C%207.4%20%7C%208.0%20%7C%208.1-777BB4?logo=php&logoColor=white)

</div>

> [!IMPORTANT]
> These packages include the fixes for **CVE-2026-109618** and **CVE-2026-109619**, two critical (CVSS 9.2) unauthenticated remote code execution vulnerabilities in PHP, published on 2026-10-21. See the [PHP advisory](https://www.php.net/archive/2026.php#2026-10-21-5).

## Contents

- [Why this exists](#why-this-exists)
- [Available versions](#available-versions)
- [Quick start](#quick-start)
- [Installation](#installation)
- [Included packages](#included-packages)
- [How the packages are built](#how-the-packages-are-built)
- [Limitations](#limitations)

## Why this exists

The [ondrej/php](https://launchpad.net/~ondrej/+archive/ubuntu/php) PPA applied the fixes to every PHP version it maintains, **but it no longer publishes packages for Ubuntu 20.04**. Servers still on Ubuntu 20.04 with PHP from that PPA have no patched package to install.

This repository takes the patched Ubuntu 22.04 source packages from the PPA and rebuilds them, unchanged, on Ubuntu 20.04. Only the version number changes. Because they are based on the latest sources, the packages also include every security fix the PPA released after it stopped publishing for Ubuntu 20.04.

## Available versions

| PHP | Package version | Based on |
|:---:|---|---|
| **8.1** | `8.1.34-9+ubuntu20.04.1+backport1` | `8.1.34-9` |
| **8.0** | `1:8.0.30-25+ubuntu20.04.1+backport1` | `1:8.0.30-25` |
| **7.4** | `1:7.4.33-31+ubuntu20.04.1+backport1` | `1:7.4.33-31` |
| **7.3** | `7.3.33-35+ubuntu20.04.1+backport1` | `7.3.33-35` |
| **5.6** | `5.6.40-104+ubuntu20.04.1+backport1` | `5.6.40-104` |

"Based on" is the ondrej/php source package for Ubuntu 22.04.

## Quick start

On an Ubuntu 20.04 amd64 server, this command upgrades every installed PHP version included in the release:

```bash
curl -fsSL https://raw.githubusercontent.com/nanoarmando/php-focal-backports/main/install.sh | sudo bash
```

For each version, [install.sh](install.sh) backs up the installed packages with `dpkg-repack` (to `~/php-focal-backports/rollback/`), downloads and verifies the archive, upgrades only the packages already installed while keeping your configuration files, restarts PHP-FPM and Apache when they are running, and checks that every package was replaced. It stops before changing a version if any package cannot be backed up. Running it again does nothing once every version is patched.

To roll back to the backed-up packages (every backed-up version, or only the versions you list):

```bash
curl -fsSL https://raw.githubusercontent.com/nanoarmando/php-focal-backports/main/install.sh | sudo bash -s -- --rollback
curl -fsSL https://raw.githubusercontent.com/nanoarmando/php-focal-backports/main/install.sh | sudo bash -s -- --rollback 7.4
```

The rollback keeps your configuration files and restarts the services. Packages that the upgrade added as new dependencies, such as `pkg-config` for `php7.4-dev`, stay installed.

To do the same by hand for one version (replace `8.1` with your version):

```bash
V=8.1
curl -LO "https://github.com/nanoarmando/php-focal-backports/releases/latest/download/php${V}-focal-amd64.tar.gz"
curl -LO "https://github.com/nanoarmando/php-focal-backports/releases/latest/download/SHA256SUMS"
sha256sum --check --ignore-missing SHA256SUMS

mkdir "php${V}" && tar -xzf "php${V}-focal-amd64.tar.gz" -C "php${V}" && cd "php${V}"
installed=$(dpkg-query -W -f='${Package} ${Status}\n' "php${V}*" "libapache2-mod-php${V}" "libphp${V}-embed" 2>/dev/null | awk '/ installed$/{print $1}')
sudo dpkg -i $(for p in $installed; do ls "${p}"_*.deb; done)

sudo systemctl restart "php${V}-fpm"
dpkg -s "php${V}-common" | grep Version   # must end in +backport1
```

The commands upgrade **only the packages that are already installed**. Read [Installation](#installation) for the details and the rollback steps.

## Installation

### Requirements

| Check | Command | Expected |
|---|---|---|
| Ubuntu release | `lsb_release -ds` | `Ubuntu 20.04.x LTS` |
| Architecture | `uname -m` | `x86_64` |
| PHP origin | `dpkg -l 'php*' \| awk '/^ii/{print $2, $3}'` | versions ending in `+deb.sury.org+1` (ondrej/php), or Ubuntu's own `php7.4` |

### Steps

1. **Back up the current packages**, so you can roll back. The PPA no longer publishes for focal, so `apt` cannot download the installed versions again; rebuild the `.deb` files from the installed packages with `dpkg-repack` instead:

   ```bash
   V=8.1
   sudo apt-get install -y dpkg-repack
   mkdir -p ~/php${V}-rollback && cd ~/php${V}-rollback
   sudo dpkg-repack $(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' "php${V}*" "libapache2-mod-php${V}" "libphp${V}-embed" 2>/dev/null | awk '$1 == "ii" {print $2}')
   sudo tar -czf ~/php${V}-etc-backup.tar.gz /etc/php/${V}
   ```

   To roll back, run `sudo dpkg -i ~/php${V}-rollback/*.deb` and restart the services (step 4).

2. **Download and verify** the archive for your version, as shown in [Quick start](#quick-start).

3. **Install only the packages already present.** Installing every `.deb` in the archive would pull in dependencies you do not need, such as Firebird or SNMP libraries.

4. **Restart the services** that run PHP:

   | Your setup | Command |
   |---|---|
   | PHP-FPM (Apache or Nginx) | `sudo systemctl restart php8.1-fpm` |
   | Apache with `mod_php` | `sudo systemctl restart apache2` |

5. **Verify** that `dpkg -s php8.1-common | grep Version` ends in `+backport1`.

Repeat the steps for every PHP version installed on the server.

> [!TIP]
> Extensions shipped as separate packages, such as `imagick`, `redis`, `memcached` or `xdebug`, keep working after the upgrade. They depend on the PHP API version (for example `phpapi-20210902` for 8.1), which does not change within a minor release.

<details>
<summary><strong>Replacing Ubuntu's own php7.4</strong></summary>

<br>

Ubuntu 20.04 ships its own `php7.4` packages, with versions like `7.4.3-4ubuntu2.x`. The `php7.4` packages from this repository replace them with the same steps:

- The epoch (`1:`) makes `dpkg` treat them as an upgrade.
- Ubuntu's `php-common` (`2:75`) satisfies their `php-common (>= 1:81~)` dependency.

After the upgrade, the server runs PHP 7.4 from these rebuilds and keeps Ubuntu's `php-common` and metapackages such as `php-xml` or `php-mbstring`.

</details>

<details>
<summary><strong>Rolling back</strong></summary>

<br>

Reinstall the packages saved in step 1 and restart PHP:

```bash
sudo dpkg -i /var/cache/apt/archives/php8.1*.deb
sudo systemctl restart php8.1-fpm
```

</details>

## Included packages

Each archive contains the same binary packages that the ondrej/php PPA builds from that source.

**Runtimes and SAPIs**

`phpX.Y` (metapackage) · `phpX.Y-cli` · `phpX.Y-fpm` · `phpX.Y-cgi` · `libapache2-mod-phpX.Y` · `phpX.Y-phpdbg` · `libphpX.Y-embed` · `phpX.Y-litespeed` · `phpX.Y-common` · `phpX.Y-dev`

**Extensions in every version**

`bcmath` · `bz2` · `curl` · `dba` · `enchant` · `gd` · `gmp` · `imap` · `interbase` · `intl` · `ldap` · `mbstring` · `mysql` · `odbc` · `opcache` · `pgsql` · `pspell` · `readline` · `snmp` · `soap` · `sqlite3` · `sybase` · `tidy` · `xml` · `xsl` · `zip`

**Extensions only in some versions**

| Extension | 8.1 | 8.0 | 7.4 | 7.3 | 5.6 |
|---|:---:|:---:|:---:|:---:|:---:|
| `json` | built-in | built-in | ✓ | ✓ | ✓ |
| `xmlrpc` | | | ✓ | ✓ | ✓ |
| `recode` | | | | ✓ | ✓ |
| `mcrypt` | | | | | ✓ |

Extensions maintained as separate source packages (`imagick`, `redis`, `memcached`, `xdebug`, `mongodb`, and others) are **not** included.

## How the packages are built

Everything runs on GitHub Actions ([`build.yml`](.github/workflows/build.yml)), on every push to `main` and on manual dispatch:

1. **Build**: for each PHP version, [`build.sh`](build.sh) runs inside an `ubuntu:20.04` container. It downloads the Ubuntu 22.04 source package from Launchpad, installs the build dependencies from the Ubuntu 20.04 archive, sets the new version with a `+backport1` suffix, and builds the packages with `dpkg-buildpackage` (without the upstream test suite).
2. **Test**: for each PHP version, [`test.sh`](test.sh) installs the CLI, PHP-FPM and common extensions in a clean `ubuntu:20.04` container, checks the package versions and the loaded extensions, sends a FastCGI request to PHP-FPM, and checks that the changelog lists the CVE fixes. For PHP 7.4, it first installs Ubuntu's own packages and replaces them with the [Quick start](#quick-start) commands. Only versions that pass are released.
3. **Release**: packs each version into `phpX.Y-focal-amd64.tar.gz` with a `SHA256SUMS` file inside, writes a top-level `SHA256SUMS`, and publishes everything to the release.

The full build log of every release is public in the [Actions](https://github.com/nanoarmando/php-focal-backports/actions) tab.

## Limitations

> [!WARNING]
> - **Ubuntu 20.04, amd64 only.** A `.deb` links against the libraries of the release it was built on, so these packages do not install on other releases. Ubuntu 22.04 and later receive patched packages through `apt`, from Ubuntu or from the ondrej/php PPA.
> - **Unofficial.** These are third-party rebuilds of upstream sources, without the PPA's signatures. Review the workflow and verify the checksums before installing.
> - **A stopgap.** Ubuntu 20.04 and PHP 8.1 and older no longer receive regular security support. Plan the move to a supported Ubuntu release and PHP version.

## License

The build scripts in this repository are provided as-is, without warranty. PHP is distributed under the PHP License, and the Debian packaging under the terms in each source package's `debian/copyright`.
