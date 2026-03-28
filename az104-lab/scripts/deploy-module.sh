#!/usr/bin/env bash
# =============================================================================
# deploy-module.sh — Deploy a single AZ-104 lab module
# Usage: ./scripts/deploy-module.sh <module-name> [--yes]
# Example: ./scripts/deploy-module.sh 03-networking
#          ./scripts/deploy-module.sh 00-foundation --yes
# =============================================================================
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULES_DIR="$LAB_ROOT/modules"
REGION="${AZ104_REGION:-eastus}"

# --- Functions ---
info()  { echo -e "${BLUE}ℹ ${NC}$*"; }
ok()    { echo -e "${GREEN}✅ ${NC}$*"; }
warn()  { echo -e "${YELLOW}⚠️  ${NC}$*"; }
err()   { echo -e "${RED}❌ ${NC}$*" >&2; }
header(){ echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

usage() {
    cat <<EOF
${BOLD}Usage:${NC} $0 <module-name> [--yes]

${BOLD}Arguments:${NC}
  module-name   Module directory name (e.g., 03-networking, 00-foundation)

${BOLD}Options:${NC}
  --yes         Skip confirmation prompts

${BOLD}Examples:${NC}
  $0 00-foundation
  $0 03-networking --yes

${BOLD}Environment:${NC}
  AZ104_REGION  Override default region (default: eastus)
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

# --- Derive names ---
# Strip leading number prefix for resource group name (e.g., 03-networking → networking)
MODULE_SHORT="${MODULE_NAME#[0-9][0-9]-}"
RG_NAME="rg-az104-lab-${MODULE_SHORT}"
MODULE_DIR="$MODULES_DIR/$MODULE_NAME"

# --- Validate ---
header "Deploying Module: $MODULE_NAME"

if [[ ! -d "$MODULE_DIR" ]]; then
    err "Module directory not found: $MODULE_DIR"
    info "Available modules:"
    ls -1 "$MODULES_DIR" | sed 's/^/  /'
    exit 1
fi

BICEP_FILE="$MODULE_DIR/main.bicep"
if [[ ! -f "$BICEP_FILE" ]]; then
    err "No main.bicep found in $MODULE_DIR"
    warn "This module may not be implemented yet."
    exit 1
fi

# Check az CLI is available and logged in
if ! command -v az &>/dev/null; then
    err "Azure CLI (az) is not installed. Install from https://aka.ms/installazurecli"
    exit 1
fi

if ! az account show &>/dev/null 2>&1; then
    err "Not logged in to Azure CLI. Run 'az login' first."
    exit 1
fi

SUBSCRIPTION=$(az account show --query "name" -o tsv 2>/dev/null)
info "Subscription: ${BOLD}$SUBSCRIPTION${NC}"
info "Region:       ${BOLD}$REGION${NC}"
info "Module:       ${BOLD}$MODULE_NAME${NC}"
info "Resource Group: ${BOLD}$RG_NAME${NC}"
echo ""

# --- Create Resource Group ---
header "Step 1: Resource Group"

if az group show --name "$RG_NAME" &>/dev/null 2>&1; then
    ok "Resource group '$RG_NAME' already exists."
else
    info "Creating resource group '$RG_NAME' in '$REGION'..."
    az group create --name "$RG_NAME" --location "$REGION" \
        --tags Environment=az104-lab Project=az104-lab Module="$MODULE_SHORT" \
        -o none
    ok "Resource group '$RG_NAME' created."
fi

# --- Build deployment command ---
DEPLOY_ARGS=(
    --resource-group "$RG_NAME"
    --template-file "$BICEP_FILE"
    --name "deploy-${MODULE_SHORT}-$(date +%Y%m%d-%H%M%S)"
)

# Use .bicepparam if available, fall back to .parameters.json
PARAM_FILE_BICEP="$MODULE_DIR/main.bicepparam"
PARAM_FILE_JSON="$MODULE_DIR/main.parameters.json"
if [[ -f "$PARAM_FILE_BICEP" ]]; then
    DEPLOY_ARGS+=(--parameters "$PARAM_FILE_BICEP")
    info "Using parameters file: main.bicepparam"
elif [[ -f "$PARAM_FILE_JSON" ]]; then
    DEPLOY_ARGS+=(--parameters "@$PARAM_FILE_JSON")
    info "Using parameters file: main.parameters.json"
else
    info "No parameters file found; using template defaults."
fi

# --- What-If ---
header "Step 2: What-If Preview"
info "Running deployment preview..."
echo ""

if ! az deployment group what-if "${DEPLOY_ARGS[@]}" 2>&1; then
    warn "What-if completed with warnings (this is often normal)."
fi

echo ""

# --- Confirm ---
if [[ "$AUTO_CONFIRM" != true ]]; then
    echo -e "${YELLOW}${BOLD}Proceed with deployment?${NC} (y/N) "
    read -r REPLY
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        warn "Deployment cancelled."
        exit 0
    fi
fi

# --- Deploy ---
header "Step 3: Deploying"
info "Starting deployment..."

DEPLOY_START=$(date +%s)

if az deployment group create "${DEPLOY_ARGS[@]}" -o table; then
    DEPLOY_END=$(date +%s)
    DURATION=$(( DEPLOY_END - DEPLOY_START ))
    ok "Deployment succeeded in ${DURATION}s."
else
    err "Deployment failed!"
    info "Check the Azure portal for details, or run:"
    echo "  az deployment group list --resource-group $RG_NAME -o table"
    exit 1
fi

# --- Entra Setup ---
ENTRA_SCRIPT="$MODULE_DIR/entra-setup.sh"
if [[ -f "$ENTRA_SCRIPT" ]]; then
    header "Step 4: Entra ID Setup"
    info "Found entra-setup.sh for this module."

    if [[ "$AUTO_CONFIRM" == true ]]; then
        RUN_ENTRA=true
    else
        echo -e "${YELLOW}Run Entra ID setup script?${NC} (y/N) "
        read -r REPLY
        RUN_ENTRA=false
        [[ "$REPLY" =~ ^[Yy]$ ]] && RUN_ENTRA=true
    fi

    if [[ "$RUN_ENTRA" == true ]]; then
        info "Running entra-setup.sh..."
        chmod +x "$ENTRA_SCRIPT"
        if bash "$ENTRA_SCRIPT"; then
            ok "Entra ID setup completed."
        else
            warn "Entra ID setup had errors. Check output above."
        fi
    else
        info "Skipping Entra ID setup. Run manually later:"
        echo "  bash $ENTRA_SCRIPT"
    fi
fi

# --- Summary ---
header "Deployment Summary"
echo -e "${BOLD}Module:${NC}         $MODULE_NAME"
echo -e "${BOLD}Resource Group:${NC} $RG_NAME"
echo -e "${BOLD}Region:${NC}         $REGION"
echo -e "${BOLD}Duration:${NC}       ${DURATION}s"
echo ""
info "Resources deployed:"
az resource list --resource-group "$RG_NAME" --query "[].{Name:name, Type:type, Location:location}" -o table 2>/dev/null || true
echo ""
ok "Done! 🎉"
