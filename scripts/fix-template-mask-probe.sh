#!/usr/bin/env bash
# Patches upstream's RPM scriptlets for systemd 259+, which rejects a bare
# template name in `systemctl show` ("neither a valid invocation ID nor unit
# name"). The scriptlets check that <name>-session-restore@.service is masked
# with `systemctl show <template> --property=LoadState`, so on Fedora 44 the
# check always fails and %pre refuses to install.
#
# Upstream fixed this only in the Arch install script (packaging/linux/Arch/
# <name>.install): it probes an instance of the template instead, since an
# instance of a masked template reports LoadState=masked. This applies the same
# fix to the four RPM copies: the inline checks in %pre and %post, and the
# one-line wrappers in %preun and %postun that pass the template to a generic
# helper. `systemctl is-enabled` still checks the template itself.
# Usage: fix-template-mask-probe.sh <spec>
set -euo pipefail

spec=$1
name=$(sed -n 's/^Name:[[:space:]]*//p' "$spec" | head -n1)
[[ $name =~ ^[a-z]+$ ]] || { echo "unexpected spec Name: $name" >&2; exit 1; }
template="${name}-session-restore@.service"
probe="${name}-session-restore@mask-probe.service"

# 1. Inline checks (%pre, %post): `systemctl show \` then the template on the next line.
before=$(grep -cF "'${template}' --property=LoadState" "$spec" || true)
sed -i "s|'${template}' --property=LoadState|'${probe}' --property=LoadState|" "$spec"

# 2. One-line wrappers (%preun, %postun) around <name>_unit_is_masked and
#    <name>_preun_unit_is_masked, which would run `systemctl show` on the template.
replacement="${name}_restore_template_is_masked() { ${name}_restore_state=\$(timeout --signal=KILL 5 systemctl is-enabled '${template}' 2>/dev/null || true); ${name}_restore_load=\$(timeout --signal=KILL 5 systemctl show '${probe}' --property=LoadState 2>/dev/null) || return 1; case \"\$${name}_restore_state\" in masked | masked-runtime) [ \"\$${name}_restore_load\" = 'LoadState=masked' ] ;; *) return 1 ;; esac; }"
# Matched as exact lines (no regex), passed through ENVIRON so awk does not
# reinterpret backslashes.
wrapper_postun="${name}_restore_template_is_masked() { ${name}_unit_is_masked '${template}'; }"
wrapper_preun="${name}_restore_template_is_masked() { ${name}_preun_unit_is_masked '${template}'; }"
wrappers=$(grep -cxF -e "$wrapper_postun" -e "$wrapper_preun" "$spec" || true)
A="$wrapper_postun" B="$wrapper_preun" R="$replacement" \
  awk '$0 == ENVIRON["A"] || $0 == ENVIRON["B"] { print ENVIRON["R"]; next } { print }' "$spec" > "$spec.tmp"
mv "$spec.tmp" "$spec"

# Fail loudly when upstream changes these scriptlets, rather than ship a spec
# that either still fails or was patched in only some places.
after=$(grep -cF "'${template}' --property=LoadState" "$spec" || true)
probes=$(grep -cF "'${probe}' --property=LoadState" "$spec" || true)
if [[ $before -ne 2 || $wrappers -ne 2 || $after -ne 0 || $probes -ne 4 ]]; then
  echo "template mask probe fix: expected 2 inline checks and 2 wrappers, found" \
       "$before and $wrappers (left unpatched: $after, probes now: $probes)" >&2
  exit 1
fi
echo "template mask probe fix: patched 4 checks for ${template}"
