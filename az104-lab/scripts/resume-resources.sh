#!/usr/bin/env bash
# =============================================================================
# resume-resources.sh — Start all deallocated VMs/VMSS/AKS in certlab RGs
# Usage: ./scripts/resume-resources.sh [--yes] [--wait]
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
WAIT_FOR_START=false

for arg in "$@"; do
    case "$arg" in
        --yes|-y)  AUTO_CONFIRM=true ;;
        --wait|-w) WAIT_FOR_START=true ;;
        --help|-h)
            echo "Usage: $0 [--yes] [--wait]"
            echo "Starts all deallocated VMs, VMSS, and AKS in rg-certlab-* resource groups."
            echo ""
            echo "Options:"
            echo "  --yes   Skip confirmation prompt"
            echo "  --wait  Wait for all VMs to reach running state"
            exit 0 ;;
    esac
done

header "Resume AZ-104 Lab Resources"

if ! command -v az &>/dev/null; then err "Azure CLI not installed."; exit 1; fi
if ! az account show &>/dev/null 2>&1; then err "Not logged in. Run 'az login'."; exit 1; fi

RG_LIST=$(az group list --query "[?starts_with(name,'rg-certlab-')].name" -o tsv 2>/dev/null || true)
if [[ -z "$RG_LIST" ]]; then
    info "No rg-certlab-* resource groups found."
    exit 0
fi

info "Scanning for deallocated resources..."
echo ""

STOPPED_VMS=()
STOPPED_VMSS=()
STOPPED_AKS=()

while IFS= read -r rg; do
    # VMs — find deallocated ones
    VM_LIST=$(az vm list -g "$rg" --query "[].name" -o tsv 2>/dev/null || true)
    if [[ -n "$VM_LIST" ]]; then
        while IFS= read -r vm_name; do
            STATE=$(az vm get-instance-view -g "$rg" -n "$vm_name" \
                --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv 2>/dev/null || echo "Unknown")
            if [[ "$STATE" == *"deallocated"* ]] || [[ "$STATE" == *"stopped"* ]]; then
                echo -e "  ${YELLOW}VM${NC}   $vm_name ($rg) — ${RED}Deallocated${NC}"
                STOPPED_VMS+=("$rg:$vm_name")
            fi
        done <<< "$VM_LIST"
    fi

    # VMSS
    VMSS_LIST=$(az vmss list -g "$rg" --query "[].name" -o tsv 2>/dev/null || true)
    if [[ -n "$VMSS_LIST" ]]; then
        while IFS= read -r vmss_name; do
            echo -e "  ${YELLOW}VMSS${NC} $vmss_name ($rg)"
            STOPPED_VMSS+=("$rg:$vmss_name")
        done <<< "$VMSS_LIST"
    fi

    # AKS
    AKS_LIST=$(az aks list -g "$rg" --query "[?powerState.code=='Stopped'].name" -o tsv 2>/dev/null || true)
    if [[ -n "$AKS_LIST" ]]; then
        while IFS= read -r aks_name; do
            echo -e "  ${YELLOW}AKS${NC}  $aks_name ($rg) — ${RED}Stopped${NC}"
            STOPPED_AKS+=("$rg:$aks_name")
        done <<< "$AKS_LIST"
    fi
done <<< "$RG_LIST"

VM_COUNT=${#STOPPED_VMS[@]}
VMSS_COUNT=${#STOPPED_VMSS[@]}
AKS_COUNT=${#STOPPED_AKS[@]}
TOTAL=$((VM_COUNT + VMSS_COUNT + AKS_COUNT))

echo ""
info "Found: ${BOLD}${VM_COUNT} VM(s), ${VMSS_COUNT} VMSS, ${AKS_COUNT} AKS cluster(s)${NC} to resume."

if [[ $TOTAL -eq 0 ]]; then
    info "No stopped resources to resume."
    exit 0
fi

if [[ "$AUTO_CONFIRM" != true ]]; then
    echo ""
    echo -e "${YELLOW}${BOLD}Start all resources?${NC} (y/N) "
    read -r REPLY
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        warn "Cancelled."
        exit 0
    fi
fi

header "Starting Resources"

# Start VMs
for entry in "${STOPPED_VMS[@]+"${STOPPED_VMS[@]}"}"; do
    IFS=':' read -r rg name <<< "$entry"
    info "Starting VM: $name..."
    if [[ "$WAIT_FOR_START" == true ]]; then
        if az vm start -g "$rg" -n "$name" 2>/dev/null; then
            ok "VM $name is running."
        else
            err "Failed to start VM $name."
        fi
    else
        if az vm start -g "$rg" -n "$name" --no-wait 2>/dev/null; then
            ok "VM $name start initiated."
        else
            err "Failed to start VM $name."
        fi
    fi
done

# Start VMSS
for entry in "${STOPPED_VMSS[@]+"${STOPPED_VMSS[@]}"}"; do
    IFS=':' read -r rg name <<< "$entry"
    info "Starting VMSS: $name..."
    if az vmss start -g "$rg" -n "$name" --no-wait 2>/dev/null; then
        ok "VMSS $name start initiated."
    else
        err "Failed to start VMSS $name."
    fi
done

# Start AKS
for entry in "${STOPPED_AKS[@]+"${STOPPED_AKS[@]}"}"; do
    IFS=':' read -r rg name <<< "$entry"
    info "Starting AKS cluster: $name..."
    if az aks start -g "$rg" -n "$name" --no-wait 2>/dev/null; then
        ok "AKS $name start initiated."
    else
        err "Failed to start AKS $name."
    fi
done

# --- Wait for running state ---
if [[ "$WAIT_FOR_START" == true ]] && [[ ${#STOPPED_VMS[@]} -gt 0 ]]; then
    header "Waiting for VMs to reach Running state"
    ALL_RUNNING=false
    MAX_WAIT=300
    ELAPSED=0
    INTERVAL=15

    while [[ "$ALL_RUNNING" == false ]] && [[ $ELAPSED -lt $MAX_WAIT ]]; do
        ALL_RUNNING=true
        for entry in "${STOPPED_VMS[@]}"; do
            IFS=':' read -r rg name <<< "$entry"
            STATE=$(az vm get-instance-view -g "$rg" -n "$name" \
                --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv 2>/dev/null || echo "Unknown")
            if [[ "$STATE" != *"running"* ]]; then
                ALL_RUNNING=false
            fi
        done

        if [[ "$ALL_RUNNING" == false ]]; then
            echo -e "  ⏳ Waiting... (${ELAPSED}s / ${MAX_WAIT}s)"
            sleep $INTERVAL
            ELAPSED=$((ELAPSED + INTERVAL))
        fi
    done

    if [[ "$ALL_RUNNING" == true ]]; then
        ok "All VMs are running."
    else
        warn "Timed out waiting for VMs. Some may still be starting."
    fi
fi

# --- Status Summary ---
header "Status Summary"
while IFS= read -r rg; do
    VM_LIST=$(az vm list -g "$rg" --query "[].name" -o tsv 2>/dev/null || true)
    if [[ -n "$VM_LIST" ]]; then
        echo -e "${BOLD}$rg:${NC}"
        while IFS= read -r vm_name; do
            STATE=$(az vm get-instance-view -g "$rg" -n "$vm_name" \
                --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv 2>/dev/null || echo "Unknown")
            if [[ "$STATE" == *"running"* ]]; then
                echo -e "  ${GREEN}●${NC} $vm_name — $STATE"
            else
                echo -e "  ${YELLOW}○${NC} $vm_name — $STATE"
            fi
        done <<< "$VM_LIST"
    fi
done <<< "$RG_LIST"

echo ""
ok "Resume complete! ▶️"
