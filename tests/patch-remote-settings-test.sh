#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
patch_script="$repo_dir/scripts/patch-remote-settings.sh"
test_root="$(mktemp -d /tmp/dsh-remote-settings-test.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT

target="$test_root/@deepseek-ai/dsh-client-ui-settings/lib/client.js"
mkdir -p "$(dirname "$target")"
printf '%s\n' 'const persistence = ctx.remote.$host.isLoopback ? "host" : "memory";' > "$target"

if ! "$patch_script" "$test_root"; then
    printf 'expected the remote settings patch to apply\n' >&2
    exit 1
fi
grep -Fxq 'const persistence = "host";' "$target"

"$patch_script" "$test_root"
grep -Fxq 'const persistence = "host";' "$target"

printf '%s\n' 'const persistence = ctx.remote.$host.isLoopback ? "host" : "memory";' > "$target"
printf '%s\n' 'const persistence = ctx.remote.$host.isLoopback ? "host" : "memory";' >> "$target"
if "$patch_script" "$test_root" >/dev/null 2>&1; then
    printf 'expected ambiguous patch target to fail\n' >&2
    exit 1
fi

printf 'Remote settings patch tests passed.\n'
