#!/usr/bin/env bash
# Launch Claude Code in a sanitized sandbox for the testing/mongodb evals.
#
#   testing/mongodb/sandbox/run-claude.sh <group>   # runs cases with "_sandbox": "<group>"
#
# Groups: clean, existing, personal, cli-missing, ec-capped, ec-ratelimited
# (see the Groups table in testing/mongodb/README.md).
#
# Extra arguments are passed through to `claude`.
#
# What the sandbox does:
#   - Removes MongoDB/Atlas credentials from the environment, so the skill's
#     "existing database" check sees only what the case intends.
#   - Puts stub atlas, brew, curl, docker, mongosh, npx, and ps first on PATH
#     (see bin/). Nothing reaches Atlas, nothing is installed or started, and
#     the skills CLI never writes to real skill directories.
#   - Pre-allows `npx skills` so the session's permission check doesn't stop the
#     call before it reaches the stub (the stub is what the eval is testing), and
#     edits to .env and .gitignore inside the throwaway project, which the
#     Ephemeral Cluster hand-off is graded on.
#   - Starts in a throwaway copy of project/ with its own git repo, so env-file
#     and .gitignore edits land there and not in this repository.
#   - Skips every MCP server (--strict-mcp-config), including connectors that
#     carry Atlas API credentials.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GROUP="${1:-}"
[ $# -gt 0 ] && shift

URI=""
EC_MODE=normal
case "$GROUP" in
  clean)          AUTH=none ;;
  existing)       AUTH=paid
                  URI="mongodb+srv://evaluser:EVALFAKEPW9d21@cluster0.acmeprod.mongodb.net/" ;;
  personal)       AUTH=personal ;;
  cli-missing)    AUTH=missing ;;
  ec-capped)      AUTH=none; EC_MODE=capped ;;
  ec-ratelimited) AUTH=none; EC_MODE=ratelimited ;;
  *)
    echo "usage: $0 clean|existing|personal|cli-missing|ec-capped|ec-ratelimited [claude args...]" >&2
    exit 2
    ;;
esac

PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/mongodb-eval-XXXXXX")"
cp -R "$HERE/project/." "$PROJECT/"
mv "$PROJECT/dot-gitignore" "$PROJECT/.gitignore"
git -C "$PROJECT" init -q
git -C "$PROJECT" add -A
git -C "$PROJECT" -c user.name=eval -c user.email=eval@example.com commit -qm "initial project"

LOG="$PROJECT.log"
: > "$LOG"

# Copy the skill under test out of the repository, so runs can't find the child
# skills sitting next to it in skills/ and skip the install hand-off.
SKILL_COPY="$PROJECT.skill/mongodb"
mkdir -p "$SKILL_COPY"
cp -R "$HERE/../../../skills/mongodb/." "$SKILL_COPY/"

echo "sandbox group:   $GROUP (atlas: $AUTH, ephemeral clusters: $EC_MODE${URI:+, MONGODB_URI set})"
echo "project dir:     $PROJECT"
echo "skill under test: $SKILL_COPY"
echo "invocation log:  $LOG"
echo

cd "$PROJECT"
exec env \
  -u MDB_MCP_CONNECTION_STRING -u MDB_MCP_API_CLIENT_ID -u MDB_MCP_API_CLIENT_SECRET \
  -u MDB_MCP_READ_ONLY -u MONGODB_URI -u DATABASE_URL \
  ${URI:+MONGODB_URI="$URI"} \
  PATH="$HERE/bin:$PATH" \
  ATLAS_STUB_AUTH="$AUTH" \
  EC_STUB_MODE="$EC_MODE" \
  MONGODB_EVAL_LOG="$LOG" \
  MONGODB_EVAL_SKILL="$SKILL_COPY" \
  claude --strict-mcp-config \
    --allowedTools "Bash(npx skills:*)" "Bash(npx -y skills:*)" "Bash(npx --yes skills:*)" \
      "Edit(./**/.env)" "Edit(./**/.gitignore)" "Edit(./.env)" "Edit(./.gitignore)" \
    "$@"
