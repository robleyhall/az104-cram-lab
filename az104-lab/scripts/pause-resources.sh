#!/usr/bin/env bash
# =============================================================================
# pause-resources.sh — Deallocate/stop costly resources in az104-lab RGs
# Usage: ./scripts/pause-resources.sh [--yes]
# =============================================================================
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${BLUE}ℹ ${NC}$*"; }
ok()    { echo -e "${GREEN}✅ ${NC}$*"; }
warn()  { echo -e "${YELLOW}⚠️  ${NC}$*"; }
err()   { echo -e "${RED}❌ ${NC}$*" >&2; }
header(){ echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

AUTO_CONFIRM=false
for arg in "$@"; do
    case "$arg" in
        --yes|-y) AUTO_CONFIRM=true ;;
        --help|-h)
            echo "Usage: $0 [--yes]"
            echo "Deallocates VMs, stops VMSS, stops AKS in all rg-az104-lab-* resource groups."
            exit 0 ;;
    esac
done

header "Pause AZ-104 Lab Resources"

if ! command -v az &>/dev/null; then err "Azure CLI not installed."; exit 1; fi
if ! az account show &>/dev/null 2>&1; then err "Not logged in. Run 'az login'."; exit 1; fi

# Gather all az104-lab resource groups
RG_LIST=$(az group list --query "[?starts_with(name,'rg-az104-lab-')].name" -o tsv 2>/dev/null || true)
if [[ -z "$RG_LIST" ]]; then
    info "No rg-az104-lab-* resource groups found."
    exit 0
fi

info "Scanning resource groups for running resources..."
echo ""

VM_COUNT=0
VMSS_COUNT=0
AKS_COUNT=0
PAUSED_VMS=()
PAUSED_VMSS=()
PAUSED_AKS=()
UNPAUSABLE=()

# --- Scan VMs ---
while IFS= read -r rg; do
    # VMs
    RUNNING_VMS=$(az vm list -g "$rg" --query "[?powerState=='VM running' || powerState==null].{Name:name,RG:resourceGroup}" -o tsv 2>/dev/null || true)
    if [[ -n "$RUNNING_VMS" ]]; then
        while IFS=$'\t' read -r vm_name vm_rg; do
            # Double-check power state
            STATE=$(az vm get-instance-view -g "$rg" -n "$vm_name" --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv 2>/dev/null || echo "Unknown")
            if [[ "$STATE" == *"running"* ]]; then
                echo -e "  ${BLUE}VM${NC}   $vm_name ($rg) — ${GREEN}Running${NC}"
                PAUSED_VMS+=("$rg:$vm_name")
                VM_COUNT=$((VM_COUNT + 1))
            fi
        done <<< "$RUNNING_VMS"
    fi

    # VMSS
    VMSS_LIST=$(az vmss list -g "$rg" --query "[].name" -o tsv 2>/dev/null || true)
    if [[ -n "$VMSS_LIST" ]]; then
        while IFS= read -r vmss_name; do
            echo -e "  ${BLUE}VMSS${NC} $vmss_name ($rg)"
            PAUSED_VMSS+=("$rg:$vmss_name")
            VMSS_COUNT=$((VMSS_COUNT + 1))
        done <<< "$VMSS_LIST"
    fi

    # AKS
    AKS_LIST=$(az aks list -g "$rg" --query "[?powerState.code=='Running'].name" -o tsv 2>/dev/null || true)
    if [[ -n "$AKS_LIST" ]]; then
        while IFS= read -r aks_name; do
            echo -e "  ${BLUE}AKS${NC}  $aks_name ($rg)"
            PAUSED_AKS+=("$rg:$aks_name")
            AKS_COUNT=$((AKS_COUNT + 1))
        done <<< "$AKS_LIST"
    fi

    # Unpausable resources (still incur cost when "stopped")
    BASTION=$(az resource list -g "$rg" --resource-type "Microsoft.Network/bastionHosts" --query "[].name" -o tsv 2>/dev/null || true)
    APPGW=$(az resource list -g "$rg" --resource-type "Microsoft.Network/applicationGateways" --query "[].name" -o tsv 2>/dev/null || true)
    FWALL=$(az resource list -g "$rg" --resource-type "Microsoft.Network/azureFirewalls" --query "[].name" -o tsv 2>/dev/null || true)
    NATGW=$(az resource list -g "$rg" --resource-type "Microsoft.Network/natGateways" --query "[].name" -o tsv 2>/dev/null || true)

    for r in $BASTION; do UNPAUSABLE+=("Bastion: $r ($rg) ~\$0.19/hr"); done
    for r in $APPGW;   do UNPAUSABLE+=("App Gateway: $r ($rg) ~\$0.25/hr"); done
    for r in $FWALL;   do UNPAUSABLE+=("Firewall: $r ($rg) ~\$1.25/hr"); done
    for r in $NATGW;   do UNPAUSABLE+=("NAT Gateway: $r ($rg) ~\$0.045/hr"); done

done <<< "$RG_LIST"

TOTAL=$((VM_COUNT + VMSS_COUNT + AKS_COUNT))
echo ""
info "Found: ${BOLD}${VM_COUNT} VM(s), ${VMSS_COUNT} VMSS, ${AKS_COUNT} AKS cluster(s)${NC}"

if [[ $TOTAL -eq 0 ]]; then
    info "No running compute resources to pause."
else
    # Estimated savings (rough hourly costs)
    EST_VM_SAVINGS=$(echo "$VM_COUNT * 0.10" | bc 2>/dev/null || echo "?")
    EST_VMSS_SAVINGS=$(echo "$VMSS_COUNT * 0.20" | bc 2>/dev/null || echo "?")
    EST_AKS_SAVINGS=$(echo "$AKS_COUNT * 0.30" | bc 2>/dev/null || echo "?")
    echo ""
    info "${BOLD}Estimated hourly savings:${NC}"
    echo -e "  VMs:  ~\$${EST_VM_SAVINGS}/hr (per VM avg)"
    echo -e "  VMSS: ~\$${EST_VMSS_SAVINGS}/hr (per scale set avg)"
    echo -e "  AKS:  ~\$${EST_AKS_SAVINGS}/hr (per cluster avg)"
    echo ""

    if [[ "$AUTO_CONFIRM" != true ]]; then
        echo -e "${YELLOW}${BOLD}Pause all resources?${NC} (y/N) "
        read -r REPLY
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            warn "Cancelled."
            exit 0
        fi
    fi

    header "Deallocating Resources"

    # Deallocate VMs
    for entry in "${PAUSED_VMS[@]+"${PAUSED_VMS[@]}"}"; do
        IFS=':' read -r rg name <<< "$entry"
        info "Deallocating VM: $name..."
        if az vm deallocate -g "$rg" -n "$name" --no-wait 2>/dev/null; then
            ok "VM $name deallocate initiated."
        else
            err "Failed to deallocate VM $name."
        fi
    done

    # Stop VMSS instances
    for entry in "${PAUSED_VMSS[@]+"${PAUSED_VMSS[@]}"}"; do
        IFS=':' read -r rg name <<< "$entry"
        info "Deallocating VMSS: $name..."
        if az vmss deallocate -g "$rg" -n "$name" --no-wait 2>/dev/null; then
            ok "VMSS $name deallocate initiated."
        else
            err "Failed to deallocate VMSS $name."
        fi
    done

    # Stop AKS
    for entry in "${PAUSED_AKS[@]+"${PAUSED_AKS[@]}"}"; do
        IFS=':' read -r rg name <<< "$entry"
        info "Stopping AKS cluster: $name..."
        if az aks stop -g "$rg" -n "$name" --no-wait 2>/dev/null; then
            ok "AKS $name stop initiated."
        else
            err "Failed to stop AKS $name."
        fi
    done
fi

# --- Unpausable resources ---
if [[ ${#UNPAUSABLE[@]} -gt 0 ]]; then
    header "Resources That Cannot Be Paused"
    warn "These resources incur cost even when idle. Consider deleting them:"
    echo ""
    for r in "${UNPAUSABLE[@]}"; do
        echo -e "  ${YELLOW}💰${NC} $r"
    done
    echo ""
    info "To delete, use: az resource delete --ids <resource-id>"
    info "Or destroy the entire module: ./scripts/destroy-module.sh <module>"
fi

echo ""
ok "Pause complete. Resources are being deallocated. 💤"
info "Resume later with: ./scripts/resume-resources.sh"
