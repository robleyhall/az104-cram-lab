#!/usr/bin/env bash
# ================================================================
# Module 01: Identity & Entra ID — Entra Setup Script
# AZ-104 CertForge Lab
# ================================================================
# This script creates demo users, groups, and RBAC assignments
# using Azure CLI.  Run it BEFORE deploying main.bicep so you
# can feed the group object IDs into the Bicep parameter file.
#
# Prerequisites:
#   • Azure CLI >= 2.50  (az --version)
#   • Logged-in with sufficient Entra ID privileges
#     (User Administrator + RBAC Administrator or higher)
#   • A resource group already created for the lab
#
# Usage:
#   export DOMAIN_NAME="yourtenant.onmicrosoft.com"
#   export RESOURCE_GROUP="rg-az104-certlab-identity"
#   bash entra-setup.sh
# ================================================================

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────

: "${DOMAIN_NAME:?'Set DOMAIN_NAME to your Entra ID tenant domain (e.g. contoso.onmicrosoft.com)'}"
: "${RESOURCE_GROUP:?'Set RESOURCE_GROUP to the target resource group name'}"

PASSWORD="CertLab@2024!"   # Demo-only — change or randomise for real use
PREFIX="certlab"

# Colours for output
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Helper: idempotent user creation ─────────────────────────────

create_user() {
  local display_name="$1"
  local upn="${2}@${DOMAIN_NAME}"
  local password="$3"

  existing_id=$(az ad user list --filter "userPrincipalName eq '${upn}'" --query "[0].id" -o tsv 2>/dev/null || true)

  if [[ -n "$existing_id" ]]; then
    warn "User ${upn} already exists (${existing_id}) — skipping creation."
    echo "$existing_id"
    return
  fi

  info "Creating user: ${upn}"
  user_id=$(az ad user create \
    --display-name "$display_name" \
    --user-principal-name "$upn" \
    --password "$password" \
    --force-change-password-next-sign-in false \
    --query id -o tsv)

  echo "$user_id"
}

# ── Helper: idempotent group creation ────────────────────────────

create_group() {
  local display_name="$1"
  local mail_nickname="$2"
  local description="$3"

  existing_id=$(az ad group list --filter "displayName eq '${display_name}'" --query "[0].id" -o tsv 2>/dev/null || true)

  if [[ -n "$existing_id" ]]; then
    warn "Group ${display_name} already exists (${existing_id}) — skipping creation."
    echo "$existing_id"
    return
  fi

  info "Creating group: ${display_name}"
  group_id=$(az ad group create \
    --display-name "$display_name" \
    --mail-nickname "$mail_nickname" \
    --description "$description" \
    --query id -o tsv)

  echo "$group_id"
}

# ── Helper: idempotent group member add ──────────────────────────

add_member() {
  local group_id="$1"
  local member_id="$2"
  local label="$3"

  is_member=$(az ad group member check --group "$group_id" --member-id "$member_id" --query value -o tsv 2>/dev/null || true)

  if [[ "$is_member" == "true" ]]; then
    warn "${label} is already a member — skipping."
    return
  fi

  info "Adding ${label} to group ${group_id}"
  az ad group member add --group "$group_id" --member-id "$member_id"
}

# ── Helper: idempotent RBAC role assignment ──────────────────────

assign_role() {
  local role="$1"
  local assignee_object_id="$2"
  local scope="$3"
  local label="$4"

  existing=$(az role assignment list \
    --assignee "$assignee_object_id" \
    --role "$role" \
    --scope "$scope" \
    --query "[0].id" -o tsv 2>/dev/null || true)

  if [[ -n "$existing" ]]; then
    warn "Role '${role}' already assigned to ${label} — skipping."
    return
  fi

  info "Assigning role '${role}' to ${label} on scope ${scope}"
  az role assignment create \
    --role "$role" \
    --assignee-object-id "$assignee_object_id" \
    --assignee-principal-type Group \
    --scope "$scope" \
    --output none
}

# ================================================================
# 1. CREATE USERS
# ================================================================

info "=== Creating demo users ==="

USER1_ID=$(create_user "CertLab User1"  "${PREFIX}-user1"  "$PASSWORD")
USER2_ID=$(create_user "CertLab User2"  "${PREFIX}-user2"  "$PASSWORD")
ADMIN_ID=$(create_user "CertLab Admin"  "${PREFIX}-admin"  "$PASSWORD")
READER_ID=$(create_user "CertLab Reader" "${PREFIX}-reader" "$PASSWORD")

echo ""
info "User IDs:"
info "  ${PREFIX}-user1  : ${USER1_ID}"
info "  ${PREFIX}-user2  : ${USER2_ID}"
info "  ${PREFIX}-admin  : ${ADMIN_ID}"
info "  ${PREFIX}-reader : ${READER_ID}"
echo ""

# ================================================================
# 2. CREATE GROUPS
# ================================================================

info "=== Creating demo groups ==="

ADMINS_GROUP_ID=$(create_group "${PREFIX}-admins"     "${PREFIX}-admins"     "AZ-104 Lab — Admins group (assigned membership)")
READERS_GROUP_ID=$(create_group "${PREFIX}-readers"    "${PREFIX}-readers"    "AZ-104 Lab — Readers group (assigned membership)")
DEVS_GROUP_ID=$(create_group "${PREFIX}-developers"    "${PREFIX}-developers" "AZ-104 Lab — Developers group (assigned membership)")

echo ""
info "Group IDs:"
info "  ${PREFIX}-admins     : ${ADMINS_GROUP_ID}"
info "  ${PREFIX}-readers    : ${READERS_GROUP_ID}"
info "  ${PREFIX}-developers : ${DEVS_GROUP_ID}"
echo ""

# ================================================================
# 3. ADD USERS TO GROUPS
# ================================================================

info "=== Adding users to groups ==="

add_member "$ADMINS_GROUP_ID"  "$ADMIN_ID"  "${PREFIX}-admin → ${PREFIX}-admins"
add_member "$READERS_GROUP_ID" "$READER_ID" "${PREFIX}-reader → ${PREFIX}-readers"
add_member "$READERS_GROUP_ID" "$USER1_ID"  "${PREFIX}-user1 → ${PREFIX}-readers"
add_member "$DEVS_GROUP_ID"    "$USER1_ID"  "${PREFIX}-user1 → ${PREFIX}-developers"
add_member "$DEVS_GROUP_ID"    "$USER2_ID"  "${PREFIX}-user2 → ${PREFIX}-developers"

echo ""

# ================================================================
# 4. RBAC ROLE ASSIGNMENTS
# ================================================================

info "=== Assigning RBAC roles ==="

RG_SCOPE=$(az group show --name "$RESOURCE_GROUP" --query id -o tsv)

assign_role "Contributor" "$ADMINS_GROUP_ID"  "$RG_SCOPE" "${PREFIX}-admins"
assign_role "Reader"      "$READERS_GROUP_ID" "$RG_SCOPE" "${PREFIX}-readers"

echo ""

# ================================================================
# 5. SSPR CONFIGURATION (INFORMATIONAL)
# ================================================================

cat <<'SSPR_NOTE'

══════════════════════════════════════════════════════════════════
 SELF-SERVICE PASSWORD RESET (SSPR) — Manual / Portal Steps
══════════════════════════════════════════════════════════════════

 ⚠  SSPR configuration requires an Entra ID P1 or P2 license.
    Free-tier tenants can only enable SSPR for administrators.

 Portal path:
   Entra admin center → Protection → Password reset

 Key settings to explore:
   • Properties  — Enable SSPR for "All" or "Selected" group
   • Authentication methods — Number required (1 or 2),
     methods available (Email, Phone, Security questions,
     Microsoft Authenticator, etc.)
   • Registration — Require users to register on sign-in
   • Notifications — Notify users / admins on password reset

 CLI reference (read-only query — modification requires Graph API):
   az rest --method GET \
     --url "https://graph.microsoft.com/v1.0/policies/authenticationMethodsPolicy"

 To enable SSPR via Microsoft Graph (requires appropriate permissions):
   az rest --method PATCH \
     --url "https://graph.microsoft.com/v1.0/policies/authenticationMethodsPolicy" \
     --headers "Content-Type=application/json" \
     --body '{"registrationEnforcement":{"authenticationMethodsRegistrationCampaign":{"state":"enabled"}}}'

══════════════════════════════════════════════════════════════════
SSPR_NOTE

# ================================================================
# 6. VERIFICATION
# ================================================================

info "=== Verification ==="

info "Listing lab users:"
az ad user list --filter "startswith(displayName,'CertLab')" \
  --query "[].{Name:displayName, UPN:userPrincipalName, Id:id}" -o table

echo ""
info "Listing lab groups:"
az ad group list --filter "startswith(displayName,'${PREFIX}')" \
  --query "[].{Name:displayName, Id:id}" -o table

echo ""
info "Listing RBAC assignments on ${RESOURCE_GROUP}:"
az role assignment list --resource-group "$RESOURCE_GROUP" \
  --query "[].{Principal:principalName, Role:roleDefinitionName, Scope:scope}" -o table

echo ""

# ================================================================
# OUTPUT FOR BICEP PARAMETER FILE
# ================================================================

cat <<EOF

══════════════════════════════════════════════════════════════════
 NEXT STEP — paste these into main.bicepparam:

   param contributorGroupPrincipalId = '${ADMINS_GROUP_ID}'
   param readerGroupPrincipalId      = '${READERS_GROUP_ID}'

 Then deploy:
   az deployment group create \\
     --resource-group ${RESOURCE_GROUP} \\
     --template-file main.bicep \\
     --parameters main.bicepparam
══════════════════════════════════════════════════════════════════
EOF

info "✅ Entra ID setup complete."

# ================================================================
# CLEANUP FUNCTION
# ================================================================
# Run this to tear down all lab objects created above.
# Usage:  bash entra-setup.sh cleanup
# ================================================================

cleanup() {
  echo ""
  warn "=== CLEANUP: Removing lab identity objects ==="
  echo ""

  # Remove RBAC assignments
  info "Removing RBAC role assignments on ${RESOURCE_GROUP}..."
  local rg_scope
  rg_scope=$(az group show --name "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null || true)

  if [[ -n "$rg_scope" ]]; then
    for assignment_id in $(az role assignment list --resource-group "$RESOURCE_GROUP" \
      --query "[?contains(principalName,'${PREFIX}')].id" -o tsv 2>/dev/null); do
      info "  Deleting assignment ${assignment_id}"
      az role assignment delete --ids "$assignment_id" 2>/dev/null || true
    done
  fi

  # Delete groups
  info "Deleting lab groups..."
  for group_name in "${PREFIX}-admins" "${PREFIX}-readers" "${PREFIX}-developers"; do
    gid=$(az ad group list --filter "displayName eq '${group_name}'" --query "[0].id" -o tsv 2>/dev/null || true)
    if [[ -n "$gid" ]]; then
      info "  Deleting group: ${group_name} (${gid})"
      az ad group delete --group "$gid" 2>/dev/null || true
    fi
  done

  # Delete users
  info "Deleting lab users..."
  for user_upn in "${PREFIX}-user1" "${PREFIX}-user2" "${PREFIX}-admin" "${PREFIX}-reader"; do
    uid=$(az ad user list --filter "userPrincipalName eq '${user_upn}@${DOMAIN_NAME}'" --query "[0].id" -o tsv 2>/dev/null || true)
    if [[ -n "$uid" ]]; then
      info "  Deleting user: ${user_upn}@${DOMAIN_NAME} (${uid})"
      az ad user delete --id "$uid" 2>/dev/null || true
    fi
  done

  echo ""
  info "✅ Cleanup complete."
}

# If "cleanup" is passed as the first argument, run cleanup and exit
if [[ "${1:-}" == "cleanup" ]]; then
  cleanup
  exit 0
fi
