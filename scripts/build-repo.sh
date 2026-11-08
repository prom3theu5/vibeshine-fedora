#!/usr/bin/env bash
# Assembles the GitHub Pages site: a signed dnf repository holding the binary
# RPMs from the newest $REPO_KEEP releases, the public signing key, and a
# .repo file for clients. Source RPMs stay on GitHub Releases only.
# Usage: build-repo.sh <site-dir>
set -euo pipefail

site=$1
keep=${REPO_KEEP:-3}
fedora=${FEDORA_VERSION:-44}
repo=${GITHUB_REPOSITORY:?}
[[ -n "${RPM_SIGNING_KEY:-}" ]] || { echo "RPM_SIGNING_KEY is not set" >&2; exit 1; }

owner=${repo%%/*} name=${repo#*/}
base_url="https://${owner,,}.github.io/${name}"
packages="$site/fedora/$fedora/x86_64"
rm -rf "$site" && mkdir -p "$packages"

mapfile -t tags < <(gh release list --repo "$repo" --exclude-drafts --exclude-pre-releases \
  --limit "$keep" --json tagName --jq '.[].tagName')
(( ${#tags[@]} > 0 )) || { echo "no releases to publish" >&2; exit 1; }
for tag in "${tags[@]}"; do
  gh release download "$tag" --repo "$repo" --dir "$packages" --pattern '*.x86_64.rpm'
done

createrepo_c "$packages"

export GNUPGHOME
GNUPGHOME=$(mktemp -d)
trap 'rm -rf "$GNUPGHOME"' EXIT
printf '%s\n' "$RPM_SIGNING_KEY" | gpg --batch --quiet --import
fingerprint=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')
gpg --batch --yes --local-user "$fingerprint" --detach-sign --armor "$packages/repodata/repomd.xml"
gpg --batch --armor --export "$fingerprint" > "$site/RPM-GPG-KEY-vibeshine-fedora"

cat > "$site/vibeshine-fedora.repo" <<REPO
[vibeshine-fedora]
name=Vibeshine for Fedora \$releasever
baseurl=${base_url}/fedora/\$releasever/\$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=${base_url}/RPM-GPG-KEY-vibeshine-fedora
REPO

cat > "$site/index.html" <<HTML
<!doctype html><meta charset="utf-8"><title>Vibeshine for Fedora</title>
<p>dnf repository for <a href="https://github.com/${repo}">${repo}</a>.</p>
<pre>sudo dnf config-manager addrepo --from-repofile=${base_url}/vibeshine-fedora.repo
sudo dnf install vibeshine</pre>
HTML
touch "$site/.nojekyll"
ls -lR "$site"
