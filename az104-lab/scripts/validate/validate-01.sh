#!/usr/bin/env bash
# =============================================================================
# validate-01.sh — Validate Module 01: Identity (Entra ID)
# Checks: users, groups, role assignments
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

RG_NAME="rg-certlab-identity"
PASS_COUNT=0; FAIL_COUNT=0; WARN_COUNT=0

pass() { echo -e "  ${GREEN}✅ PASS${NC} — $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "  ${RED}❌ FAIL${NC} — $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { echo -e "  ${YELLOW}⏭ SKIP${NC} — $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
header(){ echo -e "\n${BOLD}${CYAN}── $* ──${NC}\n"; }

echo -e "\n${BOLD}${CYAN}═══ Validate Module 01: Identity ═══${NC}\n"

if ! command -v az &>/dev/null; then echo "Azure CLI not installed."; exit 1; fi
if ! az account show &>/dev/null 2>&1; then echo "Not logged in."; exit 1; fi

# --- Resource Group ---
header "Resource Group"
if az group show --name "$RG_NAME" &>/dev/null 2>&1; then
    pass "Resource group '$RG_NAME' exists"
else
    fail "Resource group '$RG_NAME' not found"
fi

# --- Entra Users ---
header "Entra ID Users"
EXPECTED_USERS=("certlab-user1" "certlab-user2" "certlab-user3")
for user in "${EXPECTED_USERS[@]}"; do
    FOUND=$(az ad user list --filter "startswith(displayName,'$user')" --query "length([])" -o tsv 2>/dev/null || echo "0")
    if [[ "$FOUND" -gt 0 ]]; then
        pass "User '$user' exists in Entra ID"
    else
        fail "User '$user' not found in Entra ID"
    fi
done

# --- Entra Groups ---
header "Entra ID Groups"
EXPECTED_GROUPS=("certlab-admins" "certlab-readers" "certlab-contributors")
for group in "${EXPECTED_GROUPS[@]}"; do
    FOUND=$(az ad group list --filter "startswith(displayName,'$group')" --query "length([])" -o tsv 2>/dev/null || echo "0")
    if [[ "$FOUND" -gt 0 ]]; then
        pass "Group '$group' exists in Entra ID"
    else
        fail "Group '$group' not found in Entra ID"
    fi
done

# --- Role Assignments ---
header "Role Assignments"
if az group show --name "$RG_NAME" &>/dev/null 2>&1; then
    ROLE_COUNT=$(az role assignment list --resource-group "$RG_NAME" --query "length([])" -o tsv 2>/dev/null || echo "0")
    if [[ "$ROLE_COUNT" -gt 0 ]]; then
        pass "Found $ROLE_COUNT role assignment(s) on $RG_NAME"
    else
        fail "No role assignments found on $RG_NAME"
    fi

    # Check for specific roles
    for role in "Reader" "Contributor"; do
        HAS_ROLE=$(az role assignment list --resource-group "$RG_NAME" \
            --query "[?roleDefinitionName=='$role'] | length([])" -o tsv 2>/dev/null || echo "0")
        if [[ "$HAS_ROLE" -gt 0 ]]; then
            pass "Role '$role' is assigned on $RG_NAME"
        else
            fail "Role '$role' not assigned on $RG_NAME"
        fi
    done
else
    skip "Skipping role checks — resource group not found"
fi

# --- Summary ---
echo -e "\n${BOLD}${CYAN}── Summary ──${NC}"
echo -e "  ${GREEN}Passed: $PASS_COUNT${NC}  ${RED}Failed: $FAIL_COUNT${NC}  ${YELLOW}Skipped: $WARN_COUNT${NC}"
echo ""
[[ $FAIL_COUNT -gt 0 ]] && exit 1 || exit 0
