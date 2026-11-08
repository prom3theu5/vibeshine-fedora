#!/usr/bin/env bash
# Turns upstream's RPM spec into the one we build:
# - fills the version, branch and commit placeholders, as upstream's COPR
#   pipeline does, and sets the RPM release;
# - points CUDA at the toolchain image's /opt/cuda;
# - fixes the scriptlets' masked-template check for systemd 259+
#   (fix-template-mask-probe.sh, next to this script);
# - applies the project's fixes from <project-dir>, each optional:
#     extra-globals.txt        prepended to the spec
#     extra-preamble.txt       preamble tags, inserted after Release:
#     extra-buildrequires.txt  one package per line, added as BuildRequires
#     extra-files.txt          appended to %files
# Lines starting with # and blank lines in those files are ignored.
# Usage: prepare-spec.sh <upstream.spec> <output.spec> <version> <commit> <release> <project-dir>
set -euo pipefail

in=$1 out=$2 version=$3 commit=$4 release=$5 project=$6
[[ $commit =~ ^[0-9a-f]{40}$ ]] || { echo "bad commit: $commit" >&2; exit 1; }
[[ $release =~ ^[0-9]+$ ]] || { echo "bad release: $release" >&2; exit 1; }
[[ -d $project ]] || { echo "no project directory: $project" >&2; exit 1; }

# Prints a fix file without comments and blank lines; nothing if it is absent.
entries() { [[ -f "$project/$1" ]] && grep -v -e '^#' -e '^[[:space:]]*$' "$project/$1" || true; }

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

"$(dirname "$0")/fix-template-mask-probe.sh" "$out"

globals=$(entries extra-globals.txt)
if [[ -n $globals ]]; then
  { printf '%s\n' "$globals"; cat "$out"; } > "$out.tmp" && mv "$out.tmp" "$out"
fi

preamble=$(entries extra-preamble.txt)
if [[ -n $preamble ]]; then
  awk -v add="$preamble" '{ print } !done && /^Release:/ { print add; done = 1 }' \
    "$out" > "$out.tmp" && mv "$out.tmp" "$out"
fi

buildrequires=$(entries extra-buildrequires.txt | sed 's/^/BuildRequires: /')
if [[ -n $buildrequires ]]; then
  # After the first BuildRequires, inside the section shared by all distros.
  awk -v add="$buildrequires" '!done && /^BuildRequires:/ { print; print add; done = 1; next } { print }' \
    "$out" > "$out.tmp" && mv "$out.tmp" "$out"
fi

files=$(entries extra-files.txt)
if [[ -n $files ]]; then
  grep -q '^%changelog' "$out" || { echo "spec has no %changelog to insert before" >&2; exit 1; }
  awk -v add="$files" '/^%changelog/ && !done { print add; print ""; done = 1 } { print }' \
    "$out" > "$out.tmp" && mv "$out.tmp" "$out"
fi

while read -r line; do
  [[ -z $line ]] || grep -qxF -- "$line" "$out" || { echo "failed to add: $line" >&2; exit 1; }
done < <(printf '%s\n%s\n%s\n%s\n' "$globals" "$preamble" "$buildrequires" "$files")
