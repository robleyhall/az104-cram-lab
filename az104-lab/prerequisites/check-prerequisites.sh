#!/usr/bin/env bash
# AZ-104 CertForge Lab — Prerequisite Checker
# Validates that all required tools and configurations are in place.

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
WARN=0

pass() {
  echo -e "  ${GREEN}✔ PASS${NC}  $1"
  ((PASS++))
}

fail() {
  echo -e "  ${RED}✘ FAIL${NC}  $1"
  ((FAIL++))
}

warn() {
  echo -e "  ${YELLOW}⚠ WARN${NC}  $1"
  ((WARN++))
}

header() {
  echo ""
  echo -e "${BLUE}── $1 ──${NC}"
}

# Compare semver: returns 0 if $1 >= $2
version_gte() {
  printf '%s\n%s' "$2" "$1" | sort -V -C
}

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║   AZ-104 CertForge Lab — Prerequisite Check          ║"
echo "╚════════════════════════════════════════════════════════╝"

# ── Azure CLI ──
header "Azure CLI"

if command -v az &>/dev/null; then
  AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
  if [ "$AZ_VERSION" != "unknown" ]; then
    REQUIRED_AZ="2.50.0"
    if version_gte "$AZ_VERSION" "$REQUIRED_AZ"; then
      pass "Azure CLI installed (v${AZ_VERSION}) — meets minimum v${REQUIRED_AZ}"
    else
      fail "Azure CLI v${AZ_VERSION} is below minimum v${REQUIRED_AZ} — please upgrade"
    fi
  else
    fail "Azure CLI found but could not determine version"
  fi
else
  fail "Azure CLI not installed — run: brew install azure-cli (macOS) or see https://aka.ms/install-azure-cli"
fi

# ── Bicep CLI ──
header "Bicep CLI"

if command -v az &>/dev/null; then
  BICEP_VERSION=$(az bicep version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
  if [ -n "$BICEP_VERSION" ]; then
    pass "Bicep CLI installed (v${BICEP_VERSION})"
  else
    fail "Bicep CLI not installed — run: az bicep install"
  fi
else
  fail "Cannot check Bicep — Azure CLI not installed"
fi

# ── Azure Login ──
header "Azure Authentication"

if command -v az &>/dev/null; then
  if az account show &>/dev/null; then
    ACCOUNT_NAME=$(az account show --query "name" -o tsv 2>/dev/null)
    ACCOUNT_ID=$(az account show --query "id" -o tsv 2>/dev/null)
    ACCOUNT_STATE=$(az account show --query "state" -o tsv 2>/dev/null)

    pass "Logged in to Azure"
    echo -e "         Subscription: ${ACCOUNT_NAME}"
    echo -e "         ID: ${ACCOUNT_ID}"

    if [ "$ACCOUNT_STATE" = "Enabled" ]; then
      pass "Subscription is active (state: ${ACCOUNT_STATE})"
    else
      fail "Subscription state is '${ACCOUNT_STATE}' — must be 'Enabled'"
    fi
  else
    fail "Not logged in to Azure — run: az login"
  fi
else
  fail "Cannot check Azure login — Azure CLI not installed"
fi

# ── Resource Providers ──
header "Resource Providers"

REQUIRED_PROVIDERS=(
  "Microsoft.Compute"
  "Microsoft.Network"
  "Microsoft.Storage"
  "Microsoft.ContainerInstance"
  "Microsoft.Web"
  "Microsoft.ContainerRegistry"
  "Microsoft.OperationalInsights"
  "Microsoft.RecoveryServices"
)

if command -v az &>/dev/null && az account show &>/dev/null; then
  for PROVIDER in "${REQUIRED_PROVIDERS[@]}"; do
    STATE=$(az provider show --namespace "$PROVIDER" --query "registrationState" -o tsv 2>/dev/null || echo "Unknown")
    if [ "$STATE" = "Registered" ]; then
      pass "${PROVIDER} — registered"
    elif [ "$STATE" = "Registering" ]; then
      warn "${PROVIDER} — registration in progress"
    else
      fail "${PROVIDER} — not registered (state: ${STATE}). Run: az provider register --namespace ${PROVIDER}"
    fi
  done
else
  fail "Cannot check resource providers — not logged in to Azure"
fi

# ── Optional Tools ──
header "Optional Tools"

if command -v jq &>/dev/null; then
  JQ_VERSION=$(jq --version 2>/dev/null || echo "unknown")
  pass "jq installed (${JQ_VERSION})"
else
  warn "jq not installed — recommended for JSON processing. Install: brew install jq (macOS) or apt install jq (Linux)"
fi

if command -v azcopy &>/dev/null; then
  pass "AzCopy installed"
else
  warn "AzCopy not installed — needed for storage exercises. See: https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-v10"
fi

# ── Summary ──
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║   Summary                                             ║"
echo "╠════════════════════════════════════════════════════════╣"
echo -e "║   ${GREEN}Passed:  ${PASS}${NC}$(printf '%*s' $((40 - ${#PASS})) '')║"
echo -e "║   ${YELLOW}Warnings: ${WARN}${NC}$(printf '%*s' $((39 - ${#WARN})) '')║"
echo -e "║   ${RED}Failed:  ${FAIL}${NC}$(printf '%*s' $((40 - ${#FAIL})) '')║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}✘ Some critical checks failed. Please fix the issues above before proceeding.${NC}"
  echo "  Run ./prerequisites/install-tools.sh to install missing tools."
  exit 1
else
  if [ "$WARN" -gt 0 ]; then
    echo -e "${YELLOW}⚠ All critical checks passed, but some optional tools are missing.${NC}"
    echo "  The lab will work, but some exercises may require additional tools."
  else
    echo -e "${GREEN}✔ All checks passed! You're ready to start the lab.${NC}"
  fi
  exit 0
fi
