#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATCH_ROOT="${1:-/usr/local/lib/node_modules}"
readonly TARGET_SUFFIX="@deepseek-ai/dsh-client-ui-settings/lib/client.js"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -d "$PATCH_ROOT" ]] || fail "patch root does not exist: $PATCH_ROOT"
command -v find >/dev/null 2>&1 || fail "find is required"
command -v node >/dev/null 2>&1 || fail "node is required"

mapfile -t targets < <(find "$PATCH_ROOT" -type f -path "*/$TARGET_SUFFIX" -print)
((${#targets[@]} > 0)) || fail "could not find $TARGET_SUFFIX below $PATCH_ROOT"

readonly ORIGINAL_TEXT='const persistence = ctx.remote.$host.isLoopback ? "host" : "memory";'
readonly PATCHED_TEXT='const persistence = "host";'

active_target=""
active_count=0
patched_count=0

for target in "${targets[@]}"; do
    state="$(TARGET_FILE="$target" DSH_PATCH_ORIGINAL="$ORIGINAL_TEXT" DSH_PATCH_VALUE="$PATCHED_TEXT" node <<'NODE'
const fs = require('node:fs')

const source = fs.readFileSync(process.env.TARGET_FILE, 'utf8')
const original = process.env.DSH_PATCH_ORIGINAL
const patched = process.env.DSH_PATCH_VALUE
const count = (value, needle) => value.split(needle).length - 1

process.stdout.write(`${count(source, original)}:${count(source, patched)}`)
NODE
)"
    original_count="${state%%:*}"
    patched_in_file="${state##*:}"

    if (( original_count > 0 )); then
        active_target="$target"
        active_count=$((active_count + original_count))
    fi
    patched_count=$((patched_count + patched_in_file))
done

((active_count <= 1)) || fail "remote settings patch target matched $active_count times"

if ((active_count == 1)); then
    TARGET_FILE="$active_target" DSH_PATCH_ORIGINAL="$ORIGINAL_TEXT" DSH_PATCH_VALUE="$PATCHED_TEXT" node <<'NODE'
const fs = require('node:fs')

const file = process.env.TARGET_FILE
const original = process.env.DSH_PATCH_ORIGINAL
const patched = process.env.DSH_PATCH_VALUE
const source = fs.readFileSync(file, 'utf8')
const matches = source.split(original).length - 1

if (matches !== 1) {
  throw new Error(`expected one patch target in ${file}, found ${matches}`)
}

fs.writeFileSync(file, source.replace(original, patched))
NODE
    printf 'Applied remote settings patch: %s\n' "$active_target"
elif ((patched_count == 1)); then
    printf 'Remote settings patch already applied.\n'
else
    fail "remote settings patch target was not found in exactly one file"
fi
