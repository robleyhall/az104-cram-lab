#!/usr/bin/env bash
# =============================================================================
# validate-08.sh — Validate Module 08: Monitoring
# Checks: Log Analytics, action groups, alert rules, Recovery vault, backup policy
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

RG_NAME="rg-certlab-monitoring"
PASS_COUNT=0; FAIL_COUNT=0; WARN_COUNT=0

pass() { echo -e "  ${GREEN}✅ PASS${NC} — $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "  ${RED}❌ FAIL${NC} — $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { echo -e "  ${YELLOW}⏭ SKIP${NC} — $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
header(){ echo -e "\n${BOLD}${CYAN}── $* ──${NC}\n"; }

echo -e "\n${BOLD}${CYAN}═══ Validate Module 08: Monitoring ═══${NC}\n"

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

# --- Log Analytics Workspace ---
header "Log Analytics Workspace"
LAW_LIST=$(az monitor log-analytics workspace list -g "$RG_NAME" \
    --query "[].name" -o tsv 2>/dev/null || true)
if [[ -n "$LAW_LIST" ]]; then
    while IFS= read -r law; do
        [[ -z "$law" ]] && continue
        SKU=$(az monitor log-analytics workspace show -g "$RG_NAME" -n "$law" \
            --query "sku.name" -o tsv 2>/dev/null || echo "Unknown")
        RETENTION=$(az monitor log-analytics workspace show -g "$RG_NAME" -n "$law" \
            --query "retentionInDays" -o tsv 2>/dev/null || echo "Unknown")
        pass "Log Analytics workspace '$law' exists (SKU: $SKU, retention: ${RETENTION} days)"
    done <<< "$LAW_LIST"
else
    fail "No Log Analytics workspace found in $RG_NAME"
fi

# --- Action Groups ---
header "Action Groups"
AG_LIST=$(az monitor action-group list -g "$RG_NAME" \
    --query "[].name" -o tsv 2>/dev/null || true)
if [[ -n "$AG_LIST" ]]; then
    while IFS= read -r ag; do
        [[ -z "$ag" ]] && continue
        ENABLED=$(az monitor action-group show -g "$RG_NAME" -n "$ag" \
            --query "enabled" -o tsv 2>/dev/null || echo "Unknown")
        pass "Action group '$ag' exists (enabled: $ENABLED)"

        # Check receivers
        EMAIL_COUNT=$(az monitor action-group show -g "$RG_NAME" -n "$ag" \
            --query "emailReceivers | length([])" -o tsv 2>/dev/null || echo "0")
        SMS_COUNT=$(az monitor action-group show -g "$RG_NAME" -n "$ag" \
            --query "smsReceivers | length([])" -o tsv 2>/dev/null || echo "0")
        TOTAL_RECEIVERS=$((EMAIL_COUNT + SMS_COUNT))
        if [[ "$TOTAL_RECEIVERS" -gt 0 ]]; then
            pass "Action group '$ag' has $TOTAL_RECEIVERS receiver(s) (email: $EMAIL_COUNT, SMS: $SMS_COUNT)"
        else
            skip "Action group '$ag' has no email/SMS receivers (may use other receiver types)"
        fi
    done <<< "$AG_LIST"
else
    fail "No action groups found in $RG_NAME"
fi

# --- Alert Rules ---
header "Alert Rules"
# Metric alerts
METRIC_ALERTS=$(az monitor metrics alert list -g "$RG_NAME" \
    --query "length([])" -o tsv 2>/dev/null || echo "0")
# Activity log alerts
ACTIVITY_ALERTS=$(az monitor activity-log alert list -g "$RG_NAME" \
    --query "length([])" -o tsv 2>/dev/null || echo "0")

TOTAL_ALERTS=$((METRIC_ALERTS + ACTIVITY_ALERTS))
if [[ "$TOTAL_ALERTS" -gt 0 ]]; then
    pass "Found $TOTAL_ALERTS alert rule(s) (metric: $METRIC_ALERTS, activity: $ACTIVITY_ALERTS)"

    # List metric alerts
    if [[ "$METRIC_ALERTS" -gt 0 ]]; then
        ALERT_NAMES=$(az monitor metrics alert list -g "$RG_NAME" \
            --query "[].{name:name, severity:severity, enabled:enabled}" -o tsv 2>/dev/null || true)
        while IFS=$'\t' read -r aname asev aenabled; do
            [[ -z "$aname" ]] && continue
            if [[ "$aenabled" == "true" ]]; then
                pass "Metric alert '$aname' is enabled (severity: $asev)"
            else
                skip "Metric alert '$aname' is disabled"
            fi
        done <<< "$ALERT_NAMES"
    fi
else
    fail "No alert rules found in $RG_NAME"
fi

# --- Recovery Services Vault ---
header "Recovery Services Vault"
VAULT_LIST=$(az backup vault list -g "$RG_NAME" \
    --query "[].name" -o tsv 2>/dev/null || true)
if [[ -n "$VAULT_LIST" ]]; then
    while IFS= read -r vault; do
        [[ -z "$vault" ]] && continue
        pass "Recovery Services vault '$vault' exists"

        # --- Backup Policies ---
        POLICY_COUNT=$(az backup policy list -g "$RG_NAME" -v "$vault" \
            --query "length([])" -o tsv 2>/dev/null || echo "0")
        if [[ "$POLICY_COUNT" -gt 0 ]]; then
            pass "Vault '$vault' has $POLICY_COUNT backup policy(ies)"

            # List policies
            POLICIES=$(az backup policy list -g "$RG_NAME" -v "$vault" \
                --query "[].name" -o tsv 2>/dev/null || true)
            while IFS= read -r pol; do
                [[ -z "$pol" ]] && continue
                pass "Backup policy '$pol' exists"
            done <<< "$POLICIES"
        else
            fail "Vault '$vault' has no backup policies"
        fi
    done <<< "$VAULT_LIST"
else
    fail "No Recovery Services vault found in $RG_NAME"
fi

# --- Summary ---
echo -e "\n${BOLD}${CYAN}── Summary ──${NC}"
echo -e "  ${GREEN}Passed: $PASS_COUNT${NC}  ${RED}Failed: $FAIL_COUNT${NC}  ${YELLOW}Skipped: $WARN_COUNT${NC}"
echo ""
[[ $FAIL_COUNT -gt 0 ]] && exit 1 || exit 0
