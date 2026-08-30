#!/usr/bin/env bash
#
# install-minikube-in-macbook.sh — install Minikube on macOS and make sure
# Docker Desktop is running before starting the cluster.
#
# Usage:
#   ./install-minikube-in-macbook.sh
#   ./install-minikube-in-macbook.sh --cpus 4 --memory 8192
#

set -euo pipefail

CPUS="${CPUS:-2}"
MEMORY="${MEMORY:-4096}"
DRIVER="${DRIVER:-docker}"
DOCKER_WAIT_TIMEOUT="${DOCKER_WAIT_TIMEOUT:-180}"   # seconds

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cpus)    CPUS="$2";    shift 2 ;;
    --memory)  MEMORY="$2";  shift 2 ;;
    --driver)  DRIVER="$2";  shift 2 ;;
    --timeout) DOCKER_WAIT_TIMEOUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || die "This script is for macOS only."

# ---------- homebrew ----------
if ! command -v brew >/dev/null 2>&1; then
  log "Homebrew not found. Installing it..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
else
  log "Homebrew found: $(brew --version | head -1)"
fi

# ---------- docker desktop ----------
docker_app_path() {
  if [[ -d "/Applications/Docker.app" ]]; then
    echo "/Applications/Docker.app"
  elif [[ -d "$HOME/Applications/Docker.app" ]]; then
    echo "$HOME/Applications/Docker.app"
  fi
}

# After a fresh install the CLI lives inside the app bundle until Desktop
# creates /usr/local/bin (or ~/.docker/bin) symlinks.
ensure_docker_cli_path() {
  local dir
  for dir in \
    /usr/local/bin \
    "$HOME/.docker/bin" \
    /Applications/Docker.app/Contents/Resources/bin \
    "$HOME/Applications/Docker.app/Contents/Resources/bin"
  do
    if [[ -x "$dir/docker" ]]; then
      case ":$PATH:" in
        *":$dir:"*) ;;
        *) PATH="$dir:$PATH" ;;
      esac
    fi
  done
  export PATH
}

# Bound the check so a stale socket cannot hang the script.
docker_is_running() {
  command -v docker >/dev/null 2>&1 || return 1
  perl -e 'alarm 5; exec @ARGV' docker info >/dev/null 2>&1
}

docker_process_up() {
  pgrep -x com.docker.backend >/dev/null 2>&1 \
    || pgrep -f "Docker Desktop.app" >/dev/null 2>&1 \
    || pgrep -f "Docker Desktop" >/dev/null 2>&1 \
    || pgrep -x Docker >/dev/null 2>&1
}

install_docker_desktop() {
  log "Docker Desktop not found. Installing via Homebrew Cask..."
  brew install --cask docker

  local app installer
  app="$(docker_app_path)"
  installer="${app}/Contents/MacOS/install"
  # Accept the license so first launch is not blocked by a GUI dialog.
  # Privileged helper setup may still ask for a password on first run.
  if [[ -n "$app" && -x "$installer" ]]; then
    log "Accepting Docker Desktop license (unattended)..."
    "$installer" --accept-license --user "$(id -un)" >/dev/null 2>&1 || true
  fi
}

# Launch the app. `open -a` wants the bundle name ("Docker"), not a path.
# Passing a path with -a is a common reason the engine never starts.
launch_docker_app() {
  local app="$1"
  open "$app" 2>/dev/null \
    || open -a Docker 2>/dev/null \
    || osascript -e 'tell application "Docker" to activate' 2>/dev/null \
    || return 1
}

wait_for_docker_daemon() {
  log "Waiting for the Docker daemon (timeout ${DOCKER_WAIT_TIMEOUT}s)..."
  local waited=0
  local restarted=0
  # App can report "already running" while the Linux VM is still booting.
  # If the engine is still down after this many seconds, bounce Desktop once.
  local restart_after=45

  until docker_is_running; do
    if (( waited >= DOCKER_WAIT_TIMEOUT )); then
      echo
      warn "Docker context in use: $(docker context show 2>/dev/null || echo unknown)"
      warn "Last error from 'docker info':"
      perl -e 'alarm 8; exec @ARGV' docker info 2>&1 | tail -8 || true
      die "Docker did not become ready in ${DOCKER_WAIT_TIMEOUT}s. Check whether Docker Desktop is showing a dialog (license terms, permissions, or update prompt) that needs a click."
    fi

    if (( restarted == 0 && waited >= restart_after )); then
      if docker_process_up; then
        echo
        warn "Docker Desktop is open but the engine is not ready. Restarting it..."
        if command -v docker >/dev/null 2>&1 && docker desktop --help >/dev/null 2>&1; then
          docker desktop restart --timeout "$DOCKER_WAIT_TIMEOUT" || true
        else
          launch_docker_app "$(docker_app_path)" || true
        fi
        restarted=1
      fi
    fi

    sleep 3
    waited=$((waited + 3))
    printf '.'
  done
  printf '\n'
  log "Docker daemon is ready."
}

start_docker_desktop() {
  local app
  app="$(docker_app_path)"
  [[ -n "$app" ]] || die "Docker.app not found even after install."
  ensure_docker_cli_path

  log "Docker daemon is not responding. Starting Docker Desktop..."

  # Official CLI starts the engine. When the app is already open it prints
  # "already running" and returns immediately — even if the VM is still
  # booting — so we always wait for `docker info` afterwards.
  if command -v docker >/dev/null 2>&1 && docker desktop --help >/dev/null 2>&1; then
    log "Using 'docker desktop start'..."
    docker desktop start --timeout "$DOCKER_WAIT_TIMEOUT" || {
      warn "'docker desktop start' failed; launching the app instead."
      launch_docker_app "$app" || die "Failed to launch $app"
    }
  else
    launch_docker_app "$app" || die "Failed to launch $app"
    sleep 3
    if ! docker_process_up; then
      warn "Docker Desktop process not detected after launch; retrying..."
      launch_docker_app "$app" || true
      sleep 3
    fi
  fi

  if docker_is_running; then
    log "Docker daemon is ready."
    return 0
  fi

  wait_for_docker_daemon
}

ensure_docker() {
  ensure_docker_cli_path
  if [[ -z "$(docker_app_path)" ]]; then
    install_docker_desktop
    ensure_docker_cli_path
  fi
  if docker_is_running; then
    log "Docker is already running."
  else
    start_docker_desktop
  fi
}

# ---------- minikube + kubectl ----------
ensure_minikube() {
  if command -v minikube >/dev/null 2>&1; then
    log "Minikube already installed: $(minikube version --short 2>/dev/null || minikube version | head -1)"
  else
    log "Installing Minikube..."
    brew install minikube
  fi

  if command -v kubectl >/dev/null 2>&1; then
    log "kubectl already installed."
  else
    log "Installing kubectl..."
    brew install kubectl
  fi
}

start_cluster() {
  if minikube status --format '{{.Host}}' 2>/dev/null | grep -q Running; then
    log "Minikube cluster is already running."
  else
    log "Starting Minikube (driver=$DRIVER, cpus=$CPUS, memory=${MEMORY}MB)..."
    minikube start --driver="$DRIVER" --cpus="$CPUS" --memory="$MEMORY"
  fi
}

# ---------- run ----------
if [[ "$DRIVER" == "docker" ]]; then
  ensure_docker
else
  warn "Driver is '$DRIVER'; skipping Docker Desktop checks."
fi

ensure_minikube
start_cluster

log "Done. Cluster status:"
minikube status || true
echo
log "Try: kubectl get nodes"


