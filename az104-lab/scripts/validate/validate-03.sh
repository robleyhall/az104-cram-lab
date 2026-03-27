#!/usr/bin/env bash
# =============================================================================
# validate-03.sh — Validate Module 03: Networking
# Checks: VNets, peering, NSGs, ASGs, public IPs
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

RG_NAME="rg-certlab-networking"
PASS_COUNT=0; FAIL_COUNT=0; WARN_COUNT=0

pass() { echo -e "  ${GREEN}✅ PASS${NC} — $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "  ${RED}❌ FAIL${NC} — $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { echo -e "  ${YELLOW}⏭ SKIP${NC} — $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
header(){ echo -e "\n${BOLD}${CYAN}── $* ──${NC}\n"; }

echo -e "\n${BOLD}${CYAN}═══ Validate Module 03: Networking ═══${NC}\n"

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

# --- Virtual Networks ---
header "Virtual Networks"
VNET_COUNT=$(az network vnet list -g "$RG_NAME" --query "length([])" -o tsv 2>/dev/null || echo "0")
if [[ "$VNET_COUNT" -gt 0 ]]; then
    pass "Found $VNET_COUNT VNet(s)"

    # List VNets and check address spaces
    VNETS=$(az network vnet list -g "$RG_NAME" --query "[].{name:name, space:addressSpace.addressPrefixes[0]}" -o tsv 2>/dev/null || true)
    while IFS=$'\t' read -r vname vspace; do
        [[ -z "$vname" ]] && continue
        if [[ -n "$vspace" ]]; then
            pass "VNet '$vname' has address space: $vspace"
        else
            fail "VNet '$vname' has no address space configured"
        fi

        # Check subnets
        SUBNET_COUNT=$(az network vnet subnet list -g "$RG_NAME" --vnet-name "$vname" \
            --query "length([])" -o tsv 2>/dev/null || echo "0")
        if [[ "$SUBNET_COUNT" -gt 0 ]]; then
            pass "VNet '$vname' has $SUBNET_COUNT subnet(s)"
        else
            fail "VNet '$vname' has no subnets"
        fi
    done <<< "$VNETS"
else
    fail "No VNets found in $RG_NAME"
fi

# --- VNet Peering ---
header "VNet Peering"
PEERING_FOUND=false
VNETS_LIST=$(az network vnet list -g "$RG_NAME" --query "[].name" -o tsv 2>/dev/null || true)
while IFS= read -r vname; do
    [[ -z "$vname" ]] && continue
    PEERINGS=$(az network vnet peering list -g "$RG_NAME" --vnet-name "$vname" \
        --query "[].{name:name, state:peeringState}" -o tsv 2>/dev/null || true)
    if [[ -n "$PEERINGS" ]]; then
        while IFS=$'\t' read -r pname pstate; do
            PEERING_FOUND=true
            if [[ "$pstate" == "Connected" ]]; then
                pass "Peering '$pname' on '$vname' is Connected"
            else
                fail "Peering '$pname' on '$vname' state is '$pstate' (expected Connected)"
            fi
        done <<< "$PEERINGS"
    fi
done <<< "$VNETS_LIST"
[[ "$PEERING_FOUND" == false ]] && skip "No VNet peerings found (may not be required)"

# --- Network Security Groups ---
header "Network Security Groups"
NSG_COUNT=$(az network nsg list -g "$RG_NAME" --query "length([])" -o tsv 2>/dev/null || echo "0")
if [[ "$NSG_COUNT" -gt 0 ]]; then
    pass "Found $NSG_COUNT NSG(s)"

    # Check each NSG has custom rules
    NSGS=$(az network nsg list -g "$RG_NAME" --query "[].name" -o tsv 2>/dev/null || true)
    while IFS= read -r nsg; do
        [[ -z "$nsg" ]] && continue
        RULE_COUNT=$(az network nsg rule list -g "$RG_NAME" --nsg-name "$nsg" \
            --query "length([])" -o tsv 2>/dev/null || echo "0")
        if [[ "$RULE_COUNT" -gt 0 ]]; then
            pass "NSG '$nsg' has $RULE_COUNT custom rule(s)"
        else
            skip "NSG '$nsg' has no custom rules (only defaults)"
        fi
    done <<< "$NSGS"
else
    fail "No NSGs found in $RG_NAME"
fi

# --- Application Security Groups ---
header "Application Security Groups"
ASG_COUNT=$(az network asg list -g "$RG_NAME" --query "length([])" -o tsv 2>/dev/null || echo "0")
if [[ "$ASG_COUNT" -gt 0 ]]; then
    pass "Found $ASG_COUNT ASG(s)"
else
    fail "No ASGs found in $RG_NAME"
fi

# --- Public IP Addresses ---
header "Public IP Addresses"
PIP_COUNT=$(az network public-ip list -g "$RG_NAME" --query "length([])" -o tsv 2>/dev/null || echo "0")
if [[ "$PIP_COUNT" -gt 0 ]]; then
    pass "Found $PIP_COUNT public IP address(es)"
else
    fail "No public IP addresses found in $RG_NAME"
fi

# --- Summary ---
echo -e "\n${BOLD}${CYAN}── Summary ──${NC}"
echo -e "  ${GREEN}Passed: $PASS_COUNT${NC}  ${RED}Failed: $FAIL_COUNT${NC}  ${YELLOW}Skipped: $WARN_COUNT${NC}"
echo ""
[[ $FAIL_COUNT -gt 0 ]] && exit 1 || exit 0
