#!/usr/bin/env bash
# =============================================================================
# destroy-module.sh — Delete a single AZ-104 lab module's resource group
# Usage: ./scripts/destroy-module.sh <module-name> [--yes]
# =============================================================================
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULES_DIR="$LAB_ROOT/modules"

info()  { echo -e "${BLUE}ℹ ${NC}$*"; }
ok()    { echo -e "${GREEN}✅ ${NC}$*"; }
warn()  { echo -e "${YELLOW}⚠️  ${NC}$*"; }
err()   { echo -e "${RED}❌ ${NC}$*" >&2; }
header(){ echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

usage() {
    cat <<EOF
${BOLD}Usage:${NC} $0 <module-name> [--yes]

${BOLD}Arguments:${NC}
  module-name   Module directory name (e.g., 03-networking)

${BOLD}Options:${NC}
  --yes         Skip confirmation prompt

${BOLD}Examples:${NC}
  $0 06-storage
  $0 03-networking --yes
EOF
    exit 1
}

# --- Parse arguments ---
MODULE_NAME=""
AUTO_CONFIRM=false

for arg in "$@"; do
    case "$arg" in
        --yes|-y) AUTO_CONFIRM=true ;;
        --help|-h) usage ;;
        -*) err "Unknown option: $arg"; usage ;;
        *) MODULE_NAME="$arg" ;;
    esac
done

[[ -z "$MODULE_NAME" ]] && { err "Module name is required."; usage; }

MODULE_SHORT="${MODULE_NAME#[0-9][0-9]-}"
RG_NAME="rg-az104-lab-${MODULE_SHORT}"

# --- Validate ---
header "Destroy Module: $MODULE_NAME"

if [[ ! -d "$MODULES_DIR/$MODULE_NAME" ]]; then
    err "Module directory not found: $MODULES_DIR/$MODULE_NAME"
    info "Available modules:"
    ls -1 "$MODULES_DIR" | sed 's/^/  /'
    exit 1
fi

if ! command -v az &>/dev/null; then
    err "Azure CLI (az) is not installed."
    exit 1
fi

if ! az account show &>/dev/null 2>&1; then
    err "Not logged in to Azure CLI. Run 'az login' first."
    exit 1
fi

# Check if RG exists
if ! az group show --name "$RG_NAME" &>/dev/null 2>&1; then
    warn "Resource group '$RG_NAME' does not exist. Nothing to destroy."
    exit 0
fi

# List resources that will be deleted
info "Resource group: ${BOLD}$RG_NAME${NC}"
echo ""
warn "The following resources will be ${RED}${BOLD}PERMANENTLY DELETED${NC}:"
echo ""
az resource list --resource-group "$RG_NAME" \
    --query "[].{Name:name, Type:type}" -o table 2>/dev/null || true
echo ""

RESOURCE_COUNT=$(az resource list --resource-group "$RG_NAME" --query "length([])" -o tsv 2>/dev/null || echo "0")
warn "${RED}${BOLD}$RESOURCE_COUNT resource(s)${NC} will be deleted. ${RED}This cannot be undone!${NC}"
echo ""

# --- Confirm ---
if [[ "$AUTO_CONFIRM" != true ]]; then
    echo -e "${RED}${BOLD}Type the resource group name to confirm deletion:${NC} "
    read -r REPLY
    if [[ "$REPLY" != "$RG_NAME" ]]; then
        warn "Input did not match. Destruction cancelled."
        exit 0
    fi
fi

# --- Delete ---
info "Deleting resource group '$RG_NAME' (async)..."
if az group delete --name "$RG_NAME" --yes --no-wait; then
    ok "Resource group deletion initiated for '$RG_NAME'."
    info "Deletion runs in the background. Monitor with:"
    echo "  az group show --name $RG_NAME --query properties.provisioningState -o tsv"
else
    err "Failed to initiate deletion of '$RG_NAME'."
    exit 1
fi

echo ""
ok "Done! Resource group '$RG_NAME' is being deleted."
