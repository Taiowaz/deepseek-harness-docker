#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

for required_text in \
    'network: host' \
    'HTTP_PROXY: "${HTTP_PROXY:-}"' \
    'HTTPS_PROXY: "${HTTPS_PROXY:-}"' \
    'NO_PROXY: "${NO_PROXY:-}"'; do
    if ! grep -Fq -- "$required_text" "$repo_dir/compose.yaml"; then
        printf 'missing Compose proxy behavior: %s\n' "$required_text" >&2
        exit 1
    fi
done

for required_text in 'ARG HTTP_PROXY' 'ARG HTTPS_PROXY' 'ARG NO_PROXY'; do
    if ! grep -Fq -- "$required_text" "$repo_dir/Dockerfile"; then
        printf 'missing Dockerfile proxy argument: %s\n' "$required_text" >&2
        exit 1
    fi
done

grep -Fq -- 'HTTP_PROXY=' "$repo_dir/.env.example"
grep -Fq -- 'HTTPS_PROXY=' "$repo_dir/.env.example"

printf 'Build proxy static checks passed.\n'
