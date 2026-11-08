#!/usr/bin/env bash
# Signs every RPM in a directory with the armored private key in
# $RPM_SIGNING_KEY, then rewrites SHA256SUMS for the signed files.
# Usage: sign-rpms.sh <dir>
set -euo pipefail

dir=$1
[[ -n "${RPM_SIGNING_KEY:-}" ]] || { echo "RPM_SIGNING_KEY is not set" >&2; exit 1; }

export GNUPGHOME
GNUPGHOME=$(mktemp -d)
trap 'rm -rf "$GNUPGHOME"' EXIT
printf '%s\n' "$RPM_SIGNING_KEY" | gpg --batch --quiet --import
fingerprint=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')
[[ -n $fingerprint ]] || { echo "no secret key imported" >&2; exit 1; }

rpmsign --define "_gpg_name ${fingerprint}" --addsign "$dir"/*.rpm

# Verify against the public half only, as a client would.
gpg --batch --armor --export "$fingerprint" > "$GNUPGHOME/public.asc"
rpmkeys --root "$GNUPGHOME/root" --initdb 2>/dev/null || mkdir -p "$GNUPGHOME/root"
rpmkeys --root "$GNUPGHOME/root" --import "$GNUPGHOME/public.asc"
for rpm in "$dir"/*.rpm; do
  rpmkeys --root "$GNUPGHOME/root" --checksig "$rpm" | grep -q 'signatures OK' \
    || { echo "signature check failed: $rpm" >&2; exit 1; }
done

(cd "$dir" && sha256sum ./*.rpm | sed 's| \./| |' > SHA256SUMS)
echo "Signed with ${fingerprint}"
