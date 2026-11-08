# syntax=docker/dockerfile:1
# Builds Vibeshine RPMs for Fedora from a pinned upstream tag, using upstream's
# own RPM spec (packaging/linux/copr/Sunshine.spec) on the prebuilt toolchain
# image from toolchain/Containerfile. Export the packages with:
#   docker buildx build -f Containerfile --build-arg VIBESHINE_REF=2.0.6 --output type=local,dest=dist .

ARG FEDORA_VERSION=44
ARG TOOLCHAIN_IMAGE=ghcr.io/prom3theu5/vibeshine-fedora-toolchain:f${FEDORA_VERSION}

# --- Upstream source at an exact tag, with the submodules a Linux build needs.
FROM docker.io/library/fedora:${FEDORA_VERSION} AS source
ARG VIBESHINE_REPO=https://github.com/Nonary/vibeshine.git
ARG VIBESHINE_REF
RUN dnf -y install --setopt=install_weak_deps=False git-core tar gzip && dnf clean all
RUN test -n "${VIBESHINE_REF}" || { echo "VIBESHINE_REF is required" >&2; exit 1; }
WORKDIR /src
# Windows-only and Flatpak-only submodules are skipped: they are large and the
# Linux CMake paths never reference them.
RUN git clone --depth 1 --branch "${VIBESHINE_REF}" "${VIBESHINE_REPO}" vibeshine \
 && cd vibeshine \
 && git -c submodule.third-party/depot_tools.update=none \
        -c submodule.third-party/libwebrtc.update=none \
        -c submodule.packaging/linux/flatpak/deps/flatpak-builder-tools.update=none \
        -c submodule.packaging/linux/flatpak/deps/shared-modules.update=none \
        submodule update --init --recursive --depth 1 --jobs 8 \
 && git rev-parse HEAD > /src/commit
# The spec unpacks Source0 into its own directory, so the tarball holds the tree
# contents rather than a top-level folder. Git metadata is not needed: the
# version, branch and commit are passed in the environment.
RUN tar --exclude-vcs -czf /src/tarball.tar.gz -C /src/vibeshine .

# --- RPM build on the toolchain image.
FROM ${TOOLCHAIN_IMAGE} AS builder
ARG VIBESHINE_REF
ARG PACKAGE_RELEASE=1
COPY scripts/prepare-spec.sh /usr/local/bin/prepare-spec
COPY --from=source /src/vibeshine/packaging/linux/copr/Sunshine.spec /tmp/upstream.spec
COPY --from=source /src/commit /tmp/commit
RUN mkdir -p /root/rpmbuild/SPECS /root/rpmbuild/SOURCES \
 && prepare-spec /tmp/upstream.spec /root/rpmbuild/SPECS/vibeshine.spec \
        "${VIBESHINE_REF}" "$(cat /tmp/commit)" "${PACKAGE_RELEASE}" \
 && dnf -y builddep /root/rpmbuild/SPECS/vibeshine.spec \
 && dnf clean all
COPY --from=source /src/tarball.tar.gz /root/rpmbuild/SOURCES/tarball.tar.gz
RUN rpmbuild -ba /root/rpmbuild/SPECS/vibeshine.spec \
 && mkdir -p /out \
 && cp /root/rpmbuild/RPMS/*/*.rpm /root/rpmbuild/SRPMS/*.src.rpm /out/ \
 && cd /out && sha256sum *.rpm > SHA256SUMS

FROM scratch AS export
COPY --from=builder /out/ /
