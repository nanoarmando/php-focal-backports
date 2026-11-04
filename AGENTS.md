# AGENTS.md

## Purpose

Rebuild ondrej/php Ubuntu 22.04 (jammy) PHP source packages for Ubuntu 20.04 (focal, amd64) and publish the `.deb` files as a GitHub release. The motivation is CVE-2026-109618 and CVE-2026-109619; the PPA no longer publishes for focal.

## Files

- `build.sh`: builds one source package. Arguments: `<source> <jammy-version-without-epoch> <new-version>`. Downloads the `.dsc` from Launchpad, installs build dependencies with `mk-build-deps`, sets the version with `dch --force-bad-version`, builds with `dpkg-buildpackage -b` and `nocheck`, and copies the `.deb` files to `$OUT_DIR` (default `./out`).
- `test.sh`: tests one version in a clean system. Arguments: `<source> <deb-dir> <release-suffix> [upgrade]`. Installs `cli`, `fpm`, `common` and common extensions, checks that every installed `phpX.Y*` package version ends in `+<release-suffix>`, that the extensions load, that `php-fpm` answers a FastCGI request (`cgi-fcgi`), and that the upstream changelog entry lists the CVE fixes. With `upgrade`, it first installs Ubuntu's own packages and replaces them with the README Quick start commands; keep those commands in sync with the README.
- `install.sh`: one-command upgrade for servers (README Quick start). Detects the installed versions that are not yet `+backportN`, backs them up with `dpkg-repack` to `$WORK_DIR/rollback/` (default `~/php-focal-backports`; the backup of a version is replaced on each upgrade, and the upgrade aborts if any installed package has no `.deb` in it, because `dpkg-repack` only warns when it cannot rebuild a package), downloads and verifies each archive from `$RELEASE_URL`, installs only the packages already installed with `apt-get --no-remove` keeping local configuration (`--force-confold`, `UCF_FORCE_CONFFOLD`), restarts running `phpX.Y-fpm` and `apache2`, and fails if any package was not replaced. `--rollback [X.Y ...]` reinstalls the backups with `dpkg -i --force-confold` (all backed-up versions by default), restarts the services and fails if any `+backportN` package remains. Test it in an `ubuntu:20.04` amd64 container after removing `/etc/dpkg/dpkg.cfg.d/excludes`; otherwise `dpkg-repack` cannot rebuild packages whose documentation the image stripped. Keep `SUPPORTED` in sync with the matrix. Not run in CI.
- `.github/workflows/build.yml`:
  - `build` job: one matrix entry per PHP version, runs `build.sh` inside `ubuntu:20.04`, uploads `out/*.deb` as the `<source>-build` artifact.
  - `test` job: one matrix entry per PHP version (php7.4 with `upgrade`), runs `test.sh` inside `ubuntu:20.04`, and re-uploads the tested packages as the `<source>-focal-amd64` artifact. Only tested versions reach the release.
  - `release` job: runs after `test` unless the run was cancelled, packs each artifact into `<source>-focal-amd64.tar.gz` with a `SHA256SUMS` inside, writes a top-level `SHA256SUMS` (keeping the previous lines of versions not published in this run), and creates or updates the release `$RELEASE_TAG` (assets replaced with `--clobber`).
- `README.md`: public documentation: versions, included packages, download, installation, rollback, limitations.

## Conventions

- The jammy version in the matrix has no epoch, because Launchpad file names omit it. The new version keeps the epoch when the source has one (php8.0 and php7.4 use `1:`).
- New versions use the suffix `+ubuntu20.04.1+backportN`. `RELEASE_TAG` is `focal-backportN` and must match `N`.
- A rebuild that changes the packages (new base version or packaging fix) increments `N` in every matrix entry and in `RELEASE_TAG`, so `dpkg` treats it as an upgrade and the previous release stays available.
- To add a PHP version, add a matrix entry to the `build` and `test` jobs and update the README tables (versions and extra packages). Get the package list from the `Package:` lines of the source's `debian/control`.
- All repository content is in English.

## Do not

- Do not add client names, project names, server hostnames, IP addresses or credentials. The repository is public.
- Do not modify the upstream sources or packaging beyond the version number.
- Do not run the PHP test suite in CI (`nocheck`); it takes hours and is not needed for a rebuild of tested sources.
- Do not build for other Ubuntu releases; they receive patched packages through `apt`.
- Do not pin actions to branches; use released major tags verified as described in the workflow review process.
