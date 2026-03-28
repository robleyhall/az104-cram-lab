#!/usr/bin/env bash
# =============================================================================
# destroy-all.sh — Destroy all AZ-104 lab resource groups in reverse order
# Usage: ./scripts/destroy-all.sh [--yes]
# =============================================================================
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

info()  { echo -e "${BLUE}ℹ ${NC}$*"; }
ok()    { echo -e "${GREEN}✅ ${NC}$*"; }
warn()  { echo -e "${YELLOW}⚠️  ${NC}$*"; }
err()   { echo -e "${RED}❌ ${NC}$*" >&2; }
header(){ echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

usage() {
    cat <<EOF
${BOLD}Usage:${NC} $0 [--yes]

${BOLD}Options:${NC}
  --yes   Skip confirmation prompts (still requires 'DELETE ALL' confirmation)

${BOLD}Description:${NC}
  Destroys all rg-az104-lab-* resource groups in reverse dependency order.
  Optionally cleans up Entra ID objects created by the lab.
EOF
    exit 1
}

AUTO_CONFIRM=false

for arg in "$@"; do
    case "$arg" in
        --yes|-y) AUTO_CONFIRM=true ;;
        --help|-h) usage ;;
        *) err "Unknown option: $arg"; usage ;;
    esac
done

# Reverse dependency order for teardown
REVERSE_ORDER=(
    08-monitoring
    07-compute
    06-storage
    05-load-balancing
    04-dns-connectivity
    03-networking
    02-governance
    01-identity
    00-foundation
)

header "DESTROY ALL AZ-104 Lab Resources"

if ! command -v az &>/dev/null; then
    err "Azure CLI (az) is not installed."
    exit 1
fi

if ! az account show &>/dev/null 2>&1; then
    err "Not logged in to Azure CLI. Run 'az login' first."
    exit 1
fi

SUBSCRIPTION=$(az account show --query "name" -o tsv 2>/dev/null)
info "Subscription: ${BOLD}$SUBSCRIPTION${NC}"
echo ""

# Discover existing az104-lab resource groups
EXISTING_RGS=()
ALL_CERTLAB_RGS=$(az group list --query "[?starts_with(name,'rg-az104-lab-')].name" -o tsv 2>/dev/null || true)

if [[ -z "$ALL_CERTLAB_RGS" ]]; then
    info "No rg-az104-lab-* resource groups found. Nothing to destroy."
    exit 0
fi

echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${RED}${BOLD}║        ⚠️  DESTRUCTIVE OPERATION WARNING ⚠️       ║${NC}"
echo -e "${RED}${BOLD}║  All lab resources will be PERMANENTLY deleted.  ║${NC}"
echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""

warn "The following resource groups will be deleted:"
echo ""
TOTAL_RESOURCES=0
while IFS= read -r rg; do
    COUNT=$(az resource list --resource-group "$rg" --query "length([])" -o tsv 2>/dev/null || echo "0")
    TOTAL_RESOURCES=$((TOTAL_RESOURCES + COUNT))
    echo -e "  ${RED}✗${NC} $rg  (${COUNT} resources)"
    EXISTING_RGS+=("$rg")
done <<< "$ALL_CERTLAB_RGS"

echo ""
warn "${BOLD}Total: ${#EXISTING_RGS[@]} resource group(s), ~${TOTAL_RESOURCES} resource(s)${NC}"
echo ""

# --- Double confirmation ---
echo -e "${RED}${BOLD}Type 'DELETE ALL' to confirm destruction of all lab resources:${NC} "
read -r REPLY
if [[ "$REPLY" != "DELETE ALL" ]]; then
    warn "Input did not match 'DELETE ALL'. Destruction cancelled."
    exit 0
fi

echo ""

# --- Delete resource groups in reverse dependency order ---
header "Deleting Resource Groups"

DELETED=()
for module in "${REVERSE_ORDER[@]}"; do
    MODULE_SHORT="${module#[0-9][0-9]-}"
    RG_NAME="rg-az104-lab-${MODULE_SHORT}"

    if az group show --name "$RG_NAME" &>/dev/null 2>&1; then
        info "Deleting $RG_NAME..."
        if az group delete --name "$RG_NAME" --yes --no-wait 2>/dev/null; then
            ok "$RG_NAME deletion initiated."
            DELETED+=("$RG_NAME")
        else
            err "Failed to delete $RG_NAME."
        fi
    fi
done

# Catch any extra rg-az104-lab-* groups not in the standard list
for rg in "${EXISTING_RGS[@]}"; do
    ALREADY_HANDLED=false
    for d in "${DELETED[@]+"${DELETED[@]}"}"; do
        [[ "$rg" == "$d" ]] && ALREADY_HANDLED=true && break
    done
    if [[ "$ALREADY_HANDLED" == false ]]; then
        info "Deleting extra resource group: $rg..."
        az group delete --name "$rg" --yes --no-wait 2>/dev/null || true
        DELETED+=("$rg")
    fi
done

# --- Entra ID Cleanup ---
header "Entra ID Cleanup"
echo -e "${YELLOW}Would you like to clean up Entra ID objects (users, groups, app registrations)?${NC}"
info "This removes lab users (az104-lab-*), groups, and service principals."
echo ""

if [[ "$AUTO_CONFIRM" == true ]]; then
    RUN_ENTRA_CLEANUP=true
else
    echo -e "${YELLOW}Clean up Entra ID objects?${NC} (y/N) "
    read -r REPLY
    RUN_ENTRA_CLEANUP=false
    [[ "$REPLY" =~ ^[Yy]$ ]] && RUN_ENTRA_CLEANUP=true
fi

if [[ "$RUN_ENTRA_CLEANUP" == true ]]; then
    info "Searching for az104-lab Entra ID objects..."

    # Delete lab users
    LAB_USERS=$(az ad user list --query "[?startsWith(displayName,'az104-lab-') || startsWith(userPrincipalName,'az104-lab-')].id" -o tsv 2>/dev/null || true)
    if [[ -n "$LAB_USERS" ]]; then
        while IFS= read -r uid; do
            az ad user delete --id "$uid" 2>/dev/null && ok "Deleted user: $uid" || warn "Could not delete user: $uid"
        done <<< "$LAB_USERS"
    else
        info "No az104-lab users found."
    fi

    # Delete lab groups
    LAB_GROUPS=$(az ad group list --query "[?startsWith(displayName,'az104-lab-')].id" -o tsv 2>/dev/null || true)
    if [[ -n "$LAB_GROUPS" ]]; then
        while IFS= read -r gid; do
            az ad group delete --group "$gid" 2>/dev/null && ok "Deleted group: $gid" || warn "Could not delete group: $gid"
        done <<< "$LAB_GROUPS"
    else
        info "No az104-lab groups found."
    fi

    # Delete lab app registrations
    LAB_APPS=$(az ad app list --query "[?startsWith(displayName,'az104-lab-')].appId" -o tsv 2>/dev/null || true)
    if [[ -n "$LAB_APPS" ]]; then
        while IFS= read -r appid; do
            az ad app delete --id "$appid" 2>/dev/null && ok "Deleted app: $appid" || warn "Could not delete app: $appid"
        done <<< "$LAB_APPS"
    else
        info "No az104-lab app registrations found."
    fi

    ok "Entra ID cleanup complete."
else
    info "Skipping Entra ID cleanup."
fi

# --- Summary ---
header "Destruction Summary"
echo -e "${BOLD}Resource groups queued for deletion:${NC}"
for rg in "${DELETED[@]}"; do
    echo -e "  ${RED}✗${NC} $rg"
done
echo ""
info "Deletions are running asynchronously. Monitor with:"
echo "  az group list --query \"[?starts_with(name,'rg-az104-lab-')].{Name:name,State:properties.provisioningState}\" -o table"
echo ""
ok "Teardown initiated. 🧹"
