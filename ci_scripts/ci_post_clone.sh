#!/bin/zsh -e
# Xcode Cloud CI post-clone: pull sibling Swift packages that the Xcode
# project references via XCLocalSwiftPackageReference (relativePath ../).
#
# Xcode Cloud only checks out the primary repo (CI_PRIMARY_REPOSITORY_PATH);
# any local-path SwiftPM dependencies must be cloned manually here, before
# xcodebuild starts package resolution. CI_WORKSPACE is the parent dir
# (/Volumes/workspace), so siblings of $CI_PRIMARY_REPOSITORY_PATH land
# at $CI_WORKSPACE/<name>.
#
# Failure mode this fixes (build #216-#221, 2026-04-22/23):
#   xcodebuild: error: Could not resolve package dependencies:
#     the package at '/Volumes/workspace/KatafractStyle' cannot be accessed
#
# All clones below are public repos — no deploy key / token needed.

cd "$CI_WORKSPACE"

clone_pkg() {
  local repo="$1" branch="${2:-main}"
  local name="${repo##*/}"
  if [ -d "$name" ]; then
    echo "ci_post_clone: $name already present, pulling latest"
    git -C "$name" fetch --depth 1 origin "$branch" && git -C "$name" reset --hard "origin/$branch"
  else
    echo "ci_post_clone: cloning $repo ($branch)"
    git clone --depth 1 --branch "$branch" "https://github.com/${repo}.git" "$name"
  fi
}

clone_pkg "katafract-io/KatafractStyle"

echo "ci_post_clone: workspace siblings:"
ls -la "$CI_WORKSPACE"
