#!/usr/bin/env bash
# Install or upgrade the stockwatch release.
# Usage: ./run.sh [extra helm args...]

set -euo pipefail

RELEASE="${RELEASE:-stock}"
NAMESPACE="${NAMESPACE:-stock}"
CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

helm upgrade --install "$RELEASE" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --wait \
  --timeout 5m \
  "$@"
