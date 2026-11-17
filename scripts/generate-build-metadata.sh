#!/bin/sh
set -eu

output="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/BuildMetadata.json"
if [ "${CONFIGURATION:-}" != Debug ]; then
  rm -f "$output"
  exit 0
fi

# Read repository metadata only. No diff contents or credentials are emitted.
commit="$(/usr/bin/git -C "$SRCROOT" rev-parse --verify HEAD 2>/dev/null || true)"
# Xcode grants declared files individually. HEAD's reflog is a stable dependency across
# branches, unlike a loose ref path. Its latest new OID follows commits/checkouts/resets.
if [ -z "$commit" ] && [ -r "$SRCROOT/.git/logs/HEAD" ]; then
  commit="$(/usr/bin/tail -n 1 "$SRCROOT/.git/logs/HEAD" | /usr/bin/awk '{print $2}')"
fi
case "$commit" in
  ''|*[!0-9a-f]*) commit='' ;;
esac
dirty=null
# Sandboxed Git can report inaccessible tracked files as deleted.
# Inspect changes only when script sandboxing is explicitly disabled.
if [ "${ENABLE_USER_SCRIPT_SANDBOXING:-YES}" = "NO" ] && [ -n "$commit" ]; then
  if changes="$(/usr/bin/git -C "$SRCROOT" status --porcelain --untracked-files=normal 2>/dev/null)"; then
    dirty=false
    if [ -n "$changes" ]; then dirty=true; fi
  fi
fi
mkdir -p "$(dirname "$output")"
printf '{"commit":"%s","dirty":%s}\n' "$commit" "$dirty" > "$output"
