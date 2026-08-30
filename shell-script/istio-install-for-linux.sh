#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# ISTIO INSTALLATION SCRIPT  (Ubuntu)
#
# Profile  : demo
# Mode     : Traditional Sidecar
#
# Usage:
#   ./install-istio.sh
#   ISTIO_VERSION=1.29.1 ./install-istio.sh
#   ISTIO_PROFILE=default ./install-istio.sh
#   INJECT_NAMESPACE=my-app ./install-istio.sh
#   ALLOW_UPGRADE=true ./install-istio.sh
#   INSTALL_ISTIOCTL_GLOBALLY=true ./install-istio.sh   # symlink into /usr/local/bin
# ============================================================

ISTIO_VERSION="${ISTIO_VERSION:-1.30.4}"
ISTIO_PROFILE="${ISTIO_PROFILE:-demo}"
INJECT_NAMESPACE="${INJECT_NAMESPACE:-default}"
ALLOW_UPGRADE="${ALLOW_UPGRADE:-false}"
INSTALL_ISTIOCTL_GLOBALLY="${INSTALL_ISTIOCTL_GLOBALLY:-false}"
ISTIO_DIR="istio-${ISTIO_VERSION}"

echo "============================================================"
echo "          ISTIO INSTALLATION STARTED"
echo "============================================================"

# ------------------------------------------------------------
# STEP 1: Sanity-check the OS
# ------------------------------------------------------------

echo ""
echo "=== CHECKING OS ==="

if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "Detected: ${PRETTY_NAME:-unknown}"
    if [ "${ID:-}" != "ubuntu" ] && [[ "${ID_LIKE:-}" != *debian* ]]; then
        echo "WARNING: this script targets Ubuntu/Debian. Continuing anyway."
    fi
else
    echo "WARNING: /etc/os-release not found. Continuing anyway."
fi

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# ------------------------------------------------------------
# STEP 2: Install missing prerequisites via apt
# ------------------------------------------------------------

echo ""
echo "=== CHECKING PREREQUISITES ==="

MISSING=()
for cmd in curl tar; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "OK: $cmd found"
    else
        echo "MISSING: $cmd"
        MISSING+=("$cmd")
    fi
done

if [ "${#MISSING[@]}" -gt 0 ]; then
    echo "Installing missing packages: ${MISSING[*]}"
    $SUDO apt-get update -qq
    $SUDO apt-get install -y "${MISSING[@]}"
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERROR: kubectl is not installed."
    echo "Install it with:"
    echo "  sudo snap install kubectl --classic"
    echo "or follow https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
    exit 1
fi
echo "OK: kubectl found"

# ------------------------------------------------------------
# STEP 3: Detect architecture
#
# NOTE: two different naming schemes are in play.
#   downloadIstio expects TARGET_ARCH  -> x86_64 / arm64
#   GitHub release assets are named    -> amd64  / arm64
# Mixing them up produces a 404.
# ------------------------------------------------------------

echo ""
echo "=== DETECTING ARCHITECTURE ==="

RAW_ARCH="$(uname -m)"
case "$RAW_ARCH" in
    x86_64|amd64)
        TARGET_ARCH="x86_64"
        ASSET_ARCH="amd64"
        ;;
    aarch64|arm64)
        TARGET_ARCH="arm64"
        ASSET_ARCH="arm64"
        ;;
    armv7l)
        TARGET_ARCH="armv7"
        ASSET_ARCH="armv7"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $RAW_ARCH"
        exit 1
        ;;
esac

echo "Detected: $RAW_ARCH  ->  TARGET_ARCH=$TARGET_ARCH  ASSET=linux-$ASSET_ARCH"

# ------------------------------------------------------------
# STEP 4: Confirm the release artifact exists
# ------------------------------------------------------------

echo ""
echo "=== VERIFYING ISTIO ${ISTIO_VERSION} EXISTS ==="

RELEASE_URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-linux-${ASSET_ARCH}.tar.gz"

echo "Probing: $RELEASE_URL"

# -L is required: GitHub redirects release downloads to objects.githubusercontent.com
if ! curl -fsSL -r 0-0 -o /dev/null "$RELEASE_URL"; then
    echo "ERROR: Istio ${ISTIO_VERSION} not found for linux-${ASSET_ARCH}."
    echo "Valid versions: https://github.com/istio/istio/releases"
    exit 1
fi

echo "OK: release artifact exists"

# ------------------------------------------------------------
# STEP 5: Check Kubernetes cluster access
# ------------------------------------------------------------

echo ""
echo "=== CHECKING KUBERNETES CLUSTER ACCESS ==="

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

if [ -z "$CURRENT_CONTEXT" ]; then
    echo "ERROR: No Kubernetes context is configured."
    exit 1
fi

echo "Current context: $CURRENT_CONTEXT"

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to the Kubernetes cluster."
    exit 1
fi

echo "OK: cluster is reachable"

echo ""
echo "=== KUBERNETES VERSION ==="
kubectl version 2>/dev/null || true

# ------------------------------------------------------------
# STEP 6: Download Istio
# ------------------------------------------------------------

echo ""
echo "=== DOWNLOADING ISTIO ${ISTIO_VERSION} ==="

if [ -d "$ISTIO_DIR" ]; then
    echo "Directory already present, skipping download: $ISTIO_DIR"
else
    curl -fsSL https://istio.io/downloadIstio \
        | ISTIO_VERSION="$ISTIO_VERSION" TARGET_ARCH="$TARGET_ARCH" sh -
fi

if [ ! -d "$ISTIO_DIR" ]; then
    echo "ERROR: Expected directory '$ISTIO_DIR' was not created."
    exit 1
fi

echo "OK: Istio ${ISTIO_VERSION} downloaded"

# ------------------------------------------------------------
# STEP 7: Locate and verify istioctl
# ------------------------------------------------------------

echo ""
echo "=== CONFIGURING ISTIOCTL ==="

ISTIOCTL="${PWD}/${ISTIO_DIR}/bin/istioctl"

if [ ! -x "$ISTIOCTL" ]; then
    echo "ERROR: istioctl binary not found or not executable at:"
    echo "  $ISTIOCTL"
    exit 1
fi

echo "istioctl: $ISTIOCTL"
"$ISTIOCTL" version --remote=false

if [ "$INSTALL_ISTIOCTL_GLOBALLY" = "true" ]; then
    echo "Linking istioctl into /usr/local/bin ..."
    $SUDO ln -sf "$ISTIOCTL" /usr/local/bin/istioctl
    echo "OK: 'istioctl' is now available system-wide"
fi

# ------------------------------------------------------------
# STEP 8: Check for an existing installation
# ------------------------------------------------------------

echo ""
echo "=== CHECKING EXISTING ISTIO INSTALLATION ==="

if kubectl get deployment istiod -n istio-system >/dev/null 2>&1; then
    echo "WARNING: an existing Istio control plane was detected."
    "$ISTIOCTL" version || true

    if [ "$ALLOW_UPGRADE" != "true" ]; then
        echo ""
        echo "Stopping to avoid overwriting the existing install."
        echo "Re-run with ALLOW_UPGRADE=true to proceed."
        exit 1
    fi
    echo "ALLOW_UPGRADE=true, continuing..."
else
    echo "OK: no existing Istio control plane detected"
fi

# ------------------------------------------------------------
# STEP 9: Validate the profile
# ------------------------------------------------------------

echo ""
echo "=== VALIDATING PROFILE: ${ISTIO_PROFILE} ==="

# 'istioctl profile dump/list' was removed in recent releases.
# Rendering the manifest is the supported way to validate a profile,
# and it fails cleanly on an unknown profile name.
if ! "$ISTIOCTL" manifest generate --set profile="$ISTIO_PROFILE" >/dev/null 2>&1; then
    echo "ERROR: '$ISTIO_PROFILE' is not a valid profile."
    echo "Available profiles:"
    ls "${PWD}/${ISTIO_DIR}/manifests/profiles/" 2>/dev/null | sed 's/\.yaml$//;s/^/  - /'
    exit 1
fi

echo "OK: profile is valid"

# ------------------------------------------------------------
# STEP 9b: Pre-flight cluster check
# ------------------------------------------------------------

echo ""
echo "=== PRE-INSTALL CLUSTER CHECK ==="

# Replaces the old 'verify-install' pre-check.
"$ISTIOCTL" experimental precheck

# ------------------------------------------------------------
# STEP 10: Install Istio
# ------------------------------------------------------------

echo ""
echo "=== INSTALLING ISTIO ==="
echo "Version : $ISTIO_VERSION"
echo "Profile : $ISTIO_PROFILE"
echo "Mode    : traditional sidecar"
echo ""

"$ISTIOCTL" install --set profile="$ISTIO_PROFILE" -y

# ------------------------------------------------------------
# STEP 11: Wait for the control plane
# ------------------------------------------------------------

echo ""
echo "=== WAITING FOR CONTROL PLANE ==="

kubectl -n istio-system rollout status deployment/istiod --timeout=5m

echo ""
echo "Waiting for all istio-system pods to be Ready..."
kubectl wait --for=condition=Ready pods --all -n istio-system --timeout=5m

# ------------------------------------------------------------
# STEP 12: Verify installation
# ------------------------------------------------------------

echo ""
echo "=== VERIFYING INSTALLATION ==="

# 'istioctl verify-install' was also removed. The rollout/wait above is
# the real readiness gate; 'analyze' catches configuration problems.
# Warnings here are informational, so do not abort the script on them.
"$ISTIOCTL" analyze -n istio-system || true

echo ""
echo "Installed control plane:"
"$ISTIOCTL" version

# ------------------------------------------------------------
# STEP 13: Show resources
# ------------------------------------------------------------

echo ""
echo "=== ISTIO SYSTEM PODS ==="
kubectl get pods -n istio-system

echo ""
echo "=== ISTIO SYSTEM SERVICES ==="
kubectl get svc -n istio-system

# ------------------------------------------------------------
# STEP 14: Enable automatic sidecar injection
# ------------------------------------------------------------

echo ""
echo "=== ENABLING AUTOMATIC SIDECAR INJECTION ==="

if ! kubectl get namespace "$INJECT_NAMESPACE" >/dev/null 2>&1; then
    echo "Namespace '$INJECT_NAMESPACE' does not exist, creating it..."
    kubectl create namespace "$INJECT_NAMESPACE"
fi

kubectl label namespace "$INJECT_NAMESPACE" istio-injection=enabled --overwrite

echo "OK: injection enabled on namespace '$INJECT_NAMESPACE'"
echo "NOTE: pods already running there need a restart to pick up a sidecar:"
echo "  kubectl rollout restart deployment -n $INJECT_NAMESPACE"

# ------------------------------------------------------------
# DONE
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo "       ISTIO INSTALLATION COMPLETED"
echo "============================================================"
echo "Version           : $ISTIO_VERSION"
echo "Profile           : $ISTIO_PROFILE"
echo "Control plane     : istiod (istio-system)"
echo "Sidecar injection : $INJECT_NAMESPACE"
echo "Context           : $CURRENT_CONTEXT"
echo "istioctl          : $ISTIOCTL"
echo ""
echo "Add istioctl to your PATH for this shell:"
echo "  export PATH=\"${PWD}/${ISTIO_DIR}/bin:\$PATH\""
echo "============================================================"
