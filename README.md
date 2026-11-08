# vibeshine-fedora

Unofficial Fedora RPMs for two Moonlight streaming hosts by Nonary, both forks
of Sunshine:

- **[Vibeshine](https://github.com/Nonary/vibeshine)**, based on Sunshine.
- **[Vibepollo](https://github.com/Nonary/Vibepollo)**, based on Apollo, with
  Vibeshine's features.

Upstream's Linux beta ships only for Arch and CachyOS, but both source trees
carry an RPM spec (`packaging/linux/copr/Sunshine.spec`). This repository builds
that spec for each upstream **stable** release, in a Fedora container, and
publishes:

- **GitHub Releases:** binary RPM, source RPM, `SHA256SUMS` and build provenance
  attestations, tagged `<project>-<version>-<release>` (for example
  `vibeshine-2.0.6-1`).
- **GitHub Pages:** signed dnf repository metadata indexing the newest three
  releases of each project. The packages themselves download from GitHub
  Releases (each is ~150 MB, more than Pages should host).

Nothing here is endorsed by or affiliated with either upstream project.

## Install

Install **one** of the two. They share files, services and ports, and each
package conflicts with the other.

```sh
sudo dnf config-manager addrepo --from-repofile=https://prom3theu5.github.io/vibeshine-fedora/vibeshine-fedora.repo
sudo dnf install vibeshine   # or: sudo dnf install vibepollo
```

Switch between them with `sudo dnf swap vibeshine vibepollo`.

The packages install their virtual-display and DualSense kernel modules as DKMS
sources, so `dkms` and `kernel-devel` for the running kernel must be installed.
They build on your machine, against every kernel you install.

Upstream supports only KDE Plasma 6 on Wayland, started by SDDM or Plasma Login
Manager. Run one streaming host at a time: stop and disable Sunshine first.

## How it builds

Two images:

- **`toolchain/Containerfile`** → `ghcr.io/prom3theu5/vibeshine-fedora-toolchain:f44`.
  RPM tooling, npm, CUDA 12.9 at `/opt/cuda` with upstream's glibc header patch,
  GCC 14 as CUDA's host compiler, and the build dependencies of both projects.
  CUDA 12.9 is the newest release that still builds for Pascal, and it accepts
  GCC 14 at most. Fedora 44's GCC 14 exists only in Koji, so those RPMs are
  pinned by checksum, as is the CUDA installer. `toolchain.yaml` rebuilds the
  image when it changes, and weekly.
- **`Containerfile`** builds one project release on that image:
  1. **source:** clones the upstream tag with its Linux submodules and packs the
     spec's `Source0` tarball. Windows-only and Flatpak-only submodules are
     skipped, as are the FFmpeg sources: the build downloads FFmpeg prebuilt.
  2. **builder:** `scripts/prepare-spec.sh` fills the spec's version, commit and
     release placeholders, as upstream's COPR pipeline does, points it at
     `/opt/cuda`, and applies the project's fixes. Then `dnf builddep` and
     `rpmbuild -ba`.
  3. **export:** the RPMs and `SHA256SUMS`, written to `dist/`.

The kernel modules are not compiled in CI. Only their source is packaged.

### Spec fixes

Upstream's RPM spec lags behind its CMake install and its Arch package. Each
project directory in [`projects/`](projects/README.md) lists what we add:
missing build dependencies, files missing from `%files`, a `Conflicts:` with
the other project, and macros that keep the bundled NVIDIA TrueHDR libraries
private. The build also accepts the RPATH that NVIDIA's prebuilt
`libNVCVImage.so` ships with.

## Local use

```sh
task toolchain                            # optional: build the toolchain image locally
task build                                # Vibeshine, latest upstream stable tag
task build PROJECT=vibepollo              # Vibepollo
task build PROJECT=vibeshine REF=2.0.6    # a specific tag
task repo                                 # unsigned dnf repo in repo/ for testing
```

## Releasing

`.github/workflows/release.yaml` runs daily. For each project whose latest
upstream stable tag has no matching release here, it builds, signs and
releases it, then regenerates the dnf repository. Days without a new upstream
release only run the check. Run it manually to build one project, a specific
tag, a rebuild with a higher `package_release`, or to regenerate only the
repository.

### One-time setup

1. `task signing-key` generates an RSA 4096 signing key, stores it as the
   `RPM_SIGNING_KEY` secret, and writes a backup copy. Move the backup into a
   password manager and delete the file.
2. In the repository settings, set **Pages → Source** to **GitHub Actions**.
3. After the first toolchain run, set the `vibeshine-fedora-toolchain` package's
   visibility to public so local builds can pull it without logging in.

## License

The packaged software is GPL-3.0-only. Each release includes the source RPM it
was built from. The TrueHDR runtime bundled by upstream contains NVIDIA
libraries under NVIDIA's own license terms, included in the package under
`/usr/lib64/vibeshine/truehdr/licenses/`.
