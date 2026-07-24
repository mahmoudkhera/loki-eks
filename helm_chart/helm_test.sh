#!/usr/bin/env bash

set -e
set -u

FRONTEND_URL="http://frontend.192.168.49.2.nip.io"
INVENTORY_URL="http://inventory.192.168.49.2.nip.io"


PASS=0
FAIL=0


test_case(){

    local name="$1"
    local command="$2"

    echo -n "----$name"
    if eval "$command" > /dev/null 2>&1; then
        echo " PASS"
        PASS=$((PASS+1))
    else
        echo " FAIL"
        FAIL=$((FAIL+1))
    fi
}
echo "------------------------"
echo "  test ingress dns is working"
echo "------------------------"
echo ""

echo " Health Checks"
test_case "Frontend serves HTML" \
  "curl -sf $FRONTEND_URL| grep -q '<html'"
  
test_case "Inventory /health responds 200" \
  "curl -sf $INVENTORY_URL/health | grep -q 'inventory'"




echo "  Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  echo " ingress tests FAILED"
  exit 1
fi

echo "All  tests passed"
exit 0