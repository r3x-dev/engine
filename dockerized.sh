#!/usr/bin/env bash
# Interactive activation must not change the caller's shell options or replace it.
if [[ -n "${ZSH_VERSION:-}" ]]; then
  _dockerized_source="${(%):-%x}"
else
  _dockerized_source="${BASH_SOURCE[0]}"
fi
if [[ "$_dockerized_source" != "$0" || "${ZSH_EVAL_CONTEXT:-}" == *:file ]]; then
  _dockerized_shell_runner="$(cd -- "$(dirname -- "$_dockerized_source")" && pwd -P)/dockerized.sh"
  _dockerized_activate_project_bin() {
    local project_bin="$1"
    local previous_bin="${_dockerized_active_bin:-}"
    local path_is_set="${PATH+x}"
    local remaining="${PATH-}"
    local entry result= keep=0 finished

    if [[ "$path_is_set" == x ]]; then
      while :; do
        if [[ "$remaining" == *:* ]]; then
          entry="${remaining%%:*}"
          remaining="${remaining#*:}"
          finished=0
        else
          entry="$remaining"
          finished=1
        fi

        if [[ "$entry" != "$project_bin" ]]; then
          if [[ -z "$previous_bin" || "$entry" != "$previous_bin" ]]; then
            if [[ "$keep" == 0 ]]; then
              result="$entry"
              keep=1
            else
              result="$result:$entry"
            fi
          fi
        fi

        if [[ "$finished" == 1 ]]; then
          break
        fi
      done
    fi

    if [[ "$keep" == 1 ]]; then
      PATH="$project_bin:$result"
    else
      PATH="$project_bin"
    fi
    export PATH
    _dockerized_active_bin="$project_bin"
  }
  _dockerized_activate_project_bin "${_dockerized_shell_runner%/*}/.dev/bin"
  for _dockerized_bin in "${_dockerized_path_functions[@]-}" ruby bundle; do
    if typeset -f "$_dockerized_bin" >/dev/null; then
      unset -f "$_dockerized_bin"
    fi
  done
  _dockerized_path_functions=(dockerized)
  dockerized() { command bash "$_dockerized_shell_runner" "$@"; }
  for _dockerized_bin in "${_dockerized_shell_runner%/*}"/bin/*; do
    [[ -f "$_dockerized_bin" ]] || continue
    _dockerized_bin="${_dockerized_bin##*/}"
    # Function names contain paths; restrict filenames before generating definitions.
    if [[ ! "$_dockerized_bin" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo "Unsupported bin filename: $_dockerized_bin" >&2
      return 1
    fi
    _dockerized_path_functions+=("bin/$_dockerized_bin" "./bin/$_dockerized_bin")
    eval 'function bin/'"$_dockerized_bin"' { dockerized bin/'"$_dockerized_bin"' "$@"; }'
    eval 'function ./bin/'"$_dockerized_bin"' { dockerized ./bin/'"$_dockerized_bin"' "$@"; }'
  done
  unset _dockerized_source _dockerized_bin
  return 0
fi
unset _dockerized_source

set -euo pipefail

# Capture the source location before a caller changes its directory.
_dockerized_project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# Keep CLI commands and editor clients isolated by worktree.
dockerized_context() {
  cd -- "$_dockerized_project_root" || return
  export PWD
  local digest slug
  digest="$(printf '%s' "$PWD" | sha256sum)" || return
  slug="${PWD##*/}"
  slug="${slug,,}"
  slug="${slug//[^a-z0-9_-]/-}"
  export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-dev-${slug:0:32}-${digest:0:12}}"
  export DOCKER_BUNDLE_DIR="$PWD/.bundle/gems"
  export DOCKER_CACHE_DIR="$PWD/.dev/cache"
}

# A prepared bundle is required: opening an editor must never build or install.
dockerized_require_app_image() {
  local image="${COMPOSE_PROJECT_NAME}-app"
  if ! docker image inspect "$image" >/dev/null; then
    echo "App image [$image] is missing; run ./dockerized.sh setup." >&2
    return 1
  fi
}

dockerized_require_runtime() {
  local docker_security_options uid gid
  if ! docker_security_options=$(docker info --format '{{json .SecurityOptions}}'); then
    echo "Could not verify Docker daemon; refusing to start local containers." >&2
    return 1
  fi
  if [[ "$docker_security_options" == *'"name=rootless"'* ]]; then
    export DOCKERIZED_USER="0:0"
    return 0
  fi
  if [[ "$docker_security_options" == *'"name=userns"'* || "$docker_security_options" == *'"name=userns-remap"'* ]]; then
    echo "Rootful Docker with userns-remap is unsupported; refusing to start local containers." >&2
    return 1
  fi
  if ! uid=$(id -u) || ! gid=$(id -g); then
    echo "Could not verify the host user UID and GID; refusing to start local containers." >&2
    return 1
  fi
  if [[ "$uid" == 0 ]]; then
    echo "Rootful Docker cannot run local containers as host root; refusing to start." >&2
    return 1
  fi
  if [[ ! "$uid" =~ ^[0-9]+$ || ! "$gid" =~ ^[0-9]+$ ]]; then
    echo "Could not verify numeric host user UID and GID; refusing to start local containers." >&2
    return 1
  fi
  export DOCKERIZED_USER="$uid:$gid"
}

if [[ $# == 0 ]]; then
  echo "Usage: $0 COMMAND [ARG...] | setup | lsp | compose [ARG...]" >&2
  exit 2
fi

dockerized_context
dockerized_require_runtime

case "$1" in
  compose)
    shift
    exec docker compose --progress quiet "$@"
    ;;
  setup)
    mkdir -p "$DOCKER_BUNDLE_DIR" "$DOCKER_CACHE_DIR"
    docker compose --progress quiet build app
    docker compose --progress quiet run --pull never --rm --no-deps -T --entrypoint '' app bundle install
    exec docker compose --progress quiet run --pull never --rm --no-deps -T --entrypoint '' app ./bin/dprint resolved-config --config dprint.json --file compose.yaml
    ;;
  lsp)
    if [[ ! -f Gemfile.lock || ! -d "$DOCKER_BUNDLE_DIR" ]]; then
      echo "Ruby LSP [$PWD]: run ./dockerized.sh setup to prepare the bundle." >&2
      exit 1
    fi
    dockerized_require_app_image
    exec docker compose --progress quiet run --pull never --rm --no-deps -T editor
    ;;
  *)
    if [[ ! -d "$DOCKER_BUNDLE_DIR" ]]; then
      echo "Local bundle [$PWD]: run ./dockerized.sh setup to prepare it." >&2
      exit 1
    fi
    dockerized_require_app_image
    tty_args=()
    if [[ ! -t 0 || ! -t 1 ]]; then
      tty_args=(-T)
    fi
    exec docker compose --progress quiet run --pull never --rm --no-deps "${tty_args[@]}" app "$@"
    ;;
esac
