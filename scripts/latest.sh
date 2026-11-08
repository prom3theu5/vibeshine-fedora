#!/usr/bin/env bash
# Prints upstream Vibeshine's latest stable release tag (pre-releases and
# nightlies are excluded by GitHub's releases/latest endpoint).
set -euo pipefail

headers=()
if [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
    headers=(-H "Authorization: Bearer ${GH_TOKEN:-${GITHUB_TOKEN:-}}")
fi
tag=$(curl --connect-timeout 10 --max-time 30 -fsSL "${headers[@]}" \
    https://api.github.com/repos/Nonary/vibeshine/releases/latest \
    | jq -er '.tag_name | select(type == "string" and test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$"))')
printf '%s' "$tag"
