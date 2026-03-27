#!/usr/bin/env bash
# =============================================================================
# validate-02.sh — Validate Module 02: Governance
# Checks: policy assignments, resource locks, custom roles, budgets, tags
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

RG_NAME="rg-certlab-governance"
PASS_COUNT=0; FAIL_COUNT=0; WARN_COUNT=0

pass() { echo -e "  ${GREEN}✅ PASS${NC} — $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "  ${RED}❌ FAIL${NC} — $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { echo -e "  ${YELLOW}⏭ SKIP${NC} — $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
header(){ echo -e "\n${BOLD}${CYAN}── $* ──${NC}\n"; }

echo -e "\n${BOLD}${CYAN}═══ Validate Module 02: Governance ═══${NC}\n"

if ! command -v az &>/dev/null; then echo "Azure CLI not installed."; exit 1; fi
if ! az account show &>/dev/null 2>&1; then echo "Not logged in."; exit 1; fi

# --- Resource Group ---
header "Resource Group"
if az group show --name "$RG_NAME" &>/dev/null 2>&1; then
    pass "Resource group '$RG_NAME' exists"
else
    fail "Resource group '$RG_NAME' not found"
    echo -e "\n${RED}Cannot continue without resource group.${NC}"
    echo -e "  Passed: $PASS_COUNT  Failed: $FAIL_COUNT  Skipped: $WARN_COUNT"
    exit 1
fi

# --- Tags on Resource Group ---
header "Resource Group Tags"
RG_TAGS=$(az group show --name "$RG_NAME" --query "tags" -o json 2>/dev/null || echo "{}")
if echo "$RG_TAGS" | grep -qi "environment"; then
    pass "Tag 'Environment' exists on resource group"
else
    fail "Tag 'Environment' missing on resource group"
fi

if echo "$RG_TAGS" | grep -qi "project"; then
    pass "Tag 'Project' exists on resource group"
else
    fail "Tag 'Project' missing on resource group"
fi

# --- Policy Assignments ---
header "Policy Assignments"
POLICY_COUNT=$(az policy assignment list --resource-group "$RG_NAME" \
    --query "length([])" -o tsv 2>/dev/null || echo "0")
if [[ "$POLICY_COUNT" -gt 0 ]]; then
    pass "Found $POLICY_COUNT policy assignment(s) on $RG_NAME"
else
    fail "No policy assignments found on $RG_NAME"
fi

# Check subscription-level policies with certlab in the name
SUB_POLICIES=$(az policy assignment list \
    --query "[?contains(displayName,'certlab') || contains(name,'certlab')] | length([])" -o tsv 2>/dev/null || echo "0")
if [[ "$SUB_POLICIES" -gt 0 ]]; then
    pass "Found $SUB_POLICIES subscription-level certlab policy assignment(s)"
else
    skip "No subscription-level certlab policy assignments found (may be scoped to RG)"
fi

# --- Resource Locks ---
header "Resource Locks"
LOCK_COUNT=$(az lock list --resource-group "$RG_NAME" \
    --query "length([])" -o tsv 2>/dev/null || echo "0")
if [[ "$LOCK_COUNT" -gt 0 ]]; then
    pass "Found $LOCK_COUNT resource lock(s) on $RG_NAME"

    # Check for CanNotDelete or ReadOnly lock
    DELETE_LOCK=$(az lock list --resource-group "$RG_NAME" \
        --query "[?level=='CanNotDelete'] | length([])" -o tsv 2>/dev/null || echo "0")
    READONLY_LOCK=$(az lock list --resource-group "$RG_NAME" \
        --query "[?level=='ReadOnly'] | length([])" -o tsv 2>/dev/null || echo "0")

    [[ "$DELETE_LOCK" -gt 0 ]] && pass "CanNotDelete lock exists" || skip "No CanNotDelete lock (may use ReadOnly)"
    [[ "$READONLY_LOCK" -gt 0 ]] && pass "ReadOnly lock exists" || skip "No ReadOnly lock (may use CanNotDelete)"
else
    fail "No resource locks found on $RG_NAME"
fi

# --- Custom Role Definition ---
header "Custom Role Definition"
SUB_ID=$(az account show --query "id" -o tsv 2>/dev/null)
CUSTOM_ROLES=$(az role definition list --custom-role-only true \
    --query "[?contains(roleName,'certlab')] | length([])" -o tsv 2>/dev/null || echo "0")
if [[ "$CUSTOM_ROLES" -gt 0 ]]; then
    pass "Found $CUSTOM_ROLES custom role definition(s) with 'certlab' in name"
else
    fail "No custom role definitions with 'certlab' found"
fi

# --- Budget ---
header "Budget"
BUDGET_COUNT=$(az consumption budget list --query "[?contains(name,'certlab')] | length([])" -o tsv 2>/dev/null || echo "0")
if [[ "$BUDGET_COUNT" -gt 0 ]]; then
    pass "Found $BUDGET_COUNT budget(s) with 'certlab' in name"
else
    fail "No budgets with 'certlab' found (check Azure Portal > Cost Management)"
fi

# --- Summary ---
echo -e "\n${BOLD}${CYAN}── Summary ──${NC}"
echo -e "  ${GREEN}Passed: $PASS_COUNT${NC}  ${RED}Failed: $FAIL_COUNT${NC}  ${YELLOW}Skipped: $WARN_COUNT${NC}"
echo ""
[[ $FAIL_COUNT -gt 0 ]] && exit 1 || exit 0
