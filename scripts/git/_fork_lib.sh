# Sourced by git-sync-fork and git-push-on-fork.
# Provides: fork_remote (var), ensure_fork, default_branch.

fork_remote=$(git config --get fork.remote || echo "${USER}-fork")

ensure_fork() {
    if git remote get-url "$fork_remote" >/dev/null 2>&1; then
        return 0
    fi
    local origin_url slug
    origin_url=$(git remote get-url origin)
    # owner/repo: strip protocol+host, trailing .git, trailing slash
    slug=$(echo "$origin_url" | sed -E 's#^[^:]+://[^/]+/##; s#\.git$##; s#/$##')
    echo "Fork remote '$fork_remote' missing; creating via gh repo fork $slug" >&2
    gh repo fork "$slug" --remote --remote-name "$fork_remote" --clone=false
}

default_branch() {
    if ! git symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null; then
        git remote set-head origin -a >/dev/null
    fi
    git symbolic-ref --short refs/remotes/origin/HEAD | sed 's|^origin/||'
}
