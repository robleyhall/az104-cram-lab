#!/usr/bin/env bash
# =============================================================================
# validate-07.sh — Validate Module 07: Compute
# Checks: VMs, VMSS, ACR, ACI, App Service + staging slot
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

RG_NAME="rg-az104-lab-compute"
PASS_COUNT=0; FAIL_COUNT=0; WARN_COUNT=0

pass() { echo -e "  ${GREEN}✅ PASS${NC} — $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "  ${RED}❌ FAIL${NC} — $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { echo -e "  ${YELLOW}⏭ SKIP${NC} — $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
header(){ echo -e "\n${BOLD}${CYAN}── $* ──${NC}\n"; }

echo -e "\n${BOLD}${CYAN}═══ Validate Module 07: Compute ═══${NC}\n"

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

# --- Virtual Machines ---
header "Virtual Machines"
VM_LIST=$(az vm list -g "$RG_NAME" --query "[].name" -o tsv 2>/dev/null || true)
if [[ -n "$VM_LIST" ]]; then
    VM_COUNT=$(echo "$VM_LIST" | wc -l | tr -d ' ')
    pass "Found $VM_COUNT VM(s)"

    while IFS= read -r vm; do
        [[ -z "$vm" ]] && continue
        STATE=$(az vm get-instance-view -g "$RG_NAME" -n "$vm" \
            --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" \
            -o tsv 2>/dev/null || echo "Unknown")
        if [[ "$STATE" == *"running"* ]]; then
            pass "VM '$vm' is running"
        elif [[ "$STATE" == *"deallocated"* ]]; then
            skip "VM '$vm' is deallocated (run resume-resources.sh to start)"
        else
            fail "VM '$vm' power state: $STATE"
        fi
    done <<< "$VM_LIST"
else
    fail "No VMs found in $RG_NAME"
fi

# --- Virtual Machine Scale Sets ---
header "Virtual Machine Scale Sets"
VMSS_LIST=$(az vmss list -g "$RG_NAME" --query "[].{name:name, capacity:sku.capacity}" -o tsv 2>/dev/null || true)
if [[ -n "$VMSS_LIST" ]]; then
    while IFS=$'\t' read -r vmss_name vmss_cap; do
        [[ -z "$vmss_name" ]] && continue
        pass "VMSS '$vmss_name' exists (capacity: $vmss_cap)"

        if [[ "$vmss_cap" -gt 0 ]]; then
            pass "VMSS '$vmss_name' has $vmss_cap instance(s)"
        else
            fail "VMSS '$vmss_name' has 0 instances"
        fi
    done <<< "$VMSS_LIST"
else
    fail "No VMSS found in $RG_NAME"
fi

# --- Azure Container Registry ---
header "Azure Container Registry"
ACR_LIST=$(az acr list -g "$RG_NAME" --query "[].name" -o tsv 2>/dev/null || true)
if [[ -n "$ACR_LIST" ]]; then
    while IFS= read -r acr; do
        [[ -z "$acr" ]] && continue
        SKU=$(az acr show -g "$RG_NAME" -n "$acr" --query "sku.name" -o tsv 2>/dev/null || echo "Unknown")
        pass "ACR '$acr' exists (SKU: $SKU)"
    done <<< "$ACR_LIST"
else
    fail "No Azure Container Registry found in $RG_NAME"
fi

# --- Azure Container Instances ---
header "Azure Container Instances"
ACI_LIST=$(az container list -g "$RG_NAME" --query "[].name" -o tsv 2>/dev/null || true)
if [[ -n "$ACI_LIST" ]]; then
    while IFS= read -r aci; do
        [[ -z "$aci" ]] && continue
        ACI_STATE=$(az container show -g "$RG_NAME" -n "$aci" \
            --query "instanceView.state" -o tsv 2>/dev/null || echo "Unknown")
        pass "ACI '$aci' exists (state: $ACI_STATE)"
    done <<< "$ACI_LIST"
else
    fail "No Azure Container Instances found in $RG_NAME"
fi

# --- App Service ---
header "App Service"
APP_LIST=$(az webapp list -g "$RG_NAME" --query "[].name" -o tsv 2>/dev/null || true)
if [[ -n "$APP_LIST" ]]; then
    while IFS= read -r app; do
        [[ -z "$app" ]] && continue
        APP_STATE=$(az webapp show -g "$RG_NAME" -n "$app" --query "state" -o tsv 2>/dev/null || echo "Unknown")
        pass "App Service '$app' exists (state: $APP_STATE)"

        # Check for staging slot
        SLOT_COUNT=$(az webapp deployment slot list -g "$RG_NAME" -n "$app" \
            --query "length([])" -o tsv 2>/dev/null || echo "0")
        if [[ "$SLOT_COUNT" -gt 0 ]]; then
            SLOTS=$(az webapp deployment slot list -g "$RG_NAME" -n "$app" \
                --query "[].name" -o tsv 2>/dev/null || true)
            pass "App Service '$app' has $SLOT_COUNT deployment slot(s): $SLOTS"

            # Check specifically for staging
            HAS_STAGING=$(az webapp deployment slot list -g "$RG_NAME" -n "$app" \
                --query "[?name=='staging'] | length([])" -o tsv 2>/dev/null || echo "0")
            if [[ "$HAS_STAGING" -gt 0 ]]; then
                pass "App Service '$app' has a 'staging' slot"
            else
                fail "App Service '$app' has no 'staging' slot"
            fi
        else
            fail "App Service '$app' has no deployment slots"
        fi
    done <<< "$APP_LIST"
else
    fail "No App Services found in $RG_NAME"
fi

# --- Summary ---
echo -e "\n${BOLD}${CYAN}── Summary ──${NC}"
echo -e "  ${GREEN}Passed: $PASS_COUNT${NC}  ${RED}Failed: $FAIL_COUNT${NC}  ${YELLOW}Skipped: $WARN_COUNT${NC}"
echo ""
[[ $FAIL_COUNT -gt 0 ]] && exit 1 || exit 0
