#!/usr/bin/env bash
# Prints the latest stable release tag of a GitHub repository (pre-releases and
# nightlies are excluded by GitHub's releases/latest endpoint).
# Usage: latest.sh <owner/repo>
set -euo pipefail

repo=${1:?usage: latest.sh <owner/repo>}
headers=()
if [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
    headers=(-H "Authorization: Bearer ${GH_TOKEN:-${GITHUB_TOKEN:-}}")
fi
tag=$(curl --connect-timeout 10 --max-time 30 -fsSL "${headers[@]}" \
    "https://api.github.com/repos/${repo}/releases/latest" \
    | jq -er '.tag_name | select(type == "string" and test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$"))')
printf '%s' "$tag"
