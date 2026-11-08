# vibeshine-fedora

Unofficial Fedora RPMs for [Vibeshine](https://github.com/Nonary/vibeshine), the
Sunshine fork. Upstream's Linux beta ships only for Arch and CachyOS, but its
source tree carries an RPM spec (`packaging/linux/copr/Sunshine.spec`). This
repository builds that spec unchanged for each upstream **stable** release, in a
Fedora container, and publishes:

- **GitHub Releases:** binary RPM, source RPM, `SHA256SUMS`, and build
  provenance attestations.
- **GitHub Pages:** a signed dnf repository with the newest three releases.

Nothing here is endorsed by or affiliated with the Vibeshine project.

## Install

```sh
sudo dnf config-manager addrepo --from-repofile=https://prom3theu5.github.io/vibeshine-fedora/vibeshine-fedora.repo
sudo dnf install vibeshine
```

The package installs its virtual-display and DualSense kernel modules as DKMS
sources, so `dkms` and `kernel-devel` for the running kernel must be installed.
They build on your machine, against every kernel you install.

Upstream supports only KDE Plasma 6 on Wayland, started by SDDM or Plasma Login
Manager. Run one streaming host at a time: stop and disable Sunshine first.

## How it builds

Two images:

- **`toolchain/Containerfile`** → `ghcr.io/prom3theu5/vibeshine-fedora-toolchain:f44`.
  RPM tooling, npm, CUDA 12.9 at `/opt/cuda` with upstream's glibc header patch,
  GCC 14 as CUDA's host compiler, and upstream's build dependencies. CUDA 12.9
  is the newest release that still builds for Pascal and accepts GCC 14 at most.
  Fedora 44's GCC 14 exists only in Koji, so those RPMs are pinned by checksum,
  as is the CUDA installer. `toolchain.yaml` rebuilds it when it changes and weekly.
- **`Containerfile`** builds one release on that image:
  1. **source:** clones the upstream tag with its Linux submodules and packs the
     spec's `Source0` tarball. Windows-only and Flatpak-only submodules are skipped.
  2. **builder:** `scripts/prepare-spec.sh` fills the spec's version, commit and
     release placeholders, as upstream's COPR pipeline does, and points it at
     `/opt/cuda`. Then `dnf builddep` and `rpmbuild -ba`.
  3. **export:** the RPMs and `SHA256SUMS`, written to `dist/`.

The kernel modules are not compiled in CI. Only their source is packaged.

## Local use

```sh
task toolchain                   # optional: build the toolchain image locally
task build                       # latest upstream stable tag
task build VIBESHINE_REF=2.0.6   # a specific tag
task repo                        # unsigned dnf repo in repo/ for testing
```

## Releasing

`.github/workflows/release.yaml` runs daily. When upstream has a stable tag with
no matching release here, it builds, signs, releases and regenerates the dnf
repository. Run it manually to build a specific tag, to rebuild with a higher
`package_release`, or to regenerate only the repository.

Release tags are `<upstream version>-<package release>`, for example `2.0.6-1`.

### One-time setup

1. `task signing-key` generates an RSA 4096 signing key, stores it as the
   `RPM_SIGNING_KEY` secret, and writes a backup copy. Move the backup into a
   password manager and delete the file.
2. In the repository settings, set **Pages → Source** to **GitHub Actions**.
3. After the first toolchain run, set the `vibeshine-fedora-toolchain` package's
   visibility to public so local builds can pull it without logging in.

## License

The packaged software is Vibeshine, GPL-3.0-only. Each release includes the
source RPM it was built from.
