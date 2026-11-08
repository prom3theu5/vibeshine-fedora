# syntax=docker/dockerfile:1
# Builds RPMs for Fedora for one project in projects/ (Vibeshine or Vibepollo)
# from a pinned upstream tag, using upstream's own RPM spec
# (packaging/linux/copr/Sunshine.spec) on the prebuilt toolchain image from
# toolchain/Containerfile. Export the packages with:
#   docker buildx build -f Containerfile --build-arg PROJECT=vibeshine \
#     --build-arg UPSTREAM=Nonary/vibeshine --build-arg REF=2.0.6 --output type=local,dest=dist .

ARG FEDORA_VERSION=44
ARG TOOLCHAIN_IMAGE=ghcr.io/prom3theu5/vibeshine-fedora-toolchain:f${FEDORA_VERSION}

# --- Upstream source at an exact tag, with the submodules a Linux build needs.
FROM docker.io/library/fedora:${FEDORA_VERSION} AS source
ARG UPSTREAM
ARG REF
RUN dnf -y install --setopt=install_weak_deps=False git-core tar gzip && dnf clean all
RUN test -n "${UPSTREAM}" && test -n "${REF}" || { echo "UPSTREAM and REF are required" >&2; exit 1; }
WORKDIR /src
# Windows-only and Flatpak-only submodules are skipped: they are large and the
# Linux CMake paths never reference them. From build-deps the Linux build uses
# only Vulkan-Headers; FFmpeg itself comes as a pinned prebuilt download, so
# the ~1.4 GB of FFmpeg, x264, x265 and AMF sources beside it are skipped too.
RUN git clone --depth 1 --branch "${REF}" "https://github.com/${UPSTREAM}.git" upstream \
 && cd upstream \
 && git -c submodule.third-party/depot_tools.update=none \
        -c submodule.third-party/libwebrtc.update=none \
        -c submodule.packaging/linux/flatpak/deps/flatpak-builder-tools.update=none \
        -c submodule.packaging/linux/flatpak/deps/shared-modules.update=none \
        submodule update --init --depth 1 --jobs 8 \
 && git submodule foreach --quiet \
        'if [ "$sm_path" != third-party/build-deps ]; then git submodule update --init --recursive --depth 1 --jobs 8; fi' \
 && git -C third-party/build-deps submodule update --init --depth 1 third-party/FFmpeg/Vulkan-Headers \
 && git rev-parse HEAD > /src/commit
# The spec unpacks Source0 into its own directory, so the tarball holds the tree
# contents rather than a top-level folder. Git metadata is not needed: the
# version, branch and commit are passed in the environment.
RUN tar --exclude-vcs -czf /src/tarball.tar.gz -C /src/upstream .

# --- RPM build on the toolchain image.
FROM ${TOOLCHAIN_IMAGE} AS builder
ARG PROJECT
ARG REF
ARG PACKAGE_RELEASE=1
COPY scripts/prepare-spec.sh /usr/local/bin/prepare-spec
COPY projects/${PROJECT}/ /tmp/project/
COPY --from=source /src/upstream/packaging/linux/copr/Sunshine.spec /tmp/upstream.spec
COPY --from=source /src/commit /tmp/commit
RUN mkdir -p /root/rpmbuild/SPECS /root/rpmbuild/SOURCES \
 && prepare-spec /tmp/upstream.spec /root/rpmbuild/SPECS/package.spec \
        "${REF}" "$(cat /tmp/commit)" "${PACKAGE_RELEASE}" /tmp/project \
 && dnf -y builddep /root/rpmbuild/SPECS/package.spec \
 && dnf clean all
COPY --from=source /src/tarball.tar.gz /root/rpmbuild/SOURCES/tarball.tar.gz
# NVIDIA's prebuilt TrueHDR library (truehdr/nvvfx/libs/libNVCVImage.so) ships
# with its build machine's CUDA path as an RPATH. It cannot be rebuilt, so the
# rpath check accepts invalid (0x0002) and empty (0x0010) RPATHs.
RUN QA_RPATHS=$(( 0x0002 | 0x0010 )) rpmbuild -ba /root/rpmbuild/SPECS/package.spec \
 && mkdir -p /out \
 && cp /root/rpmbuild/RPMS/*/*.rpm /root/rpmbuild/SRPMS/*.src.rpm /out/ \
 && cd /out && sha256sum *.rpm > SHA256SUMS

FROM scratch AS export
COPY --from=builder /out/ /
