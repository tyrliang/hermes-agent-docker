#!/usr/bin/env sh
# Cut a semver git tag CI will mirror to GHCR (see README → Publishing).
# Usage: scripts/tag-release.sh 1.2.3    # creates annotated tag v1.2.3
#        scripts/tag-release.sh v4.5.6 # leading v is stripped and re-added

set -eu

semver="${1:?Usage: scripts/tag-release.sh <major.minor.patch>}"

semver="${semver#v}"
TAG="v${semver}"

case "$semver" in
*.*.*) ;;
*)
	printf '%s\n' "Expected at least major.minor.patch (e.g. 1.0.0 or v1.0.0), got: $1" >&2
	exit 1
	;;
esac

if git rev-parse "$TAG" >/dev/null 2>&1; then
	printf '%s\n' "Abort: git tag '$TAG' already exists locally." >&2
	exit 1
fi

git tag -a "$TAG" -m "release $TAG"

printf '%s\n' "Tagged $TAG (annotated)." "Next: git push origin $TAG"
