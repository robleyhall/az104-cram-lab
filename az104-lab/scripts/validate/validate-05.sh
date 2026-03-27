#!/usr/bin/env bash
# =============================================================================
# validate-05.sh — Validate Module 05: Load Balancing
# Checks: load balancer, frontend IP, backend pool, rules, Traffic Manager
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

RG_NAME="rg-certlab-load-balancing"
PASS_COUNT=0; FAIL_COUNT=0; WARN_COUNT=0

pass() { echo -e "  ${GREEN}✅ PASS${NC} — $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "  ${RED}❌ FAIL${NC} — $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { echo -e "  ${YELLOW}⏭ SKIP${NC} — $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
header(){ echo -e "\n${BOLD}${CYAN}── $* ──${NC}\n"; }

echo -e "\n${BOLD}${CYAN}═══ Validate Module 05: Load Balancing ═══${NC}\n"

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

# --- Load Balancer ---
header "Load Balancer"
LB_LIST=$(az network lb list -g "$RG_NAME" --query "[].name" -o tsv 2>/dev/null || true)
if [[ -n "$LB_LIST" ]]; then
    while IFS= read -r lb; do
        pass "Load balancer '$lb' exists"

        # Frontend IP configuration
        FE_COUNT=$(az network lb frontend-ip list -g "$RG_NAME" --lb-name "$lb" \
            --query "length([])" -o tsv 2>/dev/null || echo "0")
        if [[ "$FE_COUNT" -gt 0 ]]; then
            pass "Load balancer '$lb' has $FE_COUNT frontend IP config(s)"
        else
            fail "Load balancer '$lb' has no frontend IP configuration"
        fi

        # Backend pool
        BP_COUNT=$(az network lb address-pool list -g "$RG_NAME" --lb-name "$lb" \
            --query "length([])" -o tsv 2>/dev/null || echo "0")
        if [[ "$BP_COUNT" -gt 0 ]]; then
            pass "Load balancer '$lb' has $BP_COUNT backend pool(s)"
        else
            fail "Load balancer '$lb' has no backend pools"
        fi

        # Load balancing rules
        RULE_COUNT=$(az network lb rule list -g "$RG_NAME" --lb-name "$lb" \
            --query "length([])" -o tsv 2>/dev/null || echo "0")
        if [[ "$RULE_COUNT" -gt 0 ]]; then
            pass "Load balancer '$lb' has $RULE_COUNT rule(s)"
        else
            fail "Load balancer '$lb' has no load balancing rules"
        fi

        # Health probe
        PROBE_COUNT=$(az network lb probe list -g "$RG_NAME" --lb-name "$lb" \
            --query "length([])" -o tsv 2>/dev/null || echo "0")
        if [[ "$PROBE_COUNT" -gt 0 ]]; then
            pass "Load balancer '$lb' has $PROBE_COUNT health probe(s)"
        else
            fail "Load balancer '$lb' has no health probes"
        fi

    done <<< "$LB_LIST"
else
    fail "No load balancers found in $RG_NAME"
fi

# --- Traffic Manager ---
header "Traffic Manager"
TM_PROFILES=$(az network traffic-manager profile list -g "$RG_NAME" \
    --query "[].name" -o tsv 2>/dev/null || true)
if [[ -n "$TM_PROFILES" ]]; then
    while IFS= read -r tm; do
        pass "Traffic Manager profile '$tm' exists"

        # Check routing method
        METHOD=$(az network traffic-manager profile show -g "$RG_NAME" -n "$tm" \
            --query "trafficRoutingMethod" -o tsv 2>/dev/null || echo "Unknown")
        pass "Traffic Manager '$tm' uses '$METHOD' routing"

        # Check endpoints
        EP_COUNT=$(az network traffic-manager endpoint list -g "$RG_NAME" --profile-name "$tm" \
            --type azureEndpoints --query "length([])" -o tsv 2>/dev/null || echo "0")
        EP_COUNT2=$(az network traffic-manager endpoint list -g "$RG_NAME" --profile-name "$tm" \
            --type externalEndpoints --query "length([])" -o tsv 2>/dev/null || echo "0")
        TOTAL_EP=$((EP_COUNT + EP_COUNT2))
        if [[ "$TOTAL_EP" -gt 0 ]]; then
            pass "Traffic Manager '$tm' has $TOTAL_EP endpoint(s)"
        else
            fail "Traffic Manager '$tm' has no endpoints"
        fi
    done <<< "$TM_PROFILES"
else
    fail "No Traffic Manager profiles found in $RG_NAME"
fi

# --- Application Gateway (bonus check) ---
header "Application Gateway (Optional)"
APPGW_COUNT=$(az network application-gateway list -g "$RG_NAME" \
    --query "length([])" -o tsv 2>/dev/null || echo "0")
if [[ "$APPGW_COUNT" -gt 0 ]]; then
    pass "Found $APPGW_COUNT Application Gateway(s)"
else
    skip "No Application Gateway found (optional for this module)"
fi

# --- Summary ---
echo -e "\n${BOLD}${CYAN}── Summary ──${NC}"
echo -e "  ${GREEN}Passed: $PASS_COUNT${NC}  ${RED}Failed: $FAIL_COUNT${NC}  ${YELLOW}Skipped: $WARN_COUNT${NC}"
echo ""
[[ $FAIL_COUNT -gt 0 ]] && exit 1 || exit 0
