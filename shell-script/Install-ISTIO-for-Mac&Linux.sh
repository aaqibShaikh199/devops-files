#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# ISTIO INSTALLATION SCRIPT
#
# Platform : macOS (Intel + Apple Silicon) and Linux
# Profile  : demo
# Mode     : Traditional Sidecar
#
# Usage:
#   ./install-istio.sh
#   ISTIO_VERSION=1.29.1 ./install-istio.sh
#   ISTIO_PROFILE=default ./install-istio.sh
#   INJECT_NAMESPACE=my-app ./install-istio.sh
#   ALLOW_UPGRADE=true ./install-istio.sh
#   INSTALL_ISTIOCTL_GLOBALLY=true ./install-istio.sh
#
# Written for bash 3.2 so it runs on stock macOS /bin/bash.
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
# STEP 1: Detect OS and architecture
#
# Three naming schemes are in play, and mixing them causes 404s:
#   uname -s / -m       -> Darwin / arm64
#   downloadIstio       -> TARGET_ARCH=arm64 or x86_64
#   GitHub release file -> istio-<ver>-osx-arm64.tar.gz
#                          istio-<ver>-linux-amd64.tar.gz
# Note macOS uses "osx" and arch "arm64"/"amd64",
# while downloadIstio wants "x86_64" for Intel.
# ------------------------------------------------------------

echo ""
echo "=== DETECTING PLATFORM ==="

RAW_OS="$(uname -s)"
RAW_ARCH="$(uname -m)"

case "$RAW_OS" in
    Darwin) ASSET_OS="osx" ;;
    Linux)  ASSET_OS="linux" ;;
    *)
        echo "ERROR: Unsupported OS: $RAW_OS"
        exit 1
        ;;
esac

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

echo "OS   : $RAW_OS  -> $ASSET_OS"
echo "Arch : $RAW_ARCH  -> asset=$ASSET_ARCH, TARGET_ARCH=$TARGET_ARCH"

# ------------------------------------------------------------
# STEP 2: Check prerequisites
# ------------------------------------------------------------

echo ""
echo "=== CHECKING PREREQUISITES ==="

for cmd in curl tar kubectl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: '$cmd' is not installed or not on PATH."
        if [ "$RAW_OS" = "Darwin" ]; then
            echo "Install it with:  brew install $cmd"
        fi
        exit 1
    fi
    echo "OK: $cmd found"
done

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# ------------------------------------------------------------
# STEP 3: Confirm the release artifact exists
# ------------------------------------------------------------

echo ""
echo "=== VERIFYING ISTIO ${ISTIO_VERSION} EXISTS ==="

RELEASE_URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-${ASSET_OS}-${ASSET_ARCH}.tar.gz"

echo "Probing: $RELEASE_URL"

# Request one byte rather than using -I: GitHub redirects release
# downloads to objects.githubusercontent.com, where HEAD is unreliable.
if ! curl -fsSL -r 0-0 -o /dev/null "$RELEASE_URL"; then
    echo "ERROR: Istio ${ISTIO_VERSION} not found for ${ASSET_OS}-${ASSET_ARCH}."
    echo "Valid versions: https://github.com/istio/istio/releases"
    exit 1
fi

echo "OK: release artifact exists"

# ------------------------------------------------------------
# STEP 4: Check Kubernetes cluster access
# ------------------------------------------------------------

echo ""
echo "=== CHECKING KUBERNETES CLUSTER ACCESS ==="

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

if [ -z "$CURRENT_CONTEXT" ]; then
    echo "ERROR: No Kubernetes context is configured."
    echo "If you are using Docker Desktop, enable Kubernetes in its settings."
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
# STEP 5: Download Istio
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
# STEP 6: Locate istioctl
# ------------------------------------------------------------

echo ""
echo "=== CONFIGURING ISTIOCTL ==="

ISTIOCTL="${PWD}/${ISTIO_DIR}/bin/istioctl"

if [ ! -x "$ISTIOCTL" ]; then
    echo "ERROR: istioctl binary not found or not executable at:"
    echo "  $ISTIOCTL"
    exit 1
fi

# macOS Gatekeeper quarantines binaries from downloaded archives.
if [ "$RAW_OS" = "Darwin" ] && command -v xattr >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "$ISTIOCTL" 2>/dev/null || true
fi

echo "istioctl: $ISTIOCTL"
"$ISTIOCTL" version --remote=false

if [ "$INSTALL_ISTIOCTL_GLOBALLY" = "true" ]; then
    echo "Linking istioctl into /usr/local/bin ..."
    $SUDO mkdir -p /usr/local/bin
    $SUDO ln -sf "$ISTIOCTL" /usr/local/bin/istioctl
    echo "OK: 'istioctl' is now available system-wide"
fi

# ------------------------------------------------------------
# STEP 7: Check for an existing installation
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
# STEP 8: Validate the profile
# ------------------------------------------------------------

echo ""
echo "=== VALIDATING PROFILE: ${ISTIO_PROFILE} ==="

# 'istioctl profile dump' and 'profile list' were removed in recent
# releases. Rendering the manifest is the supported way to validate a
# profile name, and it exits non-zero on an unknown one.
if ! "$ISTIOCTL" manifest generate --set profile="$ISTIO_PROFILE" >/dev/null 2>&1; then
    echo "ERROR: '$ISTIO_PROFILE' is not a valid profile."
    echo "Available profiles:"
    ls "${PWD}/${ISTIO_DIR}/manifests/profiles/" 2>/dev/null \
        | sed 's/\.yaml$//; s/^/  - /'
    exit 1
fi

echo "OK: profile is valid"

# ------------------------------------------------------------
# STEP 9: Pre-flight cluster check
# ------------------------------------------------------------

echo ""
echo "=== PRE-INSTALL CLUSTER CHECK ==="

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

# 'istioctl verify-install' was removed. The rollout/wait above is the
# real readiness gate; 'analyze' surfaces configuration problems.
# Its warnings are informational, so do not abort on them.
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
echo "Platform          : ${ASSET_OS}-${ASSET_ARCH}"
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
