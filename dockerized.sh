#!/usr/bin/env bash
# Explicit Docker command runner; the caller's shell and PATH stay unchanged.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo 'Run ./dockerized.sh COMMAND [ARG...]; do not source this script.' >&2
  return 2
fi
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
caller_dir="$(pwd -P)"
case "$caller_dir/" in
  "$project_root/"*) ;;
  *) echo "Working directory [$caller_dir] is outside this checkout [$project_root]." >&2; exit 1 ;;
esac
if [[ $# == 0 ]]; then
  echo "Usage: $0 COMMAND [ARG...] | setup | up | compose [ARG...]" >&2
  exit 2
fi

digest="$(printf '%s' "$project_root" | sha256sum)"
slug="${project_root##*/}"
slug="${slug,,}"
slug="${slug//[^a-z0-9_-]/-}"
export COMPOSE_PROJECT_NAME="dev-${slug:0:32}-${digest:0:12}"
export DOCKER_PROJECT_DIR="$project_root"
export DOCKER_BUNDLE_DIR="$project_root/.bundle/gems"
export DOCKER_CACHE_DIR="$project_root/.dev/cache"

# Rootless UID 0 maps to the daemon user. Reject unsupported bind-mount ownership.
if ! security_options=$(docker info --format '{{json .SecurityOptions}}'); then
  echo 'Could not verify Docker daemon; refusing to start local containers.' >&2
  exit 1
fi
if [[ "$security_options" == *'"name=rootless"'* ]]; then
  export DOCKERIZED_USER=0:0
elif [[ "$security_options" == *'"name=userns"'* || "$security_options" == *'"name=userns-remap"'* ]]; then
  echo 'Rootful Docker with userns-remap is unsupported; refusing to start local containers.' >&2
  exit 1
else
  uid="$(id -u)"
  gid="$(id -g)"
  if [[ "$uid" == 0 ]]; then
    echo 'Rootful Docker cannot run local containers as host root; refusing to start.' >&2
    exit 1
  fi
  if [[ ! "$uid" =~ ^[0-9]+$ || ! "$gid" =~ ^[0-9]+$ ]]; then
    echo 'Could not verify numeric host user UID and GID; refusing to start local containers.' >&2
    exit 1
  fi
  export DOCKERIZED_USER="$uid:$gid"
fi

# Execute the registered plugin directly: Docker's parent CLI cancels its plugin socket
# on SIGTERM instead of forwarding the signal (docker/cli cmd/docker/docker.go).
compose_binary="$(docker info --format '{{range .ClientInfo.Plugins}}{{if eq .Name "compose"}}{{.Path}}{{end}}{{end}}')"
if [[ -z "$compose_binary" || ! -x "$compose_binary" ]]; then
  echo 'Docker Compose plugin is unavailable; install it before running just setup.' >&2
  exit 1
fi
compose=("$compose_binary" --project-directory "$project_root" --file "$project_root/compose.yaml" --progress quiet)

require_image() {
  local image
  image="$("${compose[@]}" config --images "$1")"
  if ! docker image inspect "$image" >/dev/null; then
    echo "Image [$image] is missing; run just setup in [$project_root]." >&2
    exit 1
  fi
}

case "$1" in
  setup)
    mkdir -p "$DOCKER_BUNDLE_DIR" "$DOCKER_CACHE_DIR"
    "${compose[@]}" build app
    "${compose[@]}" pull --policy missing js-tests dockerfile-lint postgres
    "${compose[@]}" run --pull never --rm --no-deps -T --entrypoint '' app bundle install
    exec "${compose[@]}" run --pull never --rm --no-deps -T --entrypoint '' app ./bin/dprint install
    ;;
  up)
    if [[ $# != 1 ]]; then
      echo 'up takes no arguments. Use ./dockerized.sh compose ... for explicit Compose administration.' >&2
      exit 2
    fi
    require_image app
    exec "${compose[@]}" up --no-build --pull never --exit-code-from app app
    ;;
  compose)
    shift
    exec "${compose[@]}" "$@"
    ;;
  *)
    require_image app
    tty_args=()
    if [[ ! -t 0 || ! -t 1 ]]; then tty_args=(-T); fi
    exec "${compose[@]}" run --pull never --rm --no-deps "${tty_args[@]}" --workdir "$caller_dir" app "$@"
    ;;
esac
