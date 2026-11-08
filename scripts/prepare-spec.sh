#!/usr/bin/env bash
# Fills the placeholders in upstream's RPM spec, the same values upstream's
# COPR pipeline substitutes, and points CUDA at the toolchain image's /opt/cuda.
# Usage: prepare-spec.sh <upstream.spec> <output.spec> <version> <commit> <release>
set -euo pipefail

in=$1 out=$2 version=$3 commit=$4 release=$5
[[ $commit =~ ^[0-9a-f]{40}$ ]] || { echo "bad commit: $commit" >&2; exit 1; }
[[ $release =~ ^[0-9]+$ ]] || { echo "bad release: $release" >&2; exit 1; }

sed \
  -e "s|^%global build_version 0$|%global build_version ${version}|" \
  -e "s|^%global branch 0$|%global branch master|" \
  -e "s|^%global commit 0$|%global commit ${commit}|" \
  -e "s|^Release: 1%{?dist}$|Release: ${release}%{?dist}|" \
  -e "s|^%global cuda_dir %{_builddir}/cuda$|%global cuda_dir /opt/cuda|" \
  "$in" > "$out"

# Fail loudly if upstream renames any placeholder, rather than build version 0.
for expected in \
  "%global build_version ${version}" \
  "%global commit ${commit}" \
  "Release: ${release}%{?dist}" \
  "%global cuda_dir /opt/cuda"; do
  grep -qxF "$expected" "$out" || { echo "spec placeholder not found: $expected" >&2; exit 1; }
done
