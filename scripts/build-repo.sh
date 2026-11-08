#!/usr/bin/env bash
# Assembles the GitHub Pages site: signed dnf repository metadata for the
# binary RPMs of the newest $REPO_KEEP releases of each project in projects/,
# the public signing key, and a .repo file for clients.
#
# The RPMs themselves stay on GitHub Releases (each is ~150 MB, and Pages sites
# are capped at 1 GB). Packages are laid out as <tag>/<file>.rpm and indexed
# with --baseurl pointing at the releases download URL, so each package's
# location resolves to .../releases/download/<tag>/<file>.rpm. dnf follows
# GitHub's redirect from there. Release tags are <project>-<version>-<release>.
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
work=$(mktemp -d)

# Newest first, by publication date.
mapfile -t all_tags < <(gh release list --repo "$repo" --exclude-drafts --exclude-pre-releases \
  --limit 200 --json tagName --jq '.[].tagName')
found=0
for dir in projects/*/; do
  project=$(basename "$dir")
  count=0
  for tag in "${all_tags[@]}"; do
    [[ $tag =~ ^${project}-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ ]] || continue
    gh release download "$tag" --repo "$repo" --dir "$work/$tag" --pattern '*.x86_64.rpm'
    found=1
    (( ++count < keep )) || break
  done
  echo "$project: $count release(s)"
done
(( found )) || { echo "no releases to publish" >&2; exit 1; }

createrepo_c --baseurl "https://github.com/${repo}/releases/download/" "$work"
mv "$work/repodata" "$packages/repodata"
rm -rf "$work"

export GNUPGHOME
GNUPGHOME=$(mktemp -d)
trap 'rm -rf "$GNUPGHOME"' EXIT
printf '%s\n' "$RPM_SIGNING_KEY" | gpg --batch --quiet --import
fingerprint=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')
gpg --batch --yes --local-user "$fingerprint" --detach-sign --armor "$packages/repodata/repomd.xml"
gpg --batch --armor --export "$fingerprint" > "$site/RPM-GPG-KEY-vibeshine-fedora"

cat > "$site/vibeshine-fedora.repo" <<REPO
[vibeshine-fedora]
name=Vibeshine and Vibepollo for Fedora \$releasever
baseurl=${base_url}/fedora/\$releasever/\$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=${base_url}/RPM-GPG-KEY-vibeshine-fedora
# Releases are rare but fixes should arrive promptly; dnf's default can keep
# stale metadata for days.
metadata_expire=6h
REPO

cat > "$site/index.html" <<HTML
<!doctype html><meta charset="utf-8"><title>Vibeshine and Vibepollo for Fedora</title>
<p>dnf repository for <a href="https://github.com/${repo}">${repo}</a>. Install one of the two.</p>
<pre>sudo dnf config-manager addrepo --from-repofile=${base_url}/vibeshine-fedora.repo
sudo dnf install vibeshine   # or: sudo dnf install vibepollo</pre>
HTML
touch "$site/.nojekyll"
ls -lR "$site"
