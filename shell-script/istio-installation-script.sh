#!/bin/bash

set -euo pipefail

# ============================================================
# ISTIO INSTALLATION SCRIPT
#
# Istio Version : 1.32.0
# Installation  : Traditional Sidecar Mode
# Platform      : Kubernetes (EKS / AKS / GKE / On-Prem)
#
# Requirements:
#   - curl
#   - kubectl
#   - Access to a Kubernetes cluster
# ============================================================

ISTIO_VERSION="1.32.0"
ISTIO_DIR="istio-${ISTIO_VERSION}"

echo "============================================================"
echo "          ISTIO INSTALLATION STARTED"
echo "============================================================"

# ------------------------------------------------------------
# STEP 1: Check Required Commands
# ------------------------------------------------------------

echo ""
echo "=== CHECKING PREREQUISITES ==="

if ! command -v curl >/dev/null 2>&1; then
    echo "❌ Error: curl is not installed."
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "❌ Error: kubectl is not installed."
    exit 1
fi

echo "✅ curl found"
echo "✅ kubectl found"

# ------------------------------------------------------------
# STEP 2: Check Kubernetes Cluster Access
# ------------------------------------------------------------

echo ""
echo "=== CHECKING KUBERNETES CLUSTER ACCESS ==="

CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || true)

if [ -z "$CURRENT_CONTEXT" ]; then
    echo "❌ Error: No Kubernetes context is configured."
    exit 1
fi

echo "Current Kubernetes Context:"
echo "$CURRENT_CONTEXT"

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Error: Cannot connect to Kubernetes cluster."
    exit 1
fi

echo "✅ Kubernetes cluster is reachable"

# ------------------------------------------------------------
# STEP 3: Display Kubernetes Version
# ------------------------------------------------------------

echo ""
echo "=== KUBERNETES VERSION ==="

kubectl version --short 2>/dev/null || kubectl version

# ------------------------------------------------------------
# STEP 4: Download Istio
# ------------------------------------------------------------

echo ""
echo "=== DOWNLOADING ISTIO ${ISTIO_VERSION} ==="

if [ -d "$ISTIO_DIR" ]; then
    echo "⚠️ Istio directory already exists:"
    echo "$ISTIO_DIR"
else
    curl -L https://istio.io/downloadIstio \
        | ISTIO_VERSION="$ISTIO_VERSION" sh -
fi

echo "✅ Istio ${ISTIO_VERSION} downloaded"

# ------------------------------------------------------------
# STEP 5: Configure istioctl
# ------------------------------------------------------------

echo ""
echo "=== CONFIGURING ISTIOCTL ==="

ISTIOCTL="${PWD}/${ISTIO_DIR}/bin/istioctl"

if [ ! -x "$ISTIOCTL" ]; then
    echo "❌ Error: istioctl binary not found."
    exit 1
fi

echo "istioctl location:"
echo "$ISTIOCTL"

# ------------------------------------------------------------
# STEP 6: Verify istioctl Version
# ------------------------------------------------------------

echo ""
echo "=== VERIFYING ISTIOCTL ==="

"$ISTIOCTL" version --remote=false

# ------------------------------------------------------------
# STEP 7: Check Existing Istio Installation
# ------------------------------------------------------------

echo ""
echo "=== CHECKING EXISTING ISTIO INSTALLATION ==="

if kubectl get namespace istio-system >/dev/null 2>&1; then
    echo "⚠️ istio-system namespace already exists."

    if kubectl get deployment istiod -n istio-system >/dev/null 2>&1; then
        echo "⚠️ Existing Istio installation detected."
        echo ""
        echo "Current Istio version:"
        "$ISTIOCTL" version

        echo ""
        echo "❌ Installation stopped to prevent overwriting existing Istio."
        exit 1
    fi
fi

echo "✅ No existing Istio control plane detected"

# ------------------------------------------------------------
# STEP 8: Validate Default Profile
# ------------------------------------------------------------

echo ""
echo "=== VALIDATING ISTIO DEFAULT PROFILE ==="

"$ISTIOCTL" profile dump default >/dev/null

echo "✅ Default profile is valid"

# ------------------------------------------------------------
# STEP 9: Install Istio
# ------------------------------------------------------------

echo ""
echo "=== INSTALLING ISTIO ==="
echo ""
echo "Installation Mode:"
echo "Traditional Sidecar Mode"
echo ""
echo "Istio Profile:"
echo "default"
echo ""

"$ISTIOCTL" install \
    --set profile=default \
    -y

# ------------------------------------------------------------
# STEP 10: Verify Istio Installation
# ------------------------------------------------------------

echo ""
echo "=== VERIFYING ISTIO INSTALLATION ==="

"$ISTIOCTL" verify-install

# ------------------------------------------------------------
# STEP 11: Check Istio Pods
# ------------------------------------------------------------

echo ""
echo "=== ISTIO SYSTEM PODS ==="

kubectl get pods -n istio-system

# ------------------------------------------------------------
# STEP 12: Check Istio Services
# ------------------------------------------------------------

echo ""
echo "=== ISTIO SYSTEM SERVICES ==="

kubectl get svc -n istio-system

# ------------------------------------------------------------
# STEP 13: Enable Sidecar Injection
# ------------------------------------------------------------

echo ""
echo "=== ENABLING AUTOMATIC SIDECAR INJECTION ==="

kubectl label namespace default \
    istio-injection=enabled \
    --overwrite

echo "✅ Automatic Envoy sidecar injection enabled"
echo "Namespace: default"

# ------------------------------------------------------------
# STEP 14: Final Verification
# ------------------------------------------------------------

echo ""
echo "=== FINAL ISTIO VERSION ==="

"$ISTIOCTL" version

# ------------------------------------------------------------
# COMPLETED
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo "       ✅ ISTIO INSTALLATION COMPLETED"
echo "============================================================"

echo ""
echo "Istio Version:"
echo "$ISTIO_VERSION"

echo ""
echo "Installation:"
echo "Traditional Sidecar Mode"

echo ""
echo "Control Plane:"
echo "istiod"

echo ""
echo "Sidecar Injection:"
echo "Enabled on default namespace"

echo ""
echo "Kubernetes Context:"
echo "$CURRENT_CONTEXT"

echo ""
echo "============================================================"
