#!/usr/bin/env bash
# =============================================================================
# estimate-cost.sh — Estimate running cost of all certlab resources
# Usage: ./scripts/estimate-cost.sh
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

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "Usage: $0"
            echo "Lists all running resources and estimates hourly/daily cost."
            exit 0 ;;
    esac
done

header "AZ-104 Lab Cost Estimate"

if ! command -v az &>/dev/null; then err "Azure CLI not installed."; exit 1; fi
if ! az account show &>/dev/null 2>&1; then err "Not logged in. Run 'az login'."; exit 1; fi

RG_LIST=$(az group list --query "[?starts_with(name,'rg-certlab-')].name" -o tsv 2>/dev/null || true)
if [[ -z "$RG_LIST" ]]; then
    info "No rg-certlab-* resource groups found. Estimated cost: \$0.00"
    exit 0
fi

# ─── Approximate hourly cost by resource type (East US, pay-as-you-go) ───
# These are rough estimates for common AZ-104 lab sizes
declare -A COST_MAP
COST_MAP["Microsoft.Compute/virtualMachines"]="0.10"
COST_MAP["Microsoft.Compute/virtualMachineScaleSets"]="0.20"
COST_MAP["Microsoft.ContainerService/managedClusters"]="0.30"
COST_MAP["Microsoft.Network/bastionHosts"]="0.19"
COST_MAP["Microsoft.Network/applicationGateways"]="0.25"
COST_MAP["Microsoft.Network/azureFirewalls"]="1.25"
COST_MAP["Microsoft.Network/natGateways"]="0.045"
COST_MAP["Microsoft.Network/publicIPAddresses"]="0.005"
COST_MAP["Microsoft.Network/virtualNetworkGateways"]="0.04"
COST_MAP["Microsoft.Web/sites"]="0.07"
COST_MAP["Microsoft.ContainerInstance/containerGroups"]="0.05"
COST_MAP["Microsoft.ContainerRegistry/registries"]="0.17"
COST_MAP["Microsoft.Sql/servers"]="0.15"
COST_MAP["Microsoft.RecoveryServices/vaults"]="0.00"
COST_MAP["Microsoft.OperationalInsights/workspaces"]="0.00"
COST_MAP["Microsoft.Storage/storageAccounts"]="0.01"
COST_MAP["Microsoft.Network/loadBalancers"]="0.025"
COST_MAP["Microsoft.Network/trafficManagerProfiles"]="0.005"

# Tiers for display
declare -A TIER_MAP
TIER_MAP["Microsoft.Compute/virtualMachines"]="HIGH"
TIER_MAP["Microsoft.Compute/virtualMachineScaleSets"]="HIGH"
TIER_MAP["Microsoft.ContainerService/managedClusters"]="HIGH"
TIER_MAP["Microsoft.Network/bastionHosts"]="HIGH"
TIER_MAP["Microsoft.Network/applicationGateways"]="HIGH"
TIER_MAP["Microsoft.Network/azureFirewalls"]="HIGH"
TIER_MAP["Microsoft.Network/natGateways"]="MEDIUM"
TIER_MAP["Microsoft.Network/virtualNetworkGateways"]="MEDIUM"
TIER_MAP["Microsoft.Web/sites"]="MEDIUM"
TIER_MAP["Microsoft.ContainerInstance/containerGroups"]="MEDIUM"
TIER_MAP["Microsoft.ContainerRegistry/registries"]="MEDIUM"
TIER_MAP["Microsoft.Sql/servers"]="MEDIUM"
TIER_MAP["Microsoft.Network/loadBalancers"]="LOW"
TIER_MAP["Microsoft.Network/publicIPAddresses"]="LOW"
TIER_MAP["Microsoft.Network/trafficManagerProfiles"]="LOW"
TIER_MAP["Microsoft.Storage/storageAccounts"]="LOW"
TIER_MAP["Microsoft.RecoveryServices/vaults"]="FREE"
TIER_MAP["Microsoft.OperationalInsights/workspaces"]="FREE"

tier_color() {
    case "$1" in
        HIGH)   echo -e "${RED}HIGH${NC}" ;;
        MEDIUM) echo -e "${YELLOW}MED${NC}" ;;
        LOW)    echo -e "${GREEN}LOW${NC}" ;;
        FREE)   echo -e "${GREEN}FREE${NC}" ;;
        *)      echo -e "${BLUE}???${NC}" ;;
    esac
}

# --- Scan resources ---
TOTAL_HOURLY=0
FREE_COUNT=0
LOW_COUNT=0
MED_COUNT=0
HIGH_COUNT=0
ALL_RESOURCES=()

printf "\n  %-6s  %-40s  %-44s  %s\n" "TIER" "RESOURCE" "TYPE" "~/HR"
printf "  %-6s  %-40s  %-44s  %s\n" "------" "----------------------------------------" "--------------------------------------------" "------"

while IFS= read -r rg; do
    RESOURCES=$(az resource list -g "$rg" --query "[].{name:name, type:type}" -o tsv 2>/dev/null || true)
    if [[ -n "$RESOURCES" ]]; then
        while IFS=$'\t' read -r name type; do
            HOURLY="${COST_MAP[$type]:-0.00}"
            TIER="${TIER_MAP[$type]:-LOW}"
            TIER_DISPLAY=$(tier_color "$TIER")

            TOTAL_HOURLY=$(echo "$TOTAL_HOURLY + $HOURLY" | bc 2>/dev/null || echo "$TOTAL_HOURLY")

            case "$TIER" in
                FREE)   FREE_COUNT=$((FREE_COUNT + 1)) ;;
                LOW)    LOW_COUNT=$((LOW_COUNT + 1)) ;;
                MEDIUM) MED_COUNT=$((MED_COUNT + 1)) ;;
                HIGH)   HIGH_COUNT=$((HIGH_COUNT + 1)) ;;
            esac

            # Truncate long names for display
            DISPLAY_NAME="${name:0:40}"
            DISPLAY_TYPE="${type:0:44}"

            printf "  %-16s  %-40s  %-44s  \$%s\n" "$TIER_DISPLAY" "$DISPLAY_NAME" "$DISPLAY_TYPE" "$HOURLY"
        done <<< "$RESOURCES"
    fi
done <<< "$RG_LIST"

TOTAL_DAILY=$(echo "$TOTAL_HOURLY * 24" | bc 2>/dev/null || echo "?")
TOTAL_MONTHLY=$(echo "$TOTAL_HOURLY * 730" | bc 2>/dev/null || echo "?")

# --- Summary ---
header "Cost Summary (Estimates)"

echo -e "  ${BOLD}Resources by tier:${NC}"
echo -e "    ${RED}HIGH${NC}:   $HIGH_COUNT resource(s)"
echo -e "    ${YELLOW}MEDIUM${NC}: $MED_COUNT resource(s)"
echo -e "    ${GREEN}LOW${NC}:    $LOW_COUNT resource(s)"
echo -e "    ${GREEN}FREE${NC}:   $FREE_COUNT resource(s)"
echo ""
echo -e "  ${BOLD}Estimated cost (while running):${NC}"
echo -e "    Hourly:  ${BOLD}\$${TOTAL_HOURLY}${NC}"
echo -e "    Daily:   ${BOLD}\$${TOTAL_DAILY}${NC}"
echo -e "    Monthly: ${BOLD}\$${TOTAL_MONTHLY}${NC} (730 hrs)"
echo ""

# --- Optimizations ---
header "Cost Optimization Tips"
echo -e "  ${CYAN}1.${NC} Deallocate VMs when not studying:   ${BOLD}./scripts/pause-resources.sh${NC}"
echo -e "  ${CYAN}2.${NC} Delete Bastion when not needed:     ${BOLD}~\$140/mo savings${NC}"
echo -e "  ${CYAN}3.${NC} Delete Azure Firewall if unused:    ${BOLD}~\$912/mo savings${NC}"
echo -e "  ${CYAN}4.${NC} Use B-series VMs for lab workloads  ${BOLD}(Standard_B1s ~\$7.59/mo)${NC}"
echo -e "  ${CYAN}5.${NC} Destroy modules you're done with:   ${BOLD}./scripts/destroy-module.sh <name>${NC}"
echo -e "  ${CYAN}6.${NC} Set a budget alert in Azure Portal  ${BOLD}(Cost Management > Budgets)${NC}"
echo ""
info "⚠️  Estimates are approximate. Actual costs depend on VM sizes, data transfer, etc."
info "📊 For precise pricing: ${BOLD}https://azure.microsoft.com/en-us/pricing/calculator/${NC}"
echo ""
