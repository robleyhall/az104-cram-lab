#!/usr/bin/env bash
# =============================================================================
# validate-04.sh — Validate Module 04: DNS & Connectivity
# Checks: DNS zones, records, Private DNS, VNet links, route tables, Bastion
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

RG_NAME="rg-az104-lab-dns-connectivity"
PASS_COUNT=0; FAIL_COUNT=0; WARN_COUNT=0

pass() { echo -e "  ${GREEN}✅ PASS${NC} — $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "  ${RED}❌ FAIL${NC} — $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { echo -e "  ${YELLOW}⏭ SKIP${NC} — $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
header(){ echo -e "\n${BOLD}${CYAN}── $* ──${NC}\n"; }

echo -e "\n${BOLD}${CYAN}═══ Validate Module 04: DNS & Connectivity ═══${NC}\n"

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

# --- Public DNS Zone ---
header "Public DNS Zone"
DNS_ZONES=$(az network dns zone list -g "$RG_NAME" --query "[].name" -o tsv 2>/dev/null || true)
if [[ -n "$DNS_ZONES" ]]; then
    while IFS= read -r zone; do
        pass "DNS zone '$zone' exists"

        # Check for records
        RECORD_COUNT=$(az network dns record-set list -g "$RG_NAME" -z "$zone" \
            --query "length([?type != 'Microsoft.Network/dnszones/SOA' && type != 'Microsoft.Network/dnszones/NS'])" \
            -o tsv 2>/dev/null || echo "0")
        if [[ "$RECORD_COUNT" -gt 0 ]]; then
            pass "DNS zone '$zone' has $RECORD_COUNT custom record set(s)"
        else
            fail "DNS zone '$zone' has no custom records"
        fi
    done <<< "$DNS_ZONES"
else
    fail "No public DNS zones found in $RG_NAME"
fi

# --- Private DNS Zone ---
header "Private DNS Zone"
PRIVATE_ZONES=$(az network private-dns zone list -g "$RG_NAME" --query "[].name" -o tsv 2>/dev/null || true)
if [[ -n "$PRIVATE_ZONES" ]]; then
    while IFS= read -r pzone; do
        pass "Private DNS zone '$pzone' exists"

        # Check VNet links
        LINK_COUNT=$(az network private-dns link vnet list -g "$RG_NAME" -z "$pzone" \
            --query "length([])" -o tsv 2>/dev/null || echo "0")
        if [[ "$LINK_COUNT" -gt 0 ]]; then
            pass "Private DNS zone '$pzone' has $LINK_COUNT VNet link(s)"
        else
            fail "Private DNS zone '$pzone' has no VNet links"
        fi
    done <<< "$PRIVATE_ZONES"
else
    fail "No private DNS zones found in $RG_NAME"
fi

# --- Route Tables ---
header "Route Tables"
RT_COUNT=$(az network route-table list -g "$RG_NAME" --query "length([])" -o tsv 2>/dev/null || echo "0")
if [[ "$RT_COUNT" -gt 0 ]]; then
    pass "Found $RT_COUNT route table(s)"

    ROUTE_TABLES=$(az network route-table list -g "$RG_NAME" --query "[].name" -o tsv 2>/dev/null || true)
    while IFS= read -r rt; do
        [[ -z "$rt" ]] && continue
        ROUTE_COUNT=$(az network route-table route list -g "$RG_NAME" --route-table-name "$rt" \
            --query "length([])" -o tsv 2>/dev/null || echo "0")
        if [[ "$ROUTE_COUNT" -gt 0 ]]; then
            pass "Route table '$rt' has $ROUTE_COUNT route(s)"
        else
            fail "Route table '$rt' has no custom routes"
        fi
    done <<< "$ROUTE_TABLES"
else
    fail "No route tables found in $RG_NAME"
fi

# --- Bastion Host ---
header "Bastion Host"
BASTION_COUNT=$(az resource list -g "$RG_NAME" \
    --resource-type "Microsoft.Network/bastionHosts" \
    --query "length([])" -o tsv 2>/dev/null || echo "0")
if [[ "$BASTION_COUNT" -gt 0 ]]; then
    pass "Bastion host exists"
else
    skip "No Bastion host found (may be deployed in foundation module)"
fi

# --- Summary ---
echo -e "\n${BOLD}${CYAN}── Summary ──${NC}"
echo -e "  ${GREEN}Passed: $PASS_COUNT${NC}  ${RED}Failed: $FAIL_COUNT${NC}  ${YELLOW}Skipped: $WARN_COUNT${NC}"
echo ""
[[ $FAIL_COUNT -gt 0 ]] && exit 1 || exit 0
