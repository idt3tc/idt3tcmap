#!/usr/bin/env bash
# Fetches the latest upstream netradiant-custom revision and rebases the
# current branch (this fork's commits) on top of it.
#
# Upstream is fetched into refs/remotes/upstream/<branch>, independent of
# the configured remotes. Set UPSTREAM_URL / UPSTREAM_BRANCH to override
# the defaults below.
#
# Files below .legacy/ were moved there unchanged, so git applies upstream
# changes to them in their new place. merge.directoryRenames=true moves
# files upstream adds to directories which were moved as a whole (e.g.
# radiant/) below .legacy/ as well, instead of stopping with a conflict.
#
# Usage: ./rebase-upstream.sh
set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/Garux/netradiant-custom.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-master}"
upstream_ref="refs/remotes/upstream/${UPSTREAM_BRANCH}"

error() {
    echo "error: $*" >&2
    exit 1
}

cd "$(dirname "$0")"

branch="$(git symbolic-ref --quiet --short HEAD)" || error "not on a branch"
if ! git diff --quiet || ! git diff --cached --quiet; then
    error "uncommitted changes, commit or stash them first"
fi
if [[ -d "$(git rev-parse --git-path rebase-merge)" || -d "$(git rev-parse --git-path rebase-apply)" ]]; then
    error "a rebase is in progress already"
fi

echo "Fetching ${UPSTREAM_BRANCH} from ${UPSTREAM_URL}"
# --no-prune: with fetch.prune set, git would otherwise delete the very ref
# this fetch is supposed to update, as it doesn't belong to a remote
git fetch --no-tags --no-prune "${UPSTREAM_URL}" "+${UPSTREAM_BRANCH}:${upstream_ref}"

old_head="$(git rev-parse HEAD)"
old_base="$(git merge-base HEAD "${upstream_ref}")"
new_base="$(git rev-parse "${upstream_ref}")"

if [[ "${old_base}" == "${new_base}" ]]; then
    echo "${branch} is up to date with upstream ${UPSTREAM_BRANCH} ($(git rev-parse --short "${new_base}"))"
    exit 0
fi

echo
echo "New upstream commits ($(git rev-list --count "${old_base}..${new_base}")):"
git --no-pager log --oneline "${old_base}..${new_base}"
echo
echo "Rebasing ${branch} ($(git rev-list --count "${old_base}..HEAD") commits) onto $(git rev-parse --short "${new_base}")"
echo "(previous ${branch}: ${old_head})"

if ! git -c merge.directoryRenames=true rebase "${upstream_ref}"; then
    cat >&2 <<EOF

The rebase stopped because of conflicts. Resolve them, then continue with

    git add <files> && git -c merge.directoryRenames=true rebase --continue

or go back to where you started with

    git rebase --abort
EOF
    exit 1
fi

# Files upstream added which did not end up below .legacy/, i.e. sit in
# directories that are kept (partially), like libs/ or include/. If
# q3map2 doesn't need them, they should be moved to .legacy/ as well.
added="$(git diff --name-only --diff-filter=A "${old_base}" "${new_base}")"
kept=()
while IFS= read -r f; do
    if [[ -n "${f}" ]] && git cat-file -e "HEAD:${f}" 2> /dev/null; then
        kept+=("${f}")
    fi
done <<< "${added}"
if [[ ${#kept[@]} -gt 0 ]]; then
    echo
    echo "Files added upstream outside .legacy/; move those q3map2 doesn't need with 'git mv <file> .legacy/<file>':"
    printf '  %s\n' "${kept[@]}"
fi

echo
echo "Done. ${branch} was rewritten, publish it with 'git push --force-with-lease'."
