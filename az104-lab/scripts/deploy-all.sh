#!/usr/bin/env bash
# =============================================================================
# deploy-all.sh — Deploy all AZ-104 lab modules in dependency order
# Usage: ./scripts/deploy-all.sh [--yes] [--continue]
# =============================================================================
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULES_DIR="$LAB_ROOT/modules"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-module.sh"

info()  { echo -e "${BLUE}ℹ ${NC}$*"; }
ok()    { echo -e "${GREEN}✅ ${NC}$*"; }
warn()  { echo -e "${YELLOW}⚠️  ${NC}$*"; }
err()   { echo -e "${RED}❌ ${NC}$*" >&2; }
header(){ echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════${NC}"; \
          echo -e "${BOLD}${CYAN}  $*${NC}"; \
          echo -e "${BOLD}${CYAN}═══════════════════════════════════════${NC}\n"; }

usage() {
    cat <<EOF
${BOLD}Usage:${NC} $0 [--yes] [--continue]

${BOLD}Options:${NC}
  --yes         Skip all confirmation prompts
  --continue    Continue deploying even if a module fails

${BOLD}Deployment Order:${NC}
  Wave 1: 00-foundation
  Wave 2: 01-identity, 02-governance
  Wave 3: 03-networking
  Wave 4: 04-dns-connectivity, 05-load-balancing
  Wave 5: 06-storage, 07-compute
  Wave 6: 08-monitoring
EOF
    exit 1
}

# --- Parse arguments ---
AUTO_CONFIRM=false
CONTINUE_ON_ERROR=false

for arg in "$@"; do
    case "$arg" in
        --yes|-y)      AUTO_CONFIRM=true ;;
        --continue|-c) CONTINUE_ON_ERROR=true ;;
        --help|-h)     usage ;;
        *)             err "Unknown option: $arg"; usage ;;
    esac
done

# Dependency waves — modules within a wave can be deployed in any order
WAVES=(
    "00-foundation"
    "01-identity 02-governance"
    "03-networking"
    "04-dns-connectivity 05-load-balancing"
    "06-storage 07-compute"
    "08-monitoring"
)

WAVE_NAMES=(
    "Foundation"
    "Identity & Governance"
    "Networking"
    "DNS/Connectivity & Load Balancing"
    "Storage & Compute"
    "Monitoring"
)

# --- Pre-flight checks ---
header "AZ-104 Lab — Full Deployment"

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
info "Region:       ${BOLD}${AZ104_REGION:-eastus}${NC}"
echo ""

# Check which modules have main.bicep
DEPLOYABLE=()
SKIPPED=()
for wave in "${WAVES[@]}"; do
    for module in $wave; do
        if [[ -f "$MODULES_DIR/$module/main.bicep" ]]; then
            DEPLOYABLE+=("$module")
        else
            SKIPPED+=("$module")
        fi
    done
done

info "Deployable modules: ${#DEPLOYABLE[@]}"
for m in "${DEPLOYABLE[@]}"; do
    echo -e "  ${GREEN}✓${NC} $m"
done

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    warn "Modules without main.bicep (will be skipped):"
    for m in "${SKIPPED[@]}"; do
        echo -e "  ${YELLOW}○${NC} $m"
    done
fi

echo ""

if [[ ${#DEPLOYABLE[@]} -eq 0 ]]; then
    warn "No deployable modules found. Nothing to do."
    exit 0
fi

if [[ "$AUTO_CONFIRM" != true ]]; then
    echo -e "${YELLOW}${BOLD}Deploy ${#DEPLOYABLE[@]} module(s)?${NC} (y/N) "
    read -r REPLY
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        warn "Deployment cancelled."
        exit 0
    fi
fi

# --- Deploy waves ---
DEPLOY_START=$(date +%s)
SUCCEEDED=()
FAILED=()
WAVE_NUM=0

DEPLOY_FLAGS=()
[[ "$AUTO_CONFIRM" == true ]] && DEPLOY_FLAGS+=(--yes)

for wave in "${WAVES[@]}"; do
    WAVE_NUM=$((WAVE_NUM + 1))
    header "Wave $WAVE_NUM: ${WAVE_NAMES[$((WAVE_NUM - 1))]}"

    for module in $wave; do
        if [[ ! -f "$MODULES_DIR/$module/main.bicep" ]]; then
            warn "Skipping $module (no main.bicep)"
            SKIPPED+=("$module")
            continue
        fi

        info "Deploying $module..."
        echo ""

        if bash "$DEPLOY_SCRIPT" "$module" "${DEPLOY_FLAGS[@]+"${DEPLOY_FLAGS[@]}"}"; then
            SUCCEEDED+=("$module")
            ok "$module deployed successfully."
        else
            FAILED+=("$module")
            err "$module deployment failed!"

            if [[ "$CONTINUE_ON_ERROR" != true ]]; then
                err "Stopping. Use --continue to deploy remaining modules."
                break 2
            else
                warn "Continuing despite failure (--continue flag)..."
            fi
        fi

        echo ""
    done
done

# --- Summary ---
DEPLOY_END=$(date +%s)
TOTAL_DURATION=$(( DEPLOY_END - DEPLOY_START ))

header "Deployment Summary"
echo -e "${BOLD}Total Duration:${NC} ${TOTAL_DURATION}s"
echo ""

if [[ ${#SUCCEEDED[@]} -gt 0 ]]; then
    echo -e "${GREEN}${BOLD}Succeeded (${#SUCCEEDED[@]}):${NC}"
    for m in "${SUCCEEDED[@]}"; do
        echo -e "  ${GREEN}✅${NC} $m"
    done
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    echo -e "${RED}${BOLD}Failed (${#FAILED[@]}):${NC}"
    for m in "${FAILED[@]}"; do
        echo -e "  ${RED}❌${NC} $m"
    done
fi

echo ""

if [[ ${#FAILED[@]} -gt 0 ]]; then
    err "Some deployments failed. Review errors above."
    exit 1
else
    ok "All deployments completed successfully! 🎉"
fi
