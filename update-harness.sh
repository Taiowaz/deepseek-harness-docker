#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PACKAGE_NAME="@deepseek-ai/dsh"
readonly BACKUP_ROOT="${BACKUP_DIR:-$REPO_DIR/backups}"
readonly COMPOSE_FILE="$REPO_DIR/compose.yaml"
readonly DOCKERFILE="$REPO_DIR/Dockerfile"

config_changed=0
backup_dir=""

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [VERSION]

Update $PACKAGE_NAME to npm's latest version and redeploy the harness.

With VERSION, update to an exact npm version instead of the latest tag.
Examples:
  $SCRIPT_NAME
  $SCRIPT_NAME 0.1.2-rc.1

Set BACKUP_DIR to place the private data backup elsewhere.
EOF
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

on_exit() {
    local status=$?
    trap - EXIT

    if (( status != 0 && config_changed == 1 )); then
        if [[ -n "$backup_dir" && -f "$backup_dir/Dockerfile" && -f "$backup_dir/compose.yaml" ]]; then
            cp -p "$backup_dir/Dockerfile" "$DOCKERFILE" || true
            cp -p "$backup_dir/compose.yaml" "$COMPOSE_FILE" || true
            printf 'Restored version configuration from %s\n' "$backup_dir" >&2
        fi
    fi

    exit "$status"
}
trap on_exit EXIT

version_is_valid() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]
}

read_config_version() {
    local file=$1
    local pattern=$2
    sed -nE "s/${pattern}/\2/p" "$file" | head -n 1
}

query_npm_version() {
    local package_spec=$1
    local output

    if command -v npm >/dev/null 2>&1; then
        output="$(npm view "$package_spec" version --json)" || return 1
    elif output="$(docker compose -f "$COMPOSE_FILE" run --rm --no-deps --entrypoint npm harness view "$package_spec" version --json 2>/dev/null)"; then
        :
    else
        output="$(docker run --rm node:24-bookworm-slim npm view "$package_spec" version --json)" || return 1
    fi

    printf '%s' "$output" | tr -d '"[:space:]'
}

wait_for_healthy() {
    local container_id=$1
    local health_status

    for _ in $(seq 1 60); do
        health_status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$container_id" 2>/dev/null || true)"
        case "$health_status" in
            healthy)
                return 0
                ;;
            unhealthy|no-healthcheck)
                printf 'Harness container health status: %s\n' "$health_status" >&2
                return 1
                ;;
            starting)
                sleep 2
                ;;
            *)
                sleep 2
                ;;
        esac
    done

    printf 'Timed out waiting for Harness healthcheck.\n' >&2
    return 1
}

[[ $# -le 1 ]] || { usage >&2; exit 2; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

requested_version="${1:-}"
if [[ -n "$requested_version" ]] && ! version_is_valid "$requested_version"; then
    fail "invalid version: $requested_version"
fi

[[ -f "$COMPOSE_FILE" ]] || fail "missing $COMPOSE_FILE"
[[ -f "$DOCKERFILE" ]] || fail "missing $DOCKERFILE"
command -v docker >/dev/null 2>&1 || fail "docker is required"
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"

current_compose_version="$(read_config_version "$COMPOSE_FILE" '^[[:space:]]*(DSH_VERSION:[[:space:]]*)([^[:space:]]+).*$')"
current_dockerfile_version="$(read_config_version "$DOCKERFILE" '^[[:space:]]*(ARG DSH_VERSION=)([^[:space:]]+).*$')"
[[ -n "$current_compose_version" ]] || fail "could not read DSH_VERSION from $COMPOSE_FILE"
[[ -n "$current_dockerfile_version" ]] || fail "could not read DSH_VERSION from $DOCKERFILE"
[[ "$current_compose_version" == "$current_dockerfile_version" ]] || fail "DSH_VERSION differs between compose.yaml and Dockerfile"
version_is_valid "$current_compose_version" || fail "invalid current DSH_VERSION: $current_compose_version"

package_spec="$PACKAGE_NAME"
if [[ -n "$requested_version" ]]; then
    package_spec="$PACKAGE_NAME@$requested_version"
fi

target_version="$(query_npm_version "$package_spec")" || fail "could not query npm for $package_spec"
version_is_valid "$target_version" || fail "npm returned an invalid version: $target_version"
if [[ -n "$requested_version" && "$target_version" != "$requested_version" ]]; then
    fail "npm resolved $package_spec to $target_version"
fi

printf 'Current Harness version: %s\n' "$current_compose_version"
printf 'Target Harness version:  %s\n' "$target_version"
if [[ "$current_compose_version" == "$target_version" ]]; then
    printf 'Harness is already up to date.\n'
    exit 0
fi

[[ -d "$REPO_DIR/data" ]] || fail "missing data directory"
[[ -d "$REPO_DIR/workspace" ]] || fail "missing workspace directory"
mkdir -p "$BACKUP_ROOT"
chmod 700 "$BACKUP_ROOT"
backup_dir="$BACKUP_ROOT/deepseek-harness-$(date +%Y%m%d-%H%M%S)"
mkdir "$backup_dir"
chmod 700 "$backup_dir"
tar -czf "$backup_dir/data-workspace-config.tgz" -C "$REPO_DIR" data workspace Dockerfile compose.yaml
chmod 600 "$backup_dir/data-workspace-config.tgz"
cp -p "$DOCKERFILE" "$backup_dir/Dockerfile"
cp -p "$COMPOSE_FILE" "$backup_dir/compose.yaml"

sed -E -i "s/^([[:space:]]*DSH_VERSION:[[:space:]]*).*/\1$target_version/" "$COMPOSE_FILE"
sed -E -i "s/^([[:space:]]*ARG DSH_VERSION=).*/\1$target_version/" "$DOCKERFILE"
config_changed=1

updated_compose_version="$(read_config_version "$COMPOSE_FILE" '^[[:space:]]*(DSH_VERSION:[[:space:]]*)([^[:space:]]+).*$')"
updated_dockerfile_version="$(read_config_version "$DOCKERFILE" '^[[:space:]]*(ARG DSH_VERSION=)([^[:space:]]+).*$')"
[[ "$updated_compose_version" == "$target_version" ]] || fail "compose.yaml was not updated to $target_version"
[[ "$updated_dockerfile_version" == "$target_version" ]] || fail "Dockerfile was not updated to $target_version"

docker compose -f "$COMPOSE_FILE" config --quiet
docker compose -f "$COMPOSE_FILE" build harness
docker compose -f "$COMPOSE_FILE" up -d

container_id="$(docker compose -f "$COMPOSE_FILE" ps -q harness)"
[[ -n "$container_id" ]] || fail "could not find the Harness container"
wait_for_healthy "$container_id" || fail "Harness healthcheck did not become healthy"

actual_version="$(docker compose -f "$COMPOSE_FILE" exec -T harness node -p "require('/usr/local/lib/node_modules/@deepseek-ai/dsh/package.json').version" | tr -d '[:space:]')"
[[ "$actual_version" == "$target_version" ]] || fail "container reports $actual_version, expected $target_version"

config_changed=0
printf 'Harness updated successfully to %s\n' "$actual_version"
printf 'Backup: %s/data-workspace-config.tgz\n' "$backup_dir"
docker compose -f "$COMPOSE_FILE" ps
