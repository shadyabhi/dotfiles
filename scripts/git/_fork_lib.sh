# Sourced by git-sync-fork and git-push-on-fork.
# Provides: fork_remote (var), ensure_fork, default_branch.

fork_remote=$(git config --get fork.remote || echo "${USER}-fork")

ensure_fork() {
    if git remote get-url "$fork_remote" >/dev/null 2>&1; then
        return 0
    fi
    local origin_url slug out fork_url
    origin_url=$(git remote get-url origin)
    # owner/repo: strip protocol+host, trailing .git, trailing slash
    slug=$(echo "$origin_url" | sed -E 's#^[^:]+://[^/]+/##; s#\.git$##; s#/$##')
    echo "Fork remote '$fork_remote' missing; creating via gh repo fork $slug" >&2
    # --remote/--remote-name are rejected when a repo arg is given, so fork
    # first, then add the remote from the fork URL gh prints (its resolved
    # host may differ from origin's, e.g. git.netflix.net → github.netflix.net).
    out=$(gh repo fork "$slug" --clone=false 2>&1)
    fork_url=$(echo "$out" | grep -oE 'https?://[^ ]+' | tail -1)
    if [ -z "$fork_url" ]; then
        echo "$out" >&2
        echo "ERROR: could not determine fork URL from gh output" >&2
        return 1
    fi
    git remote add "$fork_remote" "$fork_url"
}

default_branch() {
    if ! git symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null; then
        git remote set-head origin -a >/dev/null
    fi
    git symbolic-ref --short refs/remotes/origin/HEAD | sed 's|^origin/||'
}
