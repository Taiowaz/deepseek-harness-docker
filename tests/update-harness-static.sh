#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
script="$repo_dir/update-harness.sh"

[[ -f "$script" ]] || { printf 'missing update-harness.sh\n' >&2; exit 1; }
bash -n "$script"

for required_text in \
    'npm view' \
    'data-workspace-config.tgz' \
    'docker compose -f "$COMPOSE_FILE" config --quiet' \
    'docker compose -f "$COMPOSE_FILE" build harness' \
    'wait_for_healthy' \
    'package.json'; do
    if ! grep -Fq "$required_text" "$script"; then
        printf 'missing required script behavior: %s\n' "$required_text" >&2
        exit 1
    fi
done

if grep -Eq 'docker compose[^[:cntrl:]]*down[^[:cntrl:]]*--volumes|rm[[:space:]]+-rf[[:space:]]+(data|workspace)' "$script"; then
    printf 'destructive data removal found in update script\n' >&2
    exit 1
fi

printf 'Static update script checks passed.\n'
