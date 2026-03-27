#!/usr/bin/env bash
# AZ-104 CertForge Lab — Tool Installer
# Installs required and recommended tools for the lab environment.

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║   AZ-104 CertForge Lab — Tool Installer               ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# ── Detect OS ──
detect_os() {
  case "$(uname -s)" in
    Darwin*)  OS="macos" ;;
    Linux*)   OS="linux" ;;
    *)        error "Unsupported operating system: $(uname -s)"; exit 1 ;;
  esac
  info "Detected OS: ${OS}"
}

# ── Install Azure CLI ──
install_azure_cli() {
  echo ""
  info "── Installing Azure CLI ──"

  if command -v az &>/dev/null; then
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    ok "Azure CLI already installed (v${AZ_VERSION})"
    info "To upgrade, run: ${OS == 'macos' && echo 'brew upgrade azure-cli' || echo 'az upgrade'}"
    return
  fi

  case "$OS" in
    macos)
      if command -v brew &>/dev/null; then
        info "Installing Azure CLI via Homebrew..."
        brew install azure-cli
      else
        error "Homebrew not found. Install Homebrew first: https://brew.sh"
        error "Then run: brew install azure-cli"
        return 1
      fi
      ;;
    linux)
      info "Installing Azure CLI via apt..."
      curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
      ;;
  esac

  if command -v az &>/dev/null; then
    ok "Azure CLI installed successfully"
  else
    error "Azure CLI installation failed"
    return 1
  fi
}

# ── Install Bicep CLI ──
install_bicep() {
  echo ""
  info "── Installing Bicep CLI ──"

  if ! command -v az &>/dev/null; then
    error "Azure CLI required for Bicep installation — install Azure CLI first"
    return 1
  fi

  BICEP_VERSION=$(az bicep version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
  if [ -n "$BICEP_VERSION" ]; then
    ok "Bicep CLI already installed (v${BICEP_VERSION})"
    info "Upgrading to latest version..."
  fi

  az bicep install
  BICEP_VERSION=$(az bicep version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
  ok "Bicep CLI installed (v${BICEP_VERSION})"
}

# ── Install jq ──
install_jq() {
  echo ""
  info "── Installing jq ──"

  if command -v jq &>/dev/null; then
    ok "jq already installed ($(jq --version 2>/dev/null))"
    return
  fi

  case "$OS" in
    macos)
      if command -v brew &>/dev/null; then
        info "Installing jq via Homebrew..."
        brew install jq
      else
        warn "Homebrew not found — install jq manually: https://stedolan.github.io/jq/download/"
        return
      fi
      ;;
    linux)
      info "Installing jq via apt..."
      sudo apt-get update -qq && sudo apt-get install -y -qq jq
      ;;
  esac

  if command -v jq &>/dev/null; then
    ok "jq installed successfully"
  else
    warn "jq installation failed — this is optional but recommended"
  fi
}

# ── Install AzCopy ──
install_azcopy() {
  echo ""
  info "── Installing AzCopy ──"

  if command -v azcopy &>/dev/null; then
    ok "AzCopy already installed"
    return
  fi

  case "$OS" in
    macos)
      if command -v brew &>/dev/null; then
        info "Installing AzCopy via Homebrew..."
        brew install azcopy
      else
        warn "Homebrew not found — download AzCopy from: https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-v10"
        return
      fi
      ;;
    linux)
      info "Downloading AzCopy for Linux..."
      curl -sL https://aka.ms/downloadazcopy-v10-linux -o azcopy_linux.tar.gz
      tar -xzf azcopy_linux.tar.gz --strip-components=1 -C . --wildcards '*/azcopy'
      sudo mv azcopy /usr/local/bin/azcopy
      sudo chmod +x /usr/local/bin/azcopy
      rm -f azcopy_linux.tar.gz
      ;;
  esac

  if command -v azcopy &>/dev/null; then
    ok "AzCopy installed successfully"
  else
    warn "AzCopy installation failed — needed for storage exercises in Module 06"
  fi
}

# ── Azure Login ──
azure_login() {
  echo ""
  info "── Azure Login ──"

  if ! command -v az &>/dev/null; then
    error "Azure CLI not installed — cannot log in"
    return 1
  fi

  if az account show &>/dev/null; then
    ACCOUNT_NAME=$(az account show --query "name" -o tsv 2>/dev/null)
    ok "Already logged in to Azure (subscription: ${ACCOUNT_NAME})"
    read -rp "  Do you want to switch accounts? (y/N): " SWITCH
    if [[ "$SWITCH" =~ ^[Yy]$ ]]; then
      az login
    fi
  else
    info "Opening browser for Azure login..."
    az login
  fi

  if az account show &>/dev/null; then
    ACCOUNT_NAME=$(az account show --query "name" -o tsv 2>/dev/null)
    ok "Logged in to: ${ACCOUNT_NAME}"
  else
    error "Azure login failed"
    return 1
  fi
}

# ── Register Resource Providers ──
register_providers() {
  echo ""
  info "── Registering Resource Providers ──"

  if ! az account show &>/dev/null; then
    error "Not logged in to Azure — cannot register providers"
    return 1
  fi

  PROVIDERS=(
    "Microsoft.Compute"
    "Microsoft.Network"
    "Microsoft.Storage"
    "Microsoft.ContainerInstance"
    "Microsoft.Web"
    "Microsoft.ContainerRegistry"
    "Microsoft.OperationalInsights"
    "Microsoft.RecoveryServices"
  )

  for PROVIDER in "${PROVIDERS[@]}"; do
    STATE=$(az provider show --namespace "$PROVIDER" --query "registrationState" -o tsv 2>/dev/null || echo "Unknown")
    if [ "$STATE" = "Registered" ]; then
      ok "${PROVIDER} — already registered"
    else
      info "Registering ${PROVIDER}..."
      az provider register --namespace "$PROVIDER" --wait 2>/dev/null || true
      ok "${PROVIDER} — registration initiated"
    fi
  done

  info "Provider registration may take a few minutes to complete."
  info "Run ./prerequisites/check-prerequisites.sh to verify."
}

# ── Main ──
main() {
  detect_os
  install_azure_cli
  install_bicep
  install_jq
  install_azcopy
  azure_login
  register_providers

  echo ""
  echo "╔════════════════════════════════════════════════════════╗"
  echo "║   Installation Complete                               ║"
  echo "╠════════════════════════════════════════════════════════╣"
  echo "║   Run the prerequisite check to verify:               ║"
  echo "║   ./prerequisites/check-prerequisites.sh              ║"
  echo "╚════════════════════════════════════════════════════════╝"
  echo ""
}

main "$@"
