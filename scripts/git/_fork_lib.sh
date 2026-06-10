# Sourced by git-sync-fork and git-push-on-fork.
# Provides: fork_remote (var), ensure_fork, default_branch.

fork_remote=$(git config --get fork.remote || echo "${USER}-fork")

# Pick a gh-authenticated host matching origin's host. A bare owner/repo slug
# makes gh default to github.com (HTTP 401 here), so we must pin GH_HOST. The
# GHE alias git.netflix.net is authed under github.netflix.net, so we try the
# origin host, its github.* alias, then any host gh holds a valid token for.
gh_host_for() {
    local origin_host=$1 h
    for h in "$origin_host" "github.${origin_host#git.}"; do
        if gh auth status -h "$h" >/dev/null 2>&1; then echo "$h"; return 0; fi
    done
    while read -r h; do
        [ -n "$h" ] && gh auth status -h "$h" >/dev/null 2>&1 && { echo "$h"; return 0; }
    done < <(gh auth status 2>&1 | grep -oE '[A-Za-z0-9.-]+\.[A-Za-z]+' | sort -u)
    return 1
}

ensure_fork() {
    if git remote get-url "$fork_remote" >/dev/null 2>&1; then
        return 0
    fi
    local origin_url origin_host slug gh_host fork_owner fork_url out
    origin_url=$(git remote get-url origin)
    origin_host=$(echo "$origin_url" | sed -E 's#^[^:]+://([^/]+)/.*#\1#')
    # owner/repo: strip protocol+host, trailing .git, trailing slash
    slug=$(echo "$origin_url" | sed -E 's#^[^:]+://[^/]+/##; s#\.git$##; s#/$##')
    if ! gh_host=$(gh_host_for "$origin_host"); then
        echo "ERROR: no gh-authenticated host matches origin '$origin_host'; run: gh auth login" >&2
        return 1
    fi
    echo "Fork remote '$fork_remote' missing; creating via gh repo fork $slug (host: $gh_host)" >&2
    # Idempotent: a no-op (prints "... already exists") if the fork is already
    # there. We don't parse gh's output — it omits the URL on "already exists" —
    # but instead build the fork URL from the authenticated login on gh_host
    # (the resolved host may differ from origin's, e.g. git.netflix.net →
    # github.netflix.net).
    if ! out=$(GH_HOST="$gh_host" gh repo fork "$slug" --clone=false 2>&1); then
        echo "$out" >&2
        return 1
    fi
    fork_owner=$(GH_HOST="$gh_host" gh api user --jq .login)
    fork_url="https://${gh_host}/${fork_owner}/${slug##*/}"
    git remote add "$fork_remote" "$fork_url"
}

default_branch() {
    if ! git symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null; then
        git remote set-head origin -a >/dev/null
    fi
    git symbolic-ref --short refs/remotes/origin/HEAD | sed 's|^origin/||'
}
