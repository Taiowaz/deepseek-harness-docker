#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
healthcheck="$(rg -n -F "fetch('http://127.0.0.1:3080/')" "$repo_dir/compose.yaml")"

if [[ "$healthcheck" != *'r.status === 200 || r.status === 401'* ]]; then
    printf 'healthcheck must accept the authenticated and unauthenticated ready responses\n' >&2
    exit 1
fi

printf 'Healthcheck static checks passed.\n'
