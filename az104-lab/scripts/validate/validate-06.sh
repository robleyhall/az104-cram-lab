#!/usr/bin/env bash
# =============================================================================
# validate-06.sh — Validate Module 06: Storage
# Checks: storage accounts, containers, file shares, lifecycle, network rules
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

RG_NAME="rg-certlab-storage"
PASS_COUNT=0; FAIL_COUNT=0; WARN_COUNT=0

pass() { echo -e "  ${GREEN}✅ PASS${NC} — $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "  ${RED}❌ FAIL${NC} — $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { echo -e "  ${YELLOW}⏭ SKIP${NC} — $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
header(){ echo -e "\n${BOLD}${CYAN}── $* ──${NC}\n"; }

echo -e "\n${BOLD}${CYAN}═══ Validate Module 06: Storage ═══${NC}\n"

if ! command -v az &>/dev/null; then echo "Azure CLI not installed."; exit 1; fi
if ! az account show &>/dev/null 2>&1; then echo "Not logged in."; exit 1; fi

# --- Resource Group ---
header "Resource Group"
if az group show --name "$RG_NAME" &>/dev/null 2>&1; then
    pass "Resource group '$RG_NAME' exists"
else
    fail "Resource group '$RG_NAME' not found"
    echo -e "\n  Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
    exit 1
fi

# --- Storage Accounts ---
header "Storage Accounts"
SA_LIST=$(az storage account list -g "$RG_NAME" --query "[].name" -o tsv 2>/dev/null || true)
if [[ -n "$SA_LIST" ]]; then
    SA_COUNT=$(echo "$SA_LIST" | wc -l | tr -d ' ')
    pass "Found $SA_COUNT storage account(s)"

    while IFS= read -r sa; do
        [[ -z "$sa" ]] && continue
        pass "Storage account '$sa' exists"

        # Get account key for further checks
        KEY=$(az storage account keys list -g "$RG_NAME" -n "$sa" --query "[0].value" -o tsv 2>/dev/null || true)

        # --- Blob Containers ---
        if [[ -n "$KEY" ]]; then
            CONTAINER_COUNT=$(az storage container list --account-name "$sa" --account-key "$KEY" \
                --query "length([])" -o tsv 2>/dev/null || echo "0")
            if [[ "$CONTAINER_COUNT" -gt 0 ]]; then
                pass "Storage account '$sa' has $CONTAINER_COUNT blob container(s)"
            else
                fail "Storage account '$sa' has no blob containers"
            fi

            # --- File Shares ---
            SHARE_COUNT=$(az storage share list --account-name "$sa" --account-key "$KEY" \
                --query "length([])" -o tsv 2>/dev/null || echo "0")
            if [[ "$SHARE_COUNT" -gt 0 ]]; then
                pass "Storage account '$sa' has $SHARE_COUNT file share(s)"
            else
                skip "Storage account '$sa' has no file shares"
            fi
        else
            skip "Could not retrieve key for '$sa' — skipping container/share checks"
        fi

        # --- Lifecycle Management Policy ---
        LIFECYCLE=$(az storage account management-policy show -g "$RG_NAME" -n "$sa" \
            --query "policy.rules | length([])" -o tsv 2>/dev/null || echo "0")
        if [[ "$LIFECYCLE" -gt 0 ]]; then
            pass "Storage account '$sa' has lifecycle policy with $LIFECYCLE rule(s)"
        else
            fail "Storage account '$sa' has no lifecycle management policy"
        fi

        # --- Network Rules ---
        DEFAULT_ACTION=$(az storage account show -g "$RG_NAME" -n "$sa" \
            --query "networkRuleSet.defaultAction" -o tsv 2>/dev/null || echo "Allow")
        if [[ "$DEFAULT_ACTION" == "Deny" ]]; then
            pass "Storage account '$sa' network default action is Deny (secured)"
        else
            fail "Storage account '$sa' network default action is '$DEFAULT_ACTION' (should be Deny)"
        fi

        VNET_RULES=$(az storage account network-rule list -g "$RG_NAME" -n "$sa" \
            --query "virtualNetworkRules | length([])" -o tsv 2>/dev/null || echo "0")
        IP_RULES=$(az storage account network-rule list -g "$RG_NAME" -n "$sa" \
            --query "ipRules | length([])" -o tsv 2>/dev/null || echo "0")
        TOTAL_RULES=$((VNET_RULES + IP_RULES))
        if [[ "$TOTAL_RULES" -gt 0 ]]; then
            pass "Storage account '$sa' has $TOTAL_RULES network rule(s) (VNet: $VNET_RULES, IP: $IP_RULES)"
        else
            skip "Storage account '$sa' has no VNet/IP network rules"
        fi

    done <<< "$SA_LIST"
else
    fail "No storage accounts found in $RG_NAME"
fi

# --- Summary ---
echo -e "\n${BOLD}${CYAN}── Summary ──${NC}"
echo -e "  ${GREEN}Passed: $PASS_COUNT${NC}  ${RED}Failed: $FAIL_COUNT${NC}  ${YELLOW}Skipped: $WARN_COUNT${NC}"
echo ""
[[ $FAIL_COUNT -gt 0 ]] && exit 1 || exit 0
