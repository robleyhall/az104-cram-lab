# Exercise 01: Identity & Microsoft Entra ID

[🎥 Cram Session: Entra ID (02:20–27:00)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=140s)

> **Exam Domain**: Manage Azure identities and governance (20–25%)
>
> These exercises cover user and group management, role assignments, and self-service password reset in Microsoft Entra ID (formerly Azure AD).

---

## Prerequisites

- An active Azure subscription with **Owner** or **User Access Administrator** role
- Azure CLI v2.60+ authenticated (`az login`)
- Microsoft Entra ID P1 license for dynamic groups and SSPR (free tier works for basic exercises)
- Module 00 (Foundation) deployed

---

## Exercise 1.1: Create and Manage Users via Azure CLI

**Difficulty**: 🟢 Guided

**Objectives**:
- Create member and guest users in Entra ID
- Set user properties (department, job title, usage location)
- Understand the difference between Member and Guest user types

**Steps**:

1. Retrieve your tenant domain:
   ```bash
   DOMAIN=$(az rest --method get --url 'https://graph.microsoft.com/v1.0/domains' \
     --query "value[?isDefault].id" -o tsv)
   echo "Your domain: $DOMAIN"
   ```

2. Create a new member user:
   ```bash
   az ad user create \
     --display-name "Lab User One" \
     --user-principal-name "labuser1@${DOMAIN}" \
     --password "P@ssw0rd1234!" \
     --force-change-password-next-sign-in true \
     --department "Engineering" \
     --job-title "Cloud Engineer"
   ```

3. Create a second user with a different department:
   ```bash
   az ad user create \
     --display-name "Lab User Two" \
     --user-principal-name "labuser2@${DOMAIN}" \
     --password "P@ssw0rd1234!" \
     --force-change-password-next-sign-in true \
     --department "Operations" \
     --job-title "IT Administrator"
   ```

4. List all users you created:
   ```bash
   az ad user list --query "[?startsWith(displayName,'Lab User')]" \
     --output table
   ```

5. Update a user's properties:
   ```bash
   az ad user update \
     --id "labuser1@${DOMAIN}" \
     --job-title "Senior Cloud Engineer"
   ```

6. Invite a guest user (use a personal email or another tenant account):
   ```bash
   az rest --method post \
     --url 'https://graph.microsoft.com/v1.0/invitations' \
     --body '{
       "invitedUserEmailAddress": "guest@example.com",
       "inviteRedirectUrl": "https://portal.azure.com",
       "sendInvitationMessage": false
     }'
   ```

**Success Criteria**:
- [ ] Two member users exist with correct departments and job titles
- [ ] `az ad user show --id labuser1@${DOMAIN}` returns updated job title
- [ ] You can explain the difference between Member and Guest user types

> 💡 **Exam Tip**: Member users are created directly in your tenant. Guest users are invited from external tenants or identity providers. Guest users have limited default permissions (e.g., can't enumerate all users by default). The exam frequently tests on user type differences.

> ⚠️ **Common Mistake**: Forgetting to set `--force-change-password-next-sign-in` for new users — this is a security best practice and often appears in exam scenarios.

---

## Exercise 1.2: Create Security and Microsoft 365 Groups

**Difficulty**: 🟢 Guided

**Objectives**:
- Create an assigned security group and an M365 group
- Add and remove group members
- Understand when to use each group type

[🎥 Groups (15:51)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=951s)

**Steps**:

1. Create a security group:
   ```bash
   az ad group create \
     --display-name "sg-engineering" \
     --mail-nickname "sg-engineering" \
     --description "Engineering team security group"
   ```

2. Create a Microsoft 365 group:
   ```bash
   az ad group create \
     --display-name "m365-project-alpha" \
     --mail-nickname "m365-project-alpha" \
     --description "Project Alpha collaboration group" \
     --group-types "Unified"
   ```

3. Add labuser1 to the security group:
   ```bash
   USER1_ID=$(az ad user show --id "labuser1@${DOMAIN}" --query id -o tsv)
   az ad group member add --group "sg-engineering" --member-id "$USER1_ID"
   ```

4. Add both users to the M365 group:
   ```bash
   USER2_ID=$(az ad user show --id "labuser2@${DOMAIN}" --query id -o tsv)
   az ad group member add --group "m365-project-alpha" --member-id "$USER1_ID"
   az ad group member add --group "m365-project-alpha" --member-id "$USER2_ID"
   ```

5. Verify group membership:
   ```bash
   az ad group member list --group "sg-engineering" --query "[].displayName" -o tsv
   az ad group member list --group "m365-project-alpha" --query "[].displayName" -o tsv
   ```

6. Check which groups labuser1 belongs to:
   ```bash
   az ad user get-member-groups --id "$USER1_ID" --query "[].displayName" -o tsv
   ```

**Success Criteria**:
- [ ] Security group `sg-engineering` has 1 member
- [ ] M365 group `m365-project-alpha` has 2 members
- [ ] You can explain why M365 groups include `--group-types "Unified"`

> 💡 **Exam Tip**: Security groups can be used for RBAC assignments and resource access. M365 groups provide shared mailbox, calendar, SharePoint site, etc. **Only security groups and M365 groups (mail-enabled)** can be used for Azure role assignments — distribution groups cannot.

> 📖 **Deep Dive**: [Microsoft Entra ID Groups Documentation](https://learn.microsoft.com/en-us/azure/active-directory/)

---

## Exercise 1.3: Configure Dynamic Group Membership Rules

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Create a dynamic security group with membership rules
- Understand rule syntax and evaluation
- Test dynamic membership by modifying user attributes

[🎥 Groups — Dynamic Membership (15:51)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=951s)

> ⚠️ **Prerequisite**: Dynamic groups require **Entra ID P1** or **P2** license.

**Steps**:

1. Create a dynamic group that includes all users in the Engineering department:
   ```bash
   az rest --method post \
     --url 'https://graph.microsoft.com/v1.0/groups' \
     --body '{
       "displayName": "dyn-engineering",
       "mailNickname": "dyn-engineering",
       "mailEnabled": false,
       "securityEnabled": true,
       "groupTypes": ["DynamicMembership"],
       "membershipRule": "(user.department -eq \"Engineering\")",
       "membershipRuleProcessingState": "On"
     }'
   ```

2. Verify the rule was set correctly:
   ```bash
   az rest --method get \
     --url "https://graph.microsoft.com/v1.0/groups?\$filter=displayName eq 'dyn-engineering'" \
     --query "value[0].{name:displayName, rule:membershipRule, state:membershipRuleProcessingState}"
   ```

3. Wait 1–2 minutes for dynamic evaluation, then check members:
   ```bash
   DYN_GROUP_ID=$(az ad group show --group "dyn-engineering" --query id -o tsv)
   az ad group member list --group "$DYN_GROUP_ID" --query "[].displayName" -o tsv
   ```

4. Change labuser2's department to "Engineering" and observe:
   ```bash
   az ad user update --id "labuser2@${DOMAIN}" --department "Engineering"
   # Wait 1-2 minutes for dynamic membership to re-evaluate
   az ad group member list --group "$DYN_GROUP_ID" --query "[].displayName" -o tsv
   ```

5. **Explore on your own**: Create a dynamic group using a different rule. Try:
   - `(user.jobTitle -contains "Engineer")`
   - `(user.department -eq "Engineering") -and (user.jobTitle -ne null)`
   - `(user.userPrincipalName -match "labuser")`

**Success Criteria**:
- [ ] Dynamic group `dyn-engineering` auto-populates with users whose department = Engineering
- [ ] Changing labuser2's department causes them to be added to the group
- [ ] You can write a dynamic membership rule using `-eq`, `-contains`, or `-match` operators

> 💡 **Exam Tip**: Dynamic group rules use a specific syntax. Common operators: `-eq`, `-ne`, `-contains`, `-startsWith`, `-match`. Rules are evaluated periodically, not instantly. Know that you **cannot manually add/remove members** from dynamic groups.

> ⚠️ **Common Mistake**: Trying to add a static member to a dynamic group — this is not supported and will error. If you need both dynamic and manual members, use two separate groups or a dynamic group with a broader rule.

---

## Exercise 1.4: Assign Built-in Entra ID Roles

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Assign the User Administrator role to a user
- Assign the Global Reader role to a group
- Understand the principle of least privilege

[🎥 Roles (25:00)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=1500s)

**Steps**:

1. List common built-in Entra roles:
   ```bash
   az rest --method get \
     --url 'https://graph.microsoft.com/v1.0/directoryRoles' \
     --query "value[].{name:displayName, id:id}" -o table
   ```

2. Find the User Administrator role template ID:
   ```bash
   az rest --method get \
     --url "https://graph.microsoft.com/v1.0/directoryRoleTemplates" \
     --query "value[?displayName=='User Administrator'].{name:displayName, id:id}" -o table
   ```

3. Assign the User Administrator role to labuser1:
   ```bash
   USER_ADMIN_TEMPLATE=$(az rest --method get \
     --url "https://graph.microsoft.com/v1.0/directoryRoleTemplates" \
     --query "value[?displayName=='User Administrator'].id" -o tsv)

   az rest --method post \
     --url 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments' \
     --body "{
       \"@odata.type\": \"#microsoft.graph.unifiedRoleAssignment\",
       \"roleDefinitionId\": \"$USER_ADMIN_TEMPLATE\",
       \"principalId\": \"$USER1_ID\",
       \"directoryScopeId\": \"/\"
     }"
   ```

4. Assign the Global Reader role to the sg-engineering group:
   ```bash
   GLOBAL_READER_TEMPLATE=$(az rest --method get \
     --url "https://graph.microsoft.com/v1.0/directoryRoleTemplates" \
     --query "value[?displayName=='Global Reader'].id" -o tsv)

   SG_ENG_ID=$(az ad group show --group "sg-engineering" --query id -o tsv)

   az rest --method post \
     --url 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments' \
     --body "{
       \"@odata.type\": \"#microsoft.graph.unifiedRoleAssignment\",
       \"roleDefinitionId\": \"$GLOBAL_READER_TEMPLATE\",
       \"principalId\": \"$SG_ENG_ID\",
       \"directoryScopeId\": \"/\"
     }"
   ```

5. Verify role assignments:
   ```bash
   az rest --method get \
     --url "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?\$filter=principalId eq '$USER1_ID'" \
     --query "value[].{roleId:roleDefinitionId, scope:directoryScopeId}"
   ```

**Success Criteria**:
- [ ] labuser1 has the User Administrator role
- [ ] All members of sg-engineering inherit Global Reader through group assignment
- [ ] You can articulate why assigning roles to groups is preferred over individual users

> 💡 **Exam Tip**: Entra ID roles (User Admin, Global Admin, etc.) govern **directory operations**. Azure RBAC roles (Owner, Contributor, Reader) govern **Azure resource operations**. The exam tests whether you know which role type to use. Entra roles ≠ Azure roles.

> 📖 **Deep Dive**: [Entra ID Built-in Roles](https://learn.microsoft.com/en-us/azure/active-directory/)

---

## Exercise 1.5: Design a Role Assignment Strategy

**Difficulty**: 🔴 Challenge

**Objectives**:
- Design a role assignment plan for a multi-team organization
- Apply the principle of least privilege
- Document your design decisions

**Scenario**:

Your organization has the following teams:

| Team | Members | Needs |
|------|---------|-------|
| **Help Desk** (5 people) | Reset passwords, manage user accounts | Cannot create new admins |
| **Security Team** (3 people) | Read-only access to all audit logs and security settings | Cannot modify any settings |
| **App Dev Team** (15 people) | Register applications, manage app credentials | No directory admin access |
| **IT Managers** (2 people) | Full user/group management, license assignment | Cannot access billing or global settings |

**Your Task**:

1. For each team, identify the **minimum Entra ID role** needed
2. Decide whether to assign roles to individuals or groups (justify your choice)
3. Consider: Should any roles use **time-limited (PIM)** assignments?
4. Create the groups and role assignments using Azure CLI

**Design Template** (fill in your answers):

```
Team: Help Desk
  Entra Role: _______________
  Assignment Type: [ ] User  [x] Group
  Justification: _______________

Team: Security Team
  Entra Role: _______________
  Assignment Type: [ ] User  [x] Group
  Justification: _______________

Team: App Dev Team
  Entra Role: _______________
  Assignment Type: [ ] User  [x] Group
  Justification: _______________

Team: IT Managers
  Entra Role: _______________
  Assignment Type: [ ] User  [x] Group
  Justification: _______________
```

**Implement your design**:
```bash
# Create groups for each team
az ad group create --display-name "role-helpdesk" --mail-nickname "role-helpdesk"
az ad group create --display-name "role-security" --mail-nickname "role-security"
az ad group create --display-name "role-appdev" --mail-nickname "role-appdev"
az ad group create --display-name "role-itmanagers" --mail-nickname "role-itmanagers"

# Assign the appropriate roles — replace ROLE_ID with your chosen role IDs
# Example (implement for all four teams):
# az rest --method post \
#   --url 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments' \
#   --body '{ ... }'
```

**Success Criteria**:
- [ ] Each team has a security group with the correct role assignment
- [ ] No team has more permissions than needed (least privilege)
- [ ] You can justify each role selection verbally or in writing
- [ ] You considered PIM for elevated roles (IT Managers)

> 💡 **Exam Tip**: The exam loves "which role should you assign?" questions. Key roles to know: **Helpdesk Administrator** (reset passwords for non-admins), **Security Reader** (read-only security access), **Application Administrator** (manage app registrations), **User Administrator** (full user/group management). Global Admin is almost never the right answer.

---

## Exercise 1.6: Bulk User Management Scenario

**Difficulty**: 🔴 Challenge

**Scenario**:

> *"Your company just hired 50 new employees across three departments: Engineering (20), Marketing (15), and Finance (15). Each employee needs an Entra ID account, a license assignment, and membership in the appropriate department security group. How would you automate this?"*

**Your Task**:

1. Create a CSV file with user data:
   ```bash
   cat > lab-bulk-users.csv << 'EOF'
   displayName,userPrincipalName,department,jobTitle,password
   Eng User 01,enguser01@YOURDOMAIN,Engineering,Software Engineer,P@ssw0rd1234!
   Eng User 02,enguser02@YOURDOMAIN,Engineering,Software Engineer,P@ssw0rd1234!
   Mkt User 01,mktuser01@YOURDOMAIN,Marketing,Marketing Analyst,P@ssw0rd1234!
   Fin User 01,finuser01@YOURDOMAIN,Finance,Financial Analyst,P@ssw0rd1234!
   EOF
   ```

2. Write a script that reads the CSV and creates users:
   ```bash
   #!/bin/bash
   DOMAIN=$(az rest --method get --url 'https://graph.microsoft.com/v1.0/domains' \
     --query "value[?isDefault].id" -o tsv)

   tail -n +2 lab-bulk-users.csv | while IFS=',' read -r name upn dept title pw; do
     upn="${upn/YOURDOMAIN/$DOMAIN}"
     echo "Creating user: $name ($upn)"
     az ad user create \
       --display-name "$name" \
       --user-principal-name "$upn" \
       --password "$pw" \
       --department "$dept" \
       --job-title "$title" \
       --force-change-password-next-sign-in true \
       2>/dev/null && echo "  ✅ Created" || echo "  ❌ Failed"
   done
   ```

3. Create dynamic groups for auto-assignment:
   ```bash
   for dept in Engineering Marketing Finance; do
     az rest --method post \
       --url 'https://graph.microsoft.com/v1.0/groups' \
       --body "{
         \"displayName\": \"dept-${dept,,}\",
         \"mailNickname\": \"dept-${dept,,}\",
         \"mailEnabled\": false,
         \"securityEnabled\": true,
         \"groupTypes\": [\"DynamicMembership\"],
         \"membershipRule\": \"(user.department -eq \\\"$dept\\\")\",
         \"membershipRuleProcessingState\": \"On\"
       }"
   done
   ```

4. Verify users were created and groups populated:
   ```bash
   az ad user list --query "[?startsWith(displayName,'Eng User')].{name:displayName, dept:department}" -o table
   az ad user list --query "[?startsWith(displayName,'Mkt User')].{name:displayName, dept:department}" -o table
   az ad user list --query "[?startsWith(displayName,'Fin User')].{name:displayName, dept:department}" -o table
   ```

**Success Criteria**:
- [ ] Bulk creation script processes all users from the CSV
- [ ] Dynamic groups auto-populate based on department attribute
- [ ] You can explain why dynamic groups are better than static groups for department-based membership
- [ ] You considered error handling (what if a user already exists?)

> 💡 **Exam Tip**: The exam may ask about bulk operations. Methods include: **Azure Portal bulk upload** (CSV), **PowerShell** (`New-MgUser`), **Azure CLI**, and **Microsoft Graph API**. Know that dynamic group membership is the scalable way to manage group membership — manual assignment doesn't scale for 50+ users.

> ⚠️ **Common Mistake**: In bulk scenarios, not setting the **usage location** before assigning licenses. License assignment will fail without a usage location set.

> 📖 **Deep Dive**: [SSPR Configuration](https://learn.microsoft.com/en-us/azure/active-directory/) — SSPR requires at minimum: 1 authentication method for "Selected" group, 2 methods for "All." It requires Entra ID P1 license. The exam tests whether you know the minimum license and method requirements.

---

## Clean Up

```bash
# Remove lab users
for user in labuser1 labuser2 enguser01 enguser02 mktuser01 finuser01; do
  az ad user delete --id "${user}@${DOMAIN}" 2>/dev/null
done

# Remove groups
for group in sg-engineering m365-project-alpha dyn-engineering \
             dept-engineering dept-marketing dept-finance \
             role-helpdesk role-security role-appdev role-itmanagers; do
  az ad group delete --group "$group" 2>/dev/null
done

# Remove CSV
rm -f lab-bulk-users.csv

echo "✅ Identity lab resources cleaned up"
```

---

## Key Concepts for the Exam

| Concept | Details |
|---------|---------|
| User Types | **Member** = internal, **Guest** = external (B2B) |
| Group Types | **Security** = RBAC/resource access, **M365** = collaboration + shared resources |
| Membership Types | **Assigned** = manual, **Dynamic User** = rule-based, **Dynamic Device** = device rules |
| SSPR | Requires P1+, minimum 1 method (selected), 2 methods (all users) |
| Entra Roles vs Azure RBAC | Entra = directory operations, RBAC = resource operations |
| Bulk Operations | Portal CSV upload, PowerShell, CLI, Graph API |

---

*Next: [Exercise 02 — Governance](02-governance-exercises.md)*
