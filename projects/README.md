# Projects

One directory per upstream project built by this repository. Each holds:

- `upstream`: the GitHub `owner/repo` to build from.
- `extra-buildrequires.txt`: build dependencies missing from upstream's spec.
  Also preinstalled in the toolchain image.
- `extra-files.txt`: files CMake installs that are missing from `%files`.
- `extra-globals.txt`: spec macros prepended to the spec.
- `extra-preamble.txt`: preamble tags such as `Conflicts:`, inserted after `Release:`.

`scripts/prepare-spec.sh` applies these to upstream's
`packaging/linux/copr/Sunshine.spec`.
