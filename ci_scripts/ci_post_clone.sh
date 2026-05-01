#!/bin/zsh
# Xcode Cloud CI post-clone: pull sibling Swift packages that the Xcode
# project references via XCLocalSwiftPackageReference (relativePath ../).
#
# Xcode Cloud only checks out the primary repo; XCLocalSwiftPackageReference
# entries with relativePath="../KatafractStyle" must resolve to a sibling
# directory of $CI_PRIMARY_REPOSITORY_PATH. We clone them here, before
# xcodebuild starts package resolution.
#
# Failure mode this fixes (build #216-#221, 2026-04-22/23, and #222 today):
#   xcodebuild: error: Could not resolve package dependencies:
#     the package at '/Volumes/workspace/KatafractStyle' cannot be accessed
#
# All clones below are public repos — no deploy key / token needed.
#
# Note: NOT using `zsh -e` — we want to log diagnostics on failure rather
# than die silently. Final exit status reflects whether all clones succeeded.

set -u

echo "ci_post_clone: starting"
echo "  CI_PRIMARY_REPOSITORY_PATH=${CI_PRIMARY_REPOSITORY_PATH:-<unset>}"
echo "  CI_WORKSPACE=${CI_WORKSPACE:-<unset>}"
echo "  PWD=$(pwd)"

# Workspace = parent dir of the primary repo checkout. Apple's CI_WORKSPACE
# env var has been observed to either be unset or point elsewhere; deriving
# from CI_PRIMARY_REPOSITORY_PATH is the reliable source of truth.
if [ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
  WORKSPACE="$(dirname "$CI_PRIMARY_REPOSITORY_PATH")"
else
  WORKSPACE="${CI_WORKSPACE:-/Volumes/workspace}"
fi
echo "  resolved WORKSPACE=$WORKSPACE"

cd "$WORKSPACE" || { echo "ci_post_clone: cd to WORKSPACE failed"; exit 1; }

rc=0
clone_pkg() {
  local repo="$1" branch="${2:-main}"
  local name="${repo##*/}"
  if [ -d "$name/.git" ]; then
    echo "ci_post_clone: $name already present, fetching latest"
    git -C "$name" fetch --depth 1 origin "$branch" || { echo "  fetch failed"; rc=1; return; }
    git -C "$name" reset --hard "origin/$branch" || { echo "  reset failed"; rc=1; return; }
  else
    [ -d "$name" ] && rm -rf "$name"
    echo "ci_post_clone: cloning $repo (branch $branch)"
    if ! git clone --depth 1 --branch "$branch" "https://github.com/${repo}.git" "$name"; then
      echo "  clone failed"
      rc=1
      return
    fi
  fi
  echo "  ok: $name @ $(git -C "$name" rev-parse --short HEAD 2>/dev/null || echo '?')"
}

clone_pkg "katafract-io/KatafractStyle"

echo "ci_post_clone: workspace contents:"
ls -la "$WORKSPACE"

if [ "$rc" -ne 0 ]; then
  echo "ci_post_clone: completed with errors (rc=$rc)"
  exit "$rc"
fi
echo "ci_post_clone: done"
