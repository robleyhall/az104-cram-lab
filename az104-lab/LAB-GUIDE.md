# AZ-104 CertForge Lab Guide

## Complete Hands-On Study Guide for Azure Administrator Certification

> Built from [John Savill's AZ-104 Cram v2](https://www.youtube.com/watch?v=0Knf9nub4-k) using CertForge

---

## How to Use This Guide

This lab guide is a **standalone study resource** for the AZ-104: Microsoft Azure Administrator certification. It combines theory, hands-on deployment exercises, and exam preparation across all five exam domains.

### Approach

1. **Read the Concepts** — Each module begins with theory mapped to exam objectives
2. **Deploy the Infrastructure** — Use the provided Bicep templates to create real Azure resources
3. **Explore & Verify** — Run CLI commands and navigate the Portal to understand what was deployed
4. **Complete the Exercises** — Practice with guided, exploratory, and challenge exercises
5. **Review Key Takeaways** — Focus on exam-critical points and common mistakes
6. **Watch the Cram Session** — Use provided timestamps to jump to specific topics in the video

### Callout Legend

| Icon | Meaning |
|------|---------|
| 💡 | **Exam Tip** — Likely to appear on the exam |
| ⚠️ | **Common Mistake** — Frequently wrong answer on exams |
| 📖 | **Deep Dive** — Optional further reading |

---

## Prerequisites

- **Azure Subscription** — Pay-as-you-go or free trial
- **Azure CLI** ≥ 2.50.0 with Bicep extension
- **Basic knowledge** — Comfortable with Azure Portal, CLI, and at least one IaC tool
- Run `./prerequisites/check-prerequisites.sh` to validate your environment

---

## Exam Overview

| Domain | Weight | Lab Modules |
|--------|--------|-------------|
| Manage Azure identities and governance | 20–25% | 01-identity, 02-governance |
| Implement and manage storage | 15–20% | 06-storage |
| Deploy and manage Azure compute resources | 20–25% | 07-compute |
| Implement and manage virtual networking | 15–20% | 03-networking, 04-dns-connectivity, 05-load-balancing |
| Monitor and maintain Azure resources | 10–15% | 08-monitoring |

---

## Lab Architecture

This lab uses a **hub-spoke network topology** — the most common enterprise Azure pattern:

```
                    ┌─────────────────┐
                    │   Hub VNet      │
                    │   10.0.0.0/16   │
                    │                 │
                    │ • Bastion       │
                    │ • Gateway       │
                    │ • Firewall      │
                    │ • Management    │
                    └───────┬─────────┘
                   ┌────────┴────────┐
            ┌──────┴──────┐   ┌──────┴──────┐
            │  Spoke 1    │   │  Spoke 2    │
            │ 10.1.0.0/16 │   │ 10.2.0.0/16│
            │             │   │             │
            │ • VMs       │   │ • Secondary │
            │ • Apps      │   │   workloads │
            │ • Data      │   │             │
            └─────────────┘   └─────────────┘
```

### Resource Groups

| Resource Group | Module | Purpose |
|---------------|--------|---------|
| rg-certlab-foundation | 00 | Hub VNet, shared infrastructure |
| rg-certlab-identity | 01 | Managed identities, role assignments |
| rg-certlab-governance | 02 | Policy, locks, budgets, custom roles |
| rg-certlab-networking | 03 | Spoke VNets, peering, NSGs, ASGs |
| rg-certlab-dns-connectivity | 04 | DNS zones, UDRs, endpoints, Bastion |
| rg-certlab-load-balancing | 05 | Load Balancer, Traffic Manager |
| rg-certlab-storage | 06 | Storage accounts, blob, file shares |
| rg-certlab-compute | 07 | VMs, VMSS, ACI, ACR, App Service |
| rg-certlab-monitoring | 08 | Log Analytics, alerts, Recovery Services |

### Deployment Order

```
00-foundation ──► 01-identity
              ──► 02-governance
              ──► 03-networking ──► 04-dns-connectivity ──► 06-storage
                               ──► 05-load-balancing
                               ──► 07-compute ──► 08-monitoring
```

---

## Module 01: Identity & Entra ID

**Exam Domain:** Manage Azure identities and governance (20–25%)

### Learning Objectives

After completing this module, you will be able to:

1. Create and manage Entra ID users (cloud, hybrid, guest)
2. Create and manage security and Microsoft 365 groups (assigned and dynamic membership)
3. Configure self-service password reset (SSPR)
4. Assign and manage Entra ID roles and administrative units
5. Manage licenses in Entra ID
6. Understand Entra Connect Sync vs Cloud Sync

### Exam Relevance

| Skill | Tested? |
|-------|---------|
| Create users and groups | ✅ Directly |
| Manage user and group properties | ✅ Directly |
| Manage licenses in Microsoft Entra ID | ✅ Directly |
| Manage external users | ✅ Directly |
| Configure self-service password reset (SSPR) | ✅ Directly |

### Concepts Overview

#### Entra ID vs Active Directory Domain Services

| Feature | Entra ID | AD DS |
|---------|----------|-------|
| Location | Cloud (global) | On-premises |
| Protocols | OAuth 2.0, OpenID Connect, SAML | Kerberos, NTLM, LDAP |
| Structure | Flat (no OUs) | Hierarchical (OUs, forests, domains) |
| Management API | Microsoft Graph (REST) | LDAP, PowerShell |
| Ports | HTTPS (443) | Multiple (88, 389, 636, etc.) |
| Device join | Entra Join / Register | Domain Join |
| Delegation | Administrative Units | Organizational Units |

💡 **Exam Tip:** Entra ID is NOT an Azure service — it's a global identity instance. A tenant does not live within an Azure subscription. You associate subscriptions with a tenant for authentication.

#### Tenant Concept

Your Entra ID tenant is your organization's identity instance. Key points:
- Default domain: `{name}.onmicrosoft.com`
- You can add and verify custom domains (requires DNS TXT/MX record)
- The tenant exists independently of Azure subscriptions
- Multiple subscriptions can trust the same tenant

#### User Types

| Type | Source | Created How |
|------|--------|-------------|
| Cloud | Entra ID native | Created directly in tenant |
| Hybrid | On-prem AD DS | Synced via Entra Connect |
| Guest/External | Other IdP | Invited via B2B collaboration |

External users can come from: other Entra tenants, Microsoft accounts, Google, Facebook, SAML/WS-Fed providers, or email one-time passcodes.

⚠️ **Common Mistake:** External users are guests by default but can be changed to members. This affects how some policies are applied. Know the difference between "External" (source) and "Guest" (role).

#### Group Types

| Feature | Security Group | Microsoft 365 Group |
|---------|---------------|-------------------|
| Use case | RBAC, resource access | Collaboration (Teams, SharePoint) |
| Membership | Assigned or Dynamic | Assigned or Dynamic |
| Can contain | Users, devices, service principals | Users only |
| Role assignable | Yes (if enabled) | Yes (if enabled) |

**Dynamic Membership:** Rules based on user/device attributes (e.g., `user.department -eq "Engineering"`). Dynamic groups are periodically reevaluated — they cannot mix users and devices in one group.

💡 **Exam Tip:** Dynamic groups require Entra ID P1 or P2 licenses. You configure rules, not manual membership. The rule syntax uses `-eq`, `-ne`, `-contains`, `-match`, etc.

#### Entra ID License Tiers

| Feature | Free | P1 | P2 |
|---------|------|----|----|
| Users and groups | ✅ | ✅ | ✅ |
| Self-service password reset (cloud) | ✅ | ✅ | ✅ |
| Conditional Access | ❌ | ✅ | ✅ |
| SSPR with on-prem writeback | ❌ | ✅ | ✅ |
| Dynamic groups | ❌ | ✅ | ✅ |
| HR-driven provisioning | ❌ | ✅ | ✅ |
| Privileged Identity Management | ❌ | ❌ | ✅ |
| Identity Protection | ❌ | ❌ | ✅ |
| Access Reviews | ❌ | ❌ | ✅ |

📖 **Deep Dive:** [Microsoft Entra Pricing](https://www.microsoft.com/security/business/microsoft-entra-pricing) for full feature comparison.

#### SSPR (Self-Service Password Reset)

Requirements for SSPR:
- At minimum Entra ID Free for cloud-only accounts
- P1 required for writeback to on-premises AD
- Users must register authentication methods (phone, email, security questions, authenticator app)
- Admin can require 1 or 2 methods for reset

#### Key Roles

| Role | Scope | Key Permissions |
|------|-------|----------------|
| Global Administrator | Tenant-wide | Full access to everything |
| User Administrator | Tenant-wide | Manage users and groups |
| Helpdesk Administrator | Tenant-wide | Reset passwords for non-admins |
| Global Reader | Tenant-wide | Read everything, modify nothing |

⚠️ **Common Mistake:** Global Admin is the most privileged role — limit to 2-4 people max. It can even manage access to Azure subscriptions via the "Access management for Azure resources" toggle.

### Deploy

```bash
# Create resource group
az group create --name rg-certlab-identity --location eastus

# Preview deployment
az deployment group create \
  --resource-group rg-certlab-identity \
  --template-file modules/01-identity/main.bicep \
  --parameters modules/01-identity/main.bicepparam \
  --what-if

# Deploy
az deployment group create \
  --resource-group rg-certlab-identity \
  --template-file modules/01-identity/main.bicep \
  --parameters modules/01-identity/main.bicepparam

# Run Entra ID setup (users, groups, roles)
chmod +x modules/01-identity/entra-setup.sh
./modules/01-identity/entra-setup.sh
```

### Explore & Verify

```bash
# List created users
az ad user list --filter "startswith(displayName,'certlab')" -o table

# List groups
az ad group list --filter "startswith(displayName,'certlab')" -o table

# Check group membership
az ad group member list --group "certlab-admins" -o table

# Check role assignments
az role assignment list --resource-group rg-certlab-identity -o table
```

**Portal Navigation:** Entra ID → Users → All Users | Groups → All Groups | Roles and administrators

### Exercises

See [exercises/01-identity-exercises.md](exercises/01-identity-exercises.md) for the full exercise set.

**Quick Guided Exercise:** Create a dynamic group where membership is based on job title containing "Developer":
```bash
az ad group create --display-name "certlab-developers-dynamic" \
  --mail-nickname "certlab-devs-dyn" \
  --description "Dynamic group for developers" \
  --membership-rule "user.jobTitle -contains \"Developer\"" \
  --membership-rule-processing-state "On" \
  --group-types "DynamicMembership"
```

### Key Takeaways

1. **Entra ID is flat** — no OUs. Use Administrative Units for delegation
2. **User types matter** — Cloud, Hybrid, Guest each have different management flows
3. **Groups over individuals** — Always assign roles/licenses to groups, not users
4. **Dynamic groups need P1** — And they can't mix users and devices
5. **SSPR writeback needs P1** — Cloud-only SSPR works with Free tier

💡 **Exam Tip:** Know the difference between Entra Connect Sync (engine on-prem) and Entra Cloud Sync (engine in cloud, lightweight agents on-prem). The sync direction is always AD DS → Entra ID.

### Cram Session Reference

| Topic | Timestamp | Link |
|-------|-----------|------|
| Entra ID | 02:20 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=140s) |
| ADDS to Entra Sync | 05:01 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=301s) |
| Tenant | 07:59 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=479s) |
| Branding | 10:21 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=621s) |
| Users | 11:08 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=668s) |
| Groups | 15:51 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=951s) |
| Devices | 18:57 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=1137s) |
| Licenses | 20:48 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=1248s) |
| SSPR | 23:27 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=1407s) |
| Roles | 25:00 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=1500s) |

---

## Module 02: Governance & Compliance

**Exam Domain:** Manage Azure identities and governance (20–25%)

### Learning Objectives

1. Implement and manage Azure Policy (definitions, assignments, effects, compliance)
2. Configure resource locks (CanNotDelete, ReadOnly)
3. Apply and manage tags on resources
4. Manage resource groups (lifecycle, move operations)
5. Configure management groups
6. Create custom RBAC roles and assign at different scopes
7. Manage costs with budgets, alerts, and Azure Advisor

### Exam Relevance

This module covers the governance half of Domain 1 plus cost management. Together with Module 01, these two modules cover 20–25% of the exam.

### Concepts Overview

#### Management Group Hierarchy

```
Root Management Group
├── Production MG
│   ├── Subscription A
│   │   ├── rg-web-prod
│   │   └── rg-db-prod
│   └── Subscription B
└── Development MG
    └── Subscription C
        └── rg-web-dev
```

- Maximum 6 levels of depth (excluding root and subscription)
- Policies and RBAC assignments inherit downward
- Each subscription can only be in ONE management group

💡 **Exam Tip:** Management groups let you apply governance at scale. A policy at a management group applies to ALL subscriptions beneath it.

#### Azure Policy

| Effect | Behavior | When to Use |
|--------|----------|-------------|
| Audit | Log non-compliance | Visibility without blocking |
| Deny | Block non-compliant creates/updates | Enforce standards |
| DeployIfNotExists | Auto-remediate by deploying resources | Auto-configure (e.g., diagnostics) |
| Modify | Add/update/remove tags or properties | Tag governance |
| Disabled | Turn off a policy without removing | Temporarily disable |
| AuditIfNotExists | Audit if related resource missing | Check for companion resources |

**Policy assignment flow:** Definition → Initiative (optional grouping) → Assignment (at scope) → Evaluation → Compliance

⚠️ **Common Mistake:** Policy effects like Deny only apply to NEW resource operations. Existing non-compliant resources show in compliance reports but aren't automatically blocked or removed. You need remediation tasks for existing resources.

#### RBAC (Role-Based Access Control)

Three elements of a role assignment:
1. **Security Principal** — Who (user, group, service principal, managed identity)
2. **Role Definition** — What permissions (actions/notActions/dataActions)
3. **Scope** — Where (management group, subscription, resource group, resource)

| Built-in Role | Permissions |
|--------------|-------------|
| Owner | Full access + can assign roles |
| Contributor | Full access EXCEPT role assignment |
| Reader | View only |
| User Access Administrator | Manage role assignments only |

💡 **Exam Tip:** RBAC is additive — if you have Reader at subscription level and Contributor at resource group level, you effectively have Contributor on that resource group. The only exception is **deny assignments** (from Blueprints).

#### Resource Locks

| Lock Type | Can Read? | Can Modify? | Can Delete? |
|-----------|-----------|-------------|-------------|
| CanNotDelete | ✅ | ✅ | ❌ |
| ReadOnly | ✅ | ❌ | ❌ |

⚠️ **Common Mistake:** A ReadOnly lock on a resource group prevents adding NEW resources to it (because adding is a write operation). A ReadOnly lock on a storage account prevents listing keys.

#### Tags

- Tags are name-value pairs (max 50 per resource)
- Tags do NOT inherit from resource groups by default
- Use Azure Policy with "Inherit a tag from the resource group" to auto-inherit
- Common tags: Environment, CostCenter, Owner, Project, Department

#### Cost Management

Key tools:
- **Cost Analysis** — View current spending by service, resource group, tag
- **Budgets** — Set monthly spending limits with alerts (50%, 80%, 100%)
- **Azure Advisor** — Free recommendations for cost, security, reliability, performance
- **Reservations** — 1-year or 3-year commitments for 40-72% savings on VMs, databases
- **Spot VMs** — Up to 90% discount, can be evicted anytime

### Deploy

```bash
# Create resource group
az group create --name rg-certlab-governance --location eastus \
  --tags Environment=certlab Project=az104-lab Module=governance

# Preview deployment
az deployment group create \
  --resource-group rg-certlab-governance \
  --template-file modules/02-governance/main.bicep \
  --parameters modules/02-governance/main.bicepparam \
  --what-if

# Deploy
az deployment group create \
  --resource-group rg-certlab-governance \
  --template-file modules/02-governance/main.bicep \
  --parameters modules/02-governance/main.bicepparam

# Deploy custom policy definition from JSON
az policy definition create \
  --name "audit-missing-costcenter" \
  --display-name "Audit missing CostCenter tag" \
  --rules modules/02-governance/policy-definitions.json \
  --mode Indexed
```

### Explore & Verify

```bash
# List policy assignments on resource group
az policy assignment list --resource-group rg-certlab-governance -o table

# Check policy compliance
az policy state summarize --resource-group rg-certlab-governance

# List resource locks
az lock list --resource-group rg-certlab-governance -o table

# List role assignments
az role assignment list --resource-group rg-certlab-governance -o table

# Check tags
az group show --name rg-certlab-governance --query tags
```

### Exercises

See [exercises/02-governance-exercises.md](exercises/02-governance-exercises.md) for the full exercise set.

### Key Takeaways

1. **Policy effects matter** — Know Audit vs Deny vs DeployIfNotExists for the exam
2. **RBAC is additive, scopes cascade** — Assignments at higher scopes inherit downward
3. **Tags don't inherit** — Use Policy to enforce inheritance from resource groups
4. **Locks override RBAC** — Even an Owner can't delete a CanNotDelete-locked resource (must remove lock first)
5. **Custom roles fill gaps** — When built-in roles are too broad or too narrow

### Cram Session Reference

| Topic | Timestamp | Link |
|-------|-----------|------|
| Clouds and regions | 27:23 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=1643s) |
| Subscriptions & Management Groups | 34:48 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=2088s) |
| Cost analysis and budgets | 39:14 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=2354s) |
| Resource Groups | 43:31 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=2611s) |
| Cost saving mechanisms | 45:39 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=2739s) |
| Tags | 51:20 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=3080s) |
| Azure Policy | 54:35 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=3275s) |
| RBAC | 59:09 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=3549s) |
| Resource locking | 1:06:56 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=4016s) |

---

## Module 03: Virtual Networking

**Exam Domain:** Implement and manage virtual networking (15–20%)

### Learning Objectives

1. Create and configure virtual networks and subnets
2. Create and configure virtual network peering
3. Configure public IP addresses
4. Create and configure NSGs and application security groups
5. Evaluate effective security rules in NSGs

### Concepts Overview

#### Virtual Networks (VNets)

- VNets are regional — they cannot span regions
- Address spaces use private RFC 1918 ranges: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
- Subnets divide a VNet's address space — they cannot overlap
- **Reserved addresses per subnet:** First 4 + last 1 (e.g., in 10.0.0.0/24: .0 network, .1 gateway, .2-.3 Azure DNS, .255 broadcast)

💡 **Exam Tip:** Azure reserves 5 IP addresses per subnet. A /24 gives you 251 usable IPs, not 256. A /27 (32 addresses) gives only 27 usable.

#### Special Subnets

| Subnet | Name Must Be | Min Size | Purpose |
|--------|-------------|----------|---------|
| AzureBastionSubnet | Exact name required | /26 | Azure Bastion |
| GatewaySubnet | Exact name required | /27 recommended | VPN/ExpressRoute Gateway |
| AzureFirewallSubnet | Exact name required | /26 | Azure Firewall |

#### VNet Peering

- Connects two VNets for private IP communication
- **Non-transitive:** If A↔B and B↔C, A cannot reach C through B (unless you use a hub with forwarding)
- Can be same-region or cross-region (global peering)
- Settings: Allow forwarded traffic, Allow gateway transit, Use remote gateways

⚠️ **Common Mistake:** Peering is NOT transitive. Hub-spoke requires enabling "Allow forwarded traffic" on spoke peerings and a Network Virtual Appliance (NVA) or Azure Firewall in the hub to route between spokes.

#### Network Security Groups (NSGs)

- Stateful firewall rules at Layer 4 (TCP/UDP/ICMP)
- Can be associated with **subnets** or **NICs** (or both — both are evaluated)
- Rules have priority 100–4096 (lower number = higher priority = evaluated first)
- Default rules (cannot delete, priority 65000+): AllowVNetInBound, AllowAzureLoadBalancerInBound, DenyAllInBound, AllowVNetOutBound, AllowInternetOutBound, DenyAllOutBound

💡 **Exam Tip:** NSG rules are evaluated by priority. First matching rule wins. If you have Allow at 100 and Deny at 200 for the same traffic, the Allow wins.

#### Application Security Groups (ASGs)

- Logical grouping of NICs by application role (e.g., WebServers, AppServers)
- Use ASGs in NSG rules instead of IP addresses
- A NIC can be in multiple ASGs
- ASGs must be in the same region as the resources

| Without ASGs | With ASGs |
|-------------|-----------|
| Source: 10.1.0.4, 10.1.0.5 | Source: asg-web-servers |
| Hard to maintain as IPs change | Auto-updates when VMs join/leave ASG |

#### Public IP Addresses

| Feature | Basic SKU | Standard SKU |
|---------|-----------|-------------|
| Allocation | Static or Dynamic | Static only |
| Availability zones | Not supported | Zone-redundant |
| Security | Open by default | Closed by default (need NSG) |
| Load Balancer | Basic LB only | Standard LB only |

⚠️ **Common Mistake:** Standard SKU public IPs are secure by default — no inbound traffic is allowed until you add an NSG rule. Basic SKU is open by default.

### Deploy

```bash
# Create resource group
az group create --name rg-certlab-networking --location eastus

# Preview
az deployment group create \
  --resource-group rg-certlab-networking \
  --template-file modules/03-networking/main.bicep \
  --parameters modules/03-networking/main.bicepparam \
  --what-if

# Deploy
az deployment group create \
  --resource-group rg-certlab-networking \
  --template-file modules/03-networking/main.bicep \
  --parameters modules/03-networking/main.bicepparam

# Set up hub-side peering (cross-resource-group)
az network vnet peering create \
  --name hub-to-spoke1 \
  --resource-group rg-certlab-foundation \
  --vnet-name vnet-certlab-hub \
  --remote-vnet $(az network vnet show -g rg-certlab-networking -n vnet-certlab-spoke1 --query id -o tsv) \
  --allow-forwarded-traffic --allow-gateway-transit

az network vnet peering create \
  --name hub-to-spoke2 \
  --resource-group rg-certlab-foundation \
  --vnet-name vnet-certlab-hub \
  --remote-vnet $(az network vnet show -g rg-certlab-networking -n vnet-certlab-spoke2 --query id -o tsv) \
  --allow-forwarded-traffic --allow-gateway-transit
```

### Explore & Verify

```bash
# List VNets
az network vnet list -g rg-certlab-networking -o table

# Check peering status
az network vnet peering list -g rg-certlab-networking --vnet-name vnet-certlab-spoke1 -o table

# List NSG rules
az network nsg rule list -g rg-certlab-networking --nsg-name nsg-certlab-web -o table

# Check effective security rules on a NIC
az network nic list-effective-nsg -g rg-certlab-networking -n <nic-name>
```

### Exercises

See [exercises/03-networking-exercises.md](exercises/03-networking-exercises.md) for the full exercise set.

### Key Takeaways

1. **VNets are regional, subnets are logical** — Plan address spaces to avoid overlap
2. **Peering is non-transitive** — Hub-spoke needs forwarding + NVA
3. **NSG priority is key** — Lower number wins, default deny at 65500
4. **Use ASGs** — Much easier to manage than IP-based rules
5. **Standard public IP is secure by default** — Needs NSG for inbound

### Cram Session Reference

| Topic | Timestamp | Link |
|-------|-----------|------|
| Networking overview | 1:09:28 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=4168s) |
| Virtual network | 1:10:15 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=4215s) |
| Peering | 1:20:00 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=4800s) |
| Virtual Network Manager | 1:24:36 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=5076s) |
| Network Security Group | 1:28:47 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=5327s) |
| Azure Firewall | 1:36:27 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=5787s) |

---

## Module 04: DNS & Connectivity

**Exam Domain:** Implement and manage virtual networking (15–20%)

### Learning Objectives

1. Configure Azure DNS (public and private zones)
2. Configure user-defined routes (UDRs)
3. Implement Azure Bastion
4. Configure service endpoints for Azure PaaS
5. Configure private endpoints for Azure PaaS
6. Troubleshoot network connectivity

### Concepts Overview

#### Azure DNS

- **Public DNS Zone:** Hosts DNS records for internet-facing domains
- **Private DNS Zone:** Name resolution within VNets (not internet-resolvable)
- Supported record types: A, AAAA, CNAME, MX, NS, PTR, SOA, SRV, TXT

**Private DNS features:**
- **VNet Link:** Connect a Private DNS zone to a VNet
- **Auto-registration:** VMs automatically get DNS records in the zone
- One VNet can link to multiple Private DNS zones
- One Private DNS zone can link to multiple VNets

💡 **Exam Tip:** Auto-registration only works with Private DNS zones linked to VNets with the feature enabled. Each VNet can have auto-registration enabled for only ONE Private DNS zone.

#### User-Defined Routes (UDRs)

Route tables override Azure's default system routes. Next hop types:

| Next Hop Type | Use Case |
|--------------|----------|
| Virtual appliance | Route through NVA/firewall (specify IP) |
| Virtual network gateway | Route to on-premises via VPN/ExpressRoute |
| Virtual network | Override default within VNet |
| Internet | Force traffic to internet |
| None | Drop traffic (black hole) |

⚠️ **Common Mistake:** UDRs override system routes for the specific prefix. If you create a 0.0.0.0/0 route to a virtual appliance, ALL internet-bound traffic goes through the NVA — including traffic to Azure services. Use service tags or service endpoints to keep Azure management traffic flowing.

#### Service Endpoints vs Private Endpoints

| Feature | Service Endpoint | Private Endpoint |
|---------|-----------------|-----------------|
| Traffic path | Microsoft backbone (still public IP) | Through VNet (private IP) |
| DNS | No change needed | Requires Private DNS zone |
| IP on PaaS service | Public IP | Private IP in your subnet |
| Cost | Free | Per-hour + per-GB charge |
| Firewall rules | VNet-based allow rules | Full network isolation |
| Cross-region | Same region only | Cross-region supported |

💡 **Exam Tip:** Private endpoints give the PaaS service a private IP in YOUR VNet. Service endpoints keep the public IP but route traffic over the Azure backbone. For exam scenarios asking about "complete network isolation" → private endpoint.

#### Azure Bastion

Provides secure RDP/SSH access to VMs without public IPs on the VMs.

| SKU | Features | Cost |
|-----|----------|------|
| Developer | Single VM, no scaling | ~$0.19/hr |
| Basic | Multiple VMs, scaling | ~$0.19/hr + scale units |
| Standard | All Basic + native client, IP-based, shareable links | ~$0.19/hr + scale units |

#### Connectivity (Conceptual — not deployed in lab)

| Service | Use Case | Cost |
|---------|----------|------|
| S2S VPN | Connect on-prem network to Azure via IPsec tunnel | ~$0.04/hr |
| ExpressRoute | Private dedicated connection to Azure (via provider) | $$$$ |
| Azure Virtual WAN | Managed hub for connecting branches, VNets, VPNs | ~$0.05/hr |

📖 **Deep Dive:** [Azure Bastion documentation](https://learn.microsoft.com/en-us/azure/bastion/) for SKU comparison and features.

### Deploy

```bash
# Create resource group
az group create --name rg-certlab-dns-connectivity --location eastus

# Get hub VNet and spoke1 VNet IDs
HUB_VNET_ID=$(az network vnet show -g rg-certlab-foundation -n vnet-certlab-hub --query id -o tsv)
SPOKE1_VNET_ID=$(az network vnet show -g rg-certlab-networking -n vnet-certlab-spoke1 --query id -o tsv)
SPOKE1_DATA_SUBNET_ID=$(az network vnet subnet show -g rg-certlab-networking \
  --vnet-name vnet-certlab-spoke1 -n data --query id -o tsv)

# Preview
az deployment group create \
  --resource-group rg-certlab-dns-connectivity \
  --template-file modules/04-dns-connectivity/main.bicep \
  --parameters modules/04-dns-connectivity/main.bicepparam \
  --parameters hubVNetId=$HUB_VNET_ID spoke1VNetId=$SPOKE1_VNET_ID \
    spoke1DataSubnetId=$SPOKE1_DATA_SUBNET_ID \
  --what-if

# Deploy (Bastion costs ~$0.19/hr — add deployBastion=false to skip)
az deployment group create \
  --resource-group rg-certlab-dns-connectivity \
  --template-file modules/04-dns-connectivity/main.bicep \
  --parameters modules/04-dns-connectivity/main.bicepparam \
  --parameters hubVNetId=$HUB_VNET_ID spoke1VNetId=$SPOKE1_VNET_ID \
    spoke1DataSubnetId=$SPOKE1_DATA_SUBNET_ID
```

### Explore & Verify

```bash
# List DNS zones
az network dns zone list -g rg-certlab-dns-connectivity -o table

# List DNS records
az network dns record-set list -g rg-certlab-dns-connectivity -z certlab.example.com -o table

# List Private DNS zones
az network private-dns zone list -g rg-certlab-dns-connectivity -o table

# Check route table
az network route-table route list -g rg-certlab-dns-connectivity --route-table-name rt-certlab-spoke1 -o table

# Check effective routes on a NIC
az network nic show-effective-route-table -g rg-certlab-networking -n <nic-name>
```

### Exercises

See [exercises/04-dns-connectivity-exercises.md](exercises/04-dns-connectivity-exercises.md) for the full exercise set.

### Key Takeaways

1. **Private DNS + VNet link = internal name resolution** — Auto-registration creates records automatically
2. **UDRs override system routes** — Use for forced tunneling through NVA
3. **Service endpoint = free, stays on backbone** — Private endpoint = private IP, costs money
4. **Bastion eliminates public IPs on VMs** — Much more secure than exposing RDP/SSH
5. **Know your next hop types** — Virtual appliance, VNet gateway, Internet, None

### Cram Session Reference

| Topic | Timestamp | Link |
|-------|-----------|------|
| Azure DNS | 1:38:41 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=5921s) |
| Azure Private DNS | 1:41:35 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=6095s) |
| Connectivity | 1:46:51 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=6411s) |
| S2S VPN | 1:47:52 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=6472s) |
| ExpressRoute | 1:50:34 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=6634s) |
| Azure Virtual WAN | 1:56:09 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=6969s) |
| User Defined Routes | 1:58:36 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7116s) |
| Service endpoints | 1:59:55 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7195s) |
| Private endpoints | 2:04:50 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7490s) |
| Azure Bastion | 2:08:03 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7683s) |

---

## Module 05: Load Balancing

**Exam Domain:** Implement and manage virtual networking (15–20%)

### Learning Objectives

1. Configure an internal or public load balancer
2. Troubleshoot load balancing
3. Understand when to use each Azure load balancing service

### Concepts Overview

#### Azure Load Balancing Decision Matrix

| Service | Layer | Scope | Protocol | Best For |
|---------|-------|-------|----------|----------|
| Azure Load Balancer | 4 | Regional | TCP/UDP | High-performance L4 distribution |
| Application Gateway | 7 | Regional | HTTP/HTTPS | WAF, SSL offload, URL routing |
| Traffic Manager | DNS | Global | Any (DNS) | DNS-based global routing |
| Azure Front Door | 7 | Global | HTTP/HTTPS | Global CDN + WAF + LB |
| Cross-region LB | 4 | Global | TCP/UDP | Global L4 with regional failover |

**Decision flow:**
1. Global or Regional? → Global: Traffic Manager (any protocol) or Front Door (HTTP/S)
2. Regional: L4 or L7? → L4: Azure Load Balancer | L7: Application Gateway

#### Azure Load Balancer

| Feature | Basic SKU | Standard SKU |
|---------|-----------|-------------|
| Backend pool | Single availability set/VMSS | Any VMs in single VNet |
| Health probes | TCP, HTTP | TCP, HTTP, HTTPS |
| Availability zones | Not supported | Zone-redundant |
| SLA | None | 99.99% |
| Security | Open by default | Closed (NSG required) |
| HA Ports | No | Yes |

Components: Frontend IP → Load balancing rules → Backend pool, with health probes monitoring backends.

💡 **Exam Tip:** Standard Load Balancer requires Standard SKU public IPs and has an NSG requirement — backends must have NSGs allowing the probe and traffic. Basic LB doesn't require this.

**Session persistence options:**
- **None** (default) — Any backend can handle any request
- **Client IP** — Same client IP always goes to same backend
- **Client IP and protocol** — Same client IP + protocol combo → same backend

#### Application Gateway (Conceptual)

- Layer 7 load balancer with WAF capability
- Features: SSL termination, cookie-based affinity, URL-based routing, multi-site hosting, redirection, autoscaling
- SKUs: Standard_v2, WAF_v2
- Cost: ~$0.25/hr + data processing (expensive for lab use)

#### Traffic Manager

- DNS-based global traffic distribution — returns the best endpoint IP via DNS resolution
- Routing methods:
  - **Priority** — Primary/secondary failover
  - **Weighted** — Distribute by percentage
  - **Performance** — Route to lowest-latency endpoint
  - **Geographic** — Route by user's geographic location
  - **Multivalue** — Return multiple healthy endpoints
  - **Subnet** — Route by client subnet

⚠️ **Common Mistake:** Traffic Manager works at DNS level — it doesn't proxy traffic. The client connects directly to the endpoint after DNS resolution. This means Traffic Manager can't do SSL offloading or URL-based routing.

#### Azure Front Door (Conceptual)

- Global Layer 7 load balancer with CDN and WAF
- Built-in caching, SSL offload, URL rewriting
- Split TCP for faster connections
- Works with App Service, Storage, VMs, or any public endpoint

### Deploy

```bash
# Create resource group
az group create --name rg-certlab-load-balancing --location eastus

# Deploy
az deployment group create \
  --resource-group rg-certlab-load-balancing \
  --template-file modules/05-load-balancing/main.bicep \
  --parameters modules/05-load-balancing/main.bicepparam \
  --what-if

az deployment group create \
  --resource-group rg-certlab-load-balancing \
  --template-file modules/05-load-balancing/main.bicep \
  --parameters modules/05-load-balancing/main.bicepparam
```

### Explore & Verify

```bash
# Check load balancer
az network lb show -g rg-certlab-load-balancing -n lb-certlab-web -o table

# List LB rules
az network lb rule list -g rg-certlab-load-balancing --lb-name lb-certlab-web -o table

# Check health probe status
az network lb probe list -g rg-certlab-load-balancing --lb-name lb-certlab-web -o table

# Check Traffic Manager
az network traffic-manager profile show -g rg-certlab-load-balancing -n tm-certlab-web -o table
```

### Exercises

See [exercises/05-load-balancing-exercises.md](exercises/05-load-balancing-exercises.md) for the full exercise set.

### Key Takeaways

1. **Know the decision matrix** — L4 vs L7, regional vs global
2. **Standard LB is closed by default** — Requires NSG on backends
3. **Traffic Manager is DNS-only** — It doesn't see actual traffic
4. **Session persistence** — None, Client IP, Client IP + Protocol
5. **Health probes are critical** — Unhealthy backends are removed from rotation

### Cram Session Reference

| Topic | Timestamp | Link |
|-------|-----------|------|
| Load balancing | 2:10:24 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7824s) |
| Azure Load Balancer | 2:12:03 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7923s) |
| Azure App Gateway | 2:18:13 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=8293s) |
| Azure Traffic Manager | 2:25:01 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=8701s) |
| Cross Region LB | 2:26:51 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=8811s) |
| Azure Front Door | 2:28:09 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=8889s) |

---

## Module 06: Storage

**Exam Domain:** Implement and manage storage (15–20%)

### Learning Objectives

1. Configure Azure Storage firewalls and virtual networks
2. Create and use shared access signature (SAS) tokens
3. Configure stored access policies
4. Manage access keys and configure identity-based access
5. Create and configure storage accounts with proper redundancy
6. Configure blob containers, file shares, tiers, soft delete, lifecycle management, and versioning
7. Use Azure Storage Explorer and AzCopy

### Concepts Overview

#### Storage Account Types

| Type | Services | Performance | Use Case |
|------|----------|-------------|----------|
| StorageV2 (general purpose v2) | Blob, File, Queue, Table | Standard or Premium | Default choice for most scenarios |
| BlobStorage | Blob only | Standard | Legacy (use StorageV2 instead) |
| BlockBlobStorage | Block + append blobs | Premium | High-transaction blob workloads |
| FileStorage | Azure Files only | Premium | Enterprise file shares |

#### Storage Redundancy

| Type | Copies | Durability | Cross-Region | Read Access to Secondary |
|------|--------|------------|--------------|--------------------------|
| LRS | 3 in one datacenter | 11 nines | ❌ | ❌ |
| ZRS | 3 across zones | 12 nines | ❌ | ❌ |
| GRS | 6 (3 local + 3 remote) | 16 nines | ✅ (after failover) | ❌ |
| RA-GRS | 6 | 16 nines | ✅ | ✅ (read anytime) |
| GZRS | 6 (3 zones + 3 remote) | 16 nines | ✅ (after failover) | ❌ |
| RA-GZRS | 6 | 16 nines | ✅ | ✅ (read anytime) |

💡 **Exam Tip:** RA-GRS/RA-GZRS provide read access to the secondary region at all times (append `-secondary` to account name). Regular GRS/GZRS only expose the secondary after a failover.

#### Blob Access Tiers

| Tier | Storage Cost | Access Cost | Min Retention | Latency |
|------|-------------|-------------|---------------|---------|
| Hot | Highest | Lowest | None | Milliseconds |
| Cool | Lower | Higher | 30 days | Milliseconds |
| Cold | Lower still | Higher still | 90 days | Milliseconds |
| Archive | Lowest | Highest | 180 days | Hours (rehydration) |

⚠️ **Common Mistake:** Archive tier blobs are OFFLINE — you must rehydrate them (to Hot or Cool) before reading. Rehydration can take up to 15 hours (Standard) or 1 hour (High Priority).

#### Lifecycle Management

Automate tier transitions and deletion:
```
Hot → Cool (after 30 days) → Archive (after 90 days) → Delete (after 365 days)
```
Rules can filter by container, prefix, and blob type.

#### Access Methods

| Method | Scope | Best For |
|--------|-------|----------|
| Access keys | Full account access | Administrative tasks |
| Account SAS | Account-level, customizable | Delegated access to multiple services |
| Service SAS | Single service (blob, file, etc.) | Delegated access to specific service |
| User delegation SAS | Blob only, Entra ID-backed | Most secure SAS option |
| Entra ID RBAC | Granular role-based | Production best practice |

💡 **Exam Tip:** User Delegation SAS is the most secure SAS type because it's signed with Entra ID credentials (not account keys). It only works with Blob storage.

**Stored Access Policies** — Attach to a container to control SAS tokens. You can modify or revoke the policy to invalidate all SAS tokens that reference it.

#### Storage Firewalls

- Default: Allow from all networks
- Restricted: Allow from specific VNets (service endpoints), IP ranges, and trusted Azure services
- "Bypass: AzureServices" allows Azure Backup, Monitor, etc. to access storage even when firewall is on

#### Azure Files

- SMB (445) and NFS (2049) file shares
- Tiers: Premium (SSD), Transaction Optimized, Hot, Cool
- Identity-based access: Entra Domain Services, on-prem AD DS, Entra Kerberos
- Azure File Sync: Sync on-prem file servers with Azure Files, cloud tiering

#### Managed Disks

| Type | IOPS | Throughput | Use Case |
|------|------|------------|----------|
| Ultra Disk | Up to 160,000 | Up to 4,000 MB/s | SAP HANA, databases |
| Premium SSD v2 | Up to 80,000 | Up to 1,200 MB/s | Flexible high perf |
| Premium SSD | Up to 20,000 | Up to 900 MB/s | Production VMs |
| Standard SSD | Up to 6,000 | Up to 750 MB/s | Web servers, dev/test |
| Standard HDD | Up to 2,000 | Up to 500 MB/s | Backups, archive |

### Deploy

```bash
# Create resource group
az group create --name rg-certlab-storage --location eastus

# Get subnet ID for storage firewall rules
DATA_SUBNET_ID=$(az network vnet subnet show -g rg-certlab-networking \
  --vnet-name vnet-certlab-spoke1 -n data --query id -o tsv)

# Deploy
az deployment group create \
  --resource-group rg-certlab-storage \
  --template-file modules/06-storage/main.bicep \
  --parameters modules/06-storage/main.bicepparam \
  --parameters dataSubnetId=$DATA_SUBNET_ID \
  --what-if

az deployment group create \
  --resource-group rg-certlab-storage \
  --template-file modules/06-storage/main.bicep \
  --parameters modules/06-storage/main.bicepparam \
  --parameters dataSubnetId=$DATA_SUBNET_ID
```

### Explore & Verify

```bash
# List storage accounts
az storage account list -g rg-certlab-storage -o table

# Get primary account name
STORAGE_NAME=$(az storage account list -g rg-certlab-storage --query "[0].name" -o tsv)

# List containers
az storage container list --account-name $STORAGE_NAME --auth-mode login -o table

# Check lifecycle policy
az storage account management-policy show --account-name $STORAGE_NAME -g rg-certlab-storage

# Generate a SAS token (account-level)
az storage account generate-sas \
  --account-name $STORAGE_NAME \
  --permissions rl \
  --resource-types sco \
  --services b \
  --expiry $(date -u -v+1d '+%Y-%m-%dT%H:%MZ') \
  -o tsv

# Upload a blob using AzCopy
echo "Hello AZ-104" > /tmp/testblob.txt
az storage blob upload --account-name $STORAGE_NAME \
  --container-name certlab-data --name testblob.txt \
  --file /tmp/testblob.txt --auth-mode login
```

### Exercises

See [exercises/06-storage-exercises.md](exercises/06-storage-exercises.md) for the full exercise set.

### Key Takeaways

1. **Know redundancy levels** — LRS (cheapest, one DC) through RA-GZRS (most durable, read secondary anytime)
2. **Archive is offline** — Must rehydrate before reading
3. **User Delegation SAS is most secure** — Uses Entra ID, blob-only
4. **Stored access policies control SAS** — Only way to revoke SAS tokens after creation
5. **Storage firewall + service endpoints** — Cost-effective network restriction

### Cram Session Reference

| Topic | Timestamp | Link |
|-------|-----------|------|
| Storage accounts | 2:31:50 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=9110s) |
| Storage tools | 2:42:07 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=9727s) |
| Blob tiering | 2:44:20 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=9860s) |
| Lifecycle management | 2:49:05 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10145s) |
| Object replication | 2:50:22 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10222s) |
| Azure Files | 2:52:45 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10365s) |
| Access | 2:56:41 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10601s) |
| Encryption | 3:00:30 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10830s) |
| Managed disks | 3:02:54 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10974s) |

---

## Module 07: Compute

**Exam Domain:** Deploy and manage Azure compute resources (20–25%)

### Learning Objectives

1. Interpret, modify, and deploy ARM templates and Bicep files
2. Create and configure virtual machines
3. Manage VM sizes, disks, and extensions
4. Deploy VMs to availability zones and availability sets
5. Deploy and configure Virtual Machine Scale Sets (VMSS)
6. Create and manage Azure Container Registry (ACR)
7. Provision containers via ACI and Container Apps
8. Create and configure App Service plans, apps, scaling, and deployment slots

### Concepts Overview

#### ARM Templates vs Bicep

| Feature | ARM JSON | Bicep |
|---------|----------|-------|
| Syntax | Verbose JSON | Concise DSL |
| Readability | Difficult | Easy |
| Modularity | Linked/nested templates | Native modules |
| Parameters | parameters section | `param` keyword |
| Variables | variables section | `var` keyword |
| Conditions | condition property | `if` keyword |
| Loops | copy property | `for` keyword |
| Comments | Not supported | `//` comments |
| Tooling | Any JSON editor | VS Code extension |

ARM template structure: `$schema`, `contentVersion`, `parameters`, `variables`, `resources`, `outputs`

💡 **Exam Tip:** You WILL see ARM template interpretation questions. Know how to read parameters with defaultValue, variables with concat/format, resource dependencies with dependsOn, and outputs. See `modules/07-compute/sample-arm-template.json` for practice.

#### VM Sizing

| Family | Series | Optimized For | Example |
|--------|--------|--------------|---------|
| General Purpose | B, D, DS | Balanced CPU/memory | B2s (dev/test) |
| Compute Optimized | F, FS | High CPU | F4s (batch processing) |
| Memory Optimized | E, ES, M | High memory | E4s (databases) |
| Storage Optimized | L | High disk throughput | L8s (data warehouses) |
| GPU | N (NC, ND, NV) | GPU workloads | NC6s (ML/rendering) |

B-series VMs are **burstable** — they accumulate CPU credits when idle and spend them under load. Perfect for workloads with occasional spikes.

#### Availability Options

| Feature | Availability Set | Availability Zone |
|---------|-----------------|-------------------|
| SLA | 99.95% | 99.99% |
| Protection | Hardware failure in DC | Entire datacenter failure |
| Fault domains | 2-3 | N/A (separate DCs) |
| Update domains | 5-20 | N/A |
| Scope | Single datacenter | Multiple datacenters |
| Pricing | No extra cost | No extra cost |

⚠️ **Common Mistake:** You cannot put a VM in BOTH an availability set AND an availability zone. Choose one. Availability zones provide higher SLA (99.99% vs 99.95%).

#### Virtual Machine Scale Sets (VMSS)

- Auto-scaling based on metrics (CPU, memory, custom metrics), schedule, or manual
- Upgrade policies:
  - **Automatic** — All instances updated immediately
  - **Rolling** — Batches of instances updated with pause between
  - **Manual** — You trigger each instance upgrade
- Instance protection: Protect from scale-in, protect from all operations
- Orchestration modes: Uniform (identical VMs) vs Flexible (mix of VMs)

#### Container Services Comparison

| Feature | ACI | Container Apps | AKS | App Service |
|---------|-----|---------------|-----|-------------|
| Complexity | Simplest | Low-medium | High | Low |
| Scaling | Manual | Auto (KEDA) | Full Kubernetes | Built-in |
| Orchestration | None | Dapr, KEDA | Full K8s | PaaS managed |
| Networking | VNet optional | VNet integrated | Full VNet | VNet integration |
| Cost Model | Per-second CPU/mem | Per-second vCPU/mem | Node VMs | Plan-based |
| Best For | Quick tasks, CI/CD | Microservices | Full K8s features | Web apps |

#### App Service

**Plan tiers:** Free → Shared → Basic → Standard → Premium → Isolated

| Feature | Free/Shared | Basic | Standard | Premium |
|---------|------------|-------|----------|---------|
| Custom domain | Shared only | ✅ | ✅ | ✅ |
| SSL | ❌ | ✅ | ✅ | ✅ |
| Auto-scale | ❌ | ❌ | ✅ | ✅ |
| Deployment slots | ❌ | ❌ | ✅ (5) | ✅ (20) |
| VNet integration | ❌ | ❌ | ✅ | ✅ |
| Always On | ❌ | ✅ | ✅ | ✅ |

💡 **Exam Tip:** Deployment slots require Standard tier or above. Swap operations are zero-downtime. You can route a percentage of traffic to a slot for A/B testing.

**Scaling:** Scale UP = change plan size (more CPU/memory). Scale OUT = add more instances (1→10).

### Deploy

```bash
# Create resource group
az group create --name rg-certlab-compute --location eastus

# Get subnet IDs
SPOKE1_DEFAULT_SUBNET=$(az network vnet subnet show -g rg-certlab-networking \
  --vnet-name vnet-certlab-spoke1 -n default --query id -o tsv)
SPOKE1_APP_SUBNET=$(az network vnet subnet show -g rg-certlab-networking \
  --vnet-name vnet-certlab-spoke1 -n app --query id -o tsv)

# Deploy (requires SSH public key and admin password)
az deployment group create \
  --resource-group rg-certlab-compute \
  --template-file modules/07-compute/main.bicep \
  --parameters modules/07-compute/main.bicepparam \
  --parameters spoke1DefaultSubnetId=$SPOKE1_DEFAULT_SUBNET \
    spoke1AppSubnetId=$SPOKE1_APP_SUBNET \
    adminPublicKey="$(cat ~/.ssh/id_rsa.pub)" \
    adminPassword='<YourSecureP@ssw0rd!>' \
  --what-if

az deployment group create \
  --resource-group rg-certlab-compute \
  --template-file modules/07-compute/main.bicep \
  --parameters modules/07-compute/main.bicepparam \
  --parameters spoke1DefaultSubnetId=$SPOKE1_DEFAULT_SUBNET \
    spoke1AppSubnetId=$SPOKE1_APP_SUBNET \
    adminPublicKey="$(cat ~/.ssh/id_rsa.pub)" \
    adminPassword='<YourSecureP@ssw0rd!>'
```

### Explore & Verify

```bash
# List VMs
az vm list -g rg-certlab-compute -o table --show-details

# Check VMSS
az vmss list -g rg-certlab-compute -o table
az vmss list-instances -g rg-certlab-compute --name vmss-certlab-web -o table

# Check ACR
az acr list -g rg-certlab-compute -o table

# Check ACI
az container list -g rg-certlab-compute -o table
az container logs -g rg-certlab-compute --name ci-certlab-hello

# Check App Service
az webapp list -g rg-certlab-compute -o table
az webapp deployment slot list -g rg-certlab-compute --name <app-name> -o table
```

### Exercises

See [exercises/07-compute-exercises.md](exercises/07-compute-exercises.md) for the full exercise set.

**ARM Template Exercise:** Open `modules/07-compute/sample-arm-template.json` and answer:
1. What parameters does the template accept?
2. What default values are defined?
3. What resource is being deployed?
4. What does the output return?
5. Convert it to Bicep: `az bicep decompile --file modules/07-compute/sample-arm-template.json`

### Key Takeaways

1. **Know ARM template structure** — parameters, variables, resources, outputs
2. **Availability Zones > Availability Sets** for SLA (99.99% vs 99.95%)
3. **VMSS upgrade policies matter** — Rolling is safest for production
4. **ACI is simplest** — No cluster, no plan. Just a container
5. **Deployment slots need Standard tier** — Swap is zero-downtime

### Cram Session Reference

| Topic | Timestamp | Link |
|-------|-----------|------|
| Provisioning resources | 3:10:21 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=11421s) |
| Types of service | 3:15:07 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=11707s) |
| Virtual machines | 3:19:05 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=11945s) |
| Availability Set and Zones | 3:28:11 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=12491s) |
| VMSS | 3:30:54 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=12654s) |
| Containers | 3:34:35 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=12875s) |
| AKS | 3:37:25 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=13045s) |
| App Service Plan | 3:42:34 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=13354s) |

---

## Module 08: Monitoring & Backup

**Exam Domain:** Monitor and maintain Azure resources (10–15%)

### Learning Objectives

1. Interpret metrics in Azure Monitor
2. Configure log settings in Azure Monitor
3. Query and analyze logs using KQL
4. Set up alert rules, action groups, and alert processing rules
5. Configure monitoring of VMs, storage accounts, and networks
6. Use Azure Network Watcher and Connection Monitor
7. Create Recovery Services vault, backup policies, and perform backup/restore
8. Understand Azure Site Recovery (conceptual)

### Concepts Overview

#### Azure Monitor Architecture

```
Data Sources                    Azure Monitor                    Actions
─────────────                   ─────────────                    ───────
VMs ──────────┐                ┌─── Metrics ──── Metric Alerts ──► Action Groups
Storage ──────┤ Diagnostic     │    (real-time)                      ├─ Email
Network ──────┤ Settings ──────┤                                     ├─ SMS
Apps ─────────┤                │                                     ├─ Webhook
Activity Log ─┘                └─── Logs ─────── Log Alerts ─────►   ├─ Logic App
                                    (Log Analytics)                   └─ Azure Function
                                    └── KQL Queries
```

- **Metrics:** Numeric values collected at regular intervals. Near real-time. Retained 93 days.
- **Logs:** Structured/semi-structured data stored in Log Analytics workspaces. Retained per policy (30-730 days).

#### Key Differences: Metrics vs Logs

| Feature | Metrics | Logs |
|---------|---------|------|
| Data type | Numeric time-series | Rich structured records |
| Collection | Automatic for most resources | Requires diagnostic settings |
| Query language | Metrics Explorer (visual) | KQL (Kusto Query Language) |
| Latency | Near real-time (1 min) | Minutes (ingestion delay) |
| Retention | 93 days | 30-730 days (configurable) |
| Cost | Free (platform metrics) | Per-GB ingestion |

💡 **Exam Tip:** Platform metrics are collected automatically and free. Logs require you to configure diagnostic settings to send data to a Log Analytics workspace and cost money based on ingestion volume (5 GB/month free tier).

#### KQL (Kusto Query Language) Essentials

```kusto
// Basic structure
TableName
| where TimeGenerated > ago(1h)
| where ColumnName == "value"
| summarize Count = count() by GroupColumn
| order by Count desc
| project Column1, Column2, Count
```

Key operators:
| Operator | Purpose | Example |
|----------|---------|---------|
| `where` | Filter rows | `where CPU > 80` |
| `project` | Select columns | `project Computer, CPU` |
| `summarize` | Aggregate | `summarize avg(CPU) by Computer` |
| `extend` | Add calculated column | `extend GB = MB / 1024` |
| `order by` | Sort results | `order by CPU desc` |
| `render` | Visualize | `render timechart` |
| `join` | Combine tables | `join kind=inner OtherTable on Key` |
| `ago()` | Relative time | `ago(1h)`, `ago(7d)` |

See `modules/08-monitoring/sample-kql-queries.txt` for 10 useful queries.

#### Alert Types

| Alert Type | Data Source | Evaluation | Use Case |
|-----------|-------------|------------|----------|
| Metric alert | Metrics | Periodic (1-15 min) | CPU > 80%, disk space low |
| Log alert | Log Analytics (KQL) | Periodic (5-15 min) | Custom query conditions |
| Activity log alert | Activity Log | Real-time | Resource deleted, role assigned |

**Alert severity levels:** 0 (Critical), 1 (Error), 2 (Warning), 3 (Informational), 4 (Verbose)

**Action Groups** define what happens when an alert fires: email, SMS, push, voice, webhook, Logic App, Azure Function, ITSM.

⚠️ **Common Mistake:** Alert rules have a cost. Each metric alert rule costs ~$0.10/month. Log alert rules cost more (~$0.50-1.50/month depending on frequency). Plan alerts carefully.

#### Network Watcher

| Tool | Purpose |
|------|---------|
| IP Flow Verify | Test if traffic is allowed/denied (NSG check) |
| Next Hop | Determine next hop for a packet |
| Connection Troubleshoot | Test TCP connectivity between two endpoints |
| NSG Flow Logs | Capture network flow data for analysis |
| Topology | Visual network topology diagram |
| Packet Capture | Capture packets on a VM |

💡 **Exam Tip:** Network Watcher is auto-enabled per region. IP Flow Verify checks NSG rules. Next Hop checks routing tables. Connection Troubleshoot does an end-to-end connectivity test. Know when to use each.

#### Azure Backup

| Feature | Recovery Services Vault | Backup Vault |
|---------|------------------------|--------------|
| Supports | VMs, SQL, Files, SAP HANA | Blobs, Disks, PostgreSQL |
| Soft delete | 14 days default | 14 days default |
| Cross-region | GRS replication | GRS replication |
| Encryption | Platform + customer keys | Platform + customer keys |

**Backup Policy components:**
- **Schedule:** Daily, weekly (time and days)
- **Retention:** Daily (7-9999 days), weekly, monthly, yearly
- **Instant restore:** Snapshots retained 1-5 days for fast recovery

#### Azure Site Recovery (Conceptual)

- Replicates VMs to a secondary Azure region
- Provides disaster recovery with configurable RPO (Recovery Point Objective)
- Failover/failback capabilities
- Not deployed in this lab (requires paired region setup and adds cost)

📖 **Deep Dive:** [Azure Backup documentation](https://learn.microsoft.com/en-us/azure/backup/) and [Azure Site Recovery documentation](https://learn.microsoft.com/en-us/azure/site-recovery/)

### Deploy

```bash
# Create resource group
az group create --name rg-certlab-monitoring --location eastus

# Optionally get VM resource ID for metric alerts
VM_ID=$(az vm show -g rg-certlab-compute -n vm-certlab-linux1 --query id -o tsv 2>/dev/null)

# Deploy
az deployment group create \
  --resource-group rg-certlab-monitoring \
  --template-file modules/08-monitoring/main.bicep \
  --parameters modules/08-monitoring/main.bicepparam \
  --parameters contactEmail='your-email@example.com' \
  ${VM_ID:+--parameters vmResourceId=$VM_ID} \
  --what-if

az deployment group create \
  --resource-group rg-certlab-monitoring \
  --template-file modules/08-monitoring/main.bicep \
  --parameters modules/08-monitoring/main.bicepparam \
  --parameters contactEmail='your-email@example.com' \
  ${VM_ID:+--parameters vmResourceId=$VM_ID}

# Enable VM diagnostics (post-deployment)
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  -g rg-certlab-monitoring -n law-certlab-monitor --query id -o tsv)

az vm diagnostics set -g rg-certlab-compute -n vm-certlab-linux1 \
  --settings '{}' || echo "Configure via Portal: VM → Diagnostic settings → Add"

# Configure VM backup
az backup protection enable-for-vm \
  --resource-group rg-certlab-monitoring \
  --vault-name rsv-certlab-backup \
  --vm $(az vm show -g rg-certlab-compute -n vm-certlab-linux1 --query id -o tsv) \
  --policy-name policy-certlab-vm-daily
```

### Explore & Verify

```bash
# Check Log Analytics workspace
az monitor log-analytics workspace show -g rg-certlab-monitoring -n law-certlab-monitor -o table

# List alert rules
az monitor metrics alert list -g rg-certlab-monitoring -o table

# Check action groups
az monitor action-group list -g rg-certlab-monitoring -o table

# Check Recovery Services vault
az backup vault show -g rg-certlab-monitoring -n rsv-certlab-backup -o table

# List backup policies
az backup policy list -g rg-certlab-monitoring --vault-name rsv-certlab-backup -o table

# Run a KQL query
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "Heartbeat | summarize count() by Computer" \
  -o table
```

### Exercises

See [exercises/08-monitoring-exercises.md](exercises/08-monitoring-exercises.md) for the full exercise set.

### Key Takeaways

1. **Metrics = free, automatic** — Logs require diagnostic settings and cost per GB
2. **Know basic KQL** — where, project, summarize, extend, ago()
3. **Action groups are reusable** — Multiple alerts can trigger the same action group
4. **Network Watcher tools** — IP Flow Verify for NSGs, Next Hop for routing, Connection Troubleshoot for E2E
5. **Recovery Services vault for VMs** — Backup vault for blobs/disks

### Cram Session Reference

| Topic | Timestamp | Link |
|-------|-----------|------|
| Monitoring | 3:45:25 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=13525s) |
| Alerting | 3:50:48 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=13848s) |
| Log Analytics Workspace | 3:54:57 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=14097s) |
| Network Watcher | 3:59:05 | [Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=14345s) |

---

## Comprehensive Review

### Exam Readiness Checklist

Check off each skill as you feel confident. All items are directly from the [official exam study guide](https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/az-104).

#### Domain 1: Manage Azure identities and governance (20–25%)

- [ ] Create users and groups
- [ ] Manage user and group properties
- [ ] Manage licenses in Microsoft Entra ID
- [ ] Manage external users
- [ ] Configure self-service password reset (SSPR)
- [ ] Manage built-in Azure roles
- [ ] Assign roles at different scopes
- [ ] Interpret access assignments
- [ ] Implement and manage Azure Policy
- [ ] Configure resource locks
- [ ] Apply and manage tags on resources
- [ ] Manage resource groups
- [ ] Manage subscriptions
- [ ] Manage costs by using alerts, budgets, and Azure Advisor recommendations
- [ ] Configure management groups

#### Domain 2: Implement and manage storage (15–20%)

- [ ] Configure Azure Storage firewalls and virtual networks
- [ ] Create and use shared access signature (SAS) tokens
- [ ] Configure stored access policies
- [ ] Manage access keys
- [ ] Configure identity-based access for Azure Files
- [ ] Create and configure storage accounts
- [ ] Configure Azure Storage redundancy
- [ ] Configure object replication
- [ ] Configure storage account encryption
- [ ] Manage data by using Azure Storage Explorer and AzCopy
- [ ] Create and configure a file share in Azure Files
- [ ] Create and configure a container in Azure Blob Storage
- [ ] Configure storage tiers
- [ ] Configure soft delete for blobs and containers
- [ ] Configure snapshots and soft delete for Azure Files
- [ ] Configure blob lifecycle management
- [ ] Configure blob versioning

#### Domain 3: Deploy and manage Azure compute resources (20–25%)

- [ ] Interpret an Azure Resource Manager template or a Bicep file
- [ ] Modify an existing Azure Resource Manager template
- [ ] Modify an existing Bicep file
- [ ] Deploy resources by using an ARM template or Bicep file
- [ ] Export a deployment as an ARM template or convert to Bicep
- [ ] Create a virtual machine
- [ ] Configure encryption at host for Azure virtual machines
- [ ] Move a VM to another resource group, subscription, or region
- [ ] Manage virtual machine sizes
- [ ] Manage virtual machine disks
- [ ] Deploy VMs to availability zones and availability sets
- [ ] Deploy and configure Azure Virtual Machine Scale Sets
- [ ] Create and manage an Azure Container Registry
- [ ] Provision a container by using Azure Container Instances
- [ ] Provision a container by using Azure Container Apps
- [ ] Manage sizing and scaling for containers
- [ ] Provision an App Service plan
- [ ] Configure scaling for an App Service plan
- [ ] Create an App Service
- [ ] Configure certificates and TLS for an App Service
- [ ] Map an existing custom DNS name to an App Service
- [ ] Configure backup for an App Service
- [ ] Configure networking settings for an App Service
- [ ] Configure deployment slots for an App Service

#### Domain 4: Implement and manage virtual networking (15–20%)

- [ ] Create and configure virtual networks and subnets
- [ ] Create and configure virtual network peering
- [ ] Configure public IP addresses
- [ ] Configure user-defined routes
- [ ] Troubleshoot network connectivity
- [ ] Create and configure NSGs and application security groups
- [ ] Evaluate effective security rules in NSGs
- [ ] Implement Azure Bastion
- [ ] Configure service endpoints for Azure PaaS
- [ ] Configure private endpoints for Azure PaaS
- [ ] Configure Azure DNS
- [ ] Configure an internal or public load balancer
- [ ] Troubleshoot load balancing

#### Domain 5: Monitor and maintain Azure resources (10–15%)

- [ ] Interpret metrics in Azure Monitor
- [ ] Configure log settings in Azure Monitor
- [ ] Query and analyze logs in Azure Monitor
- [ ] Set up alert rules, action groups, and alert processing rules
- [ ] Configure and interpret monitoring of VMs, storage accounts, and networks
- [ ] Use Azure Network Watcher and Connection Monitor
- [ ] Create a Recovery Services vault
- [ ] Create an Azure Backup vault
- [ ] Create and configure a backup policy
- [ ] Perform backup and restore operations by using Azure Backup
- [ ] Configure Azure Site Recovery for Azure resources
- [ ] Perform a failover to a secondary region by using Site Recovery
- [ ] Configure and interpret reports and alerts for backups

---

### Practice Questions

**Q1.** Your company requires all resource groups to have an "Environment" tag. Which Azure feature enforces this at creation time?

A) Resource locks
B) Azure Policy with Deny effect
C) RBAC custom role
D) Management group

**Answer:** B) Azure Policy with Deny effect — Use the built-in policy "Require a tag on resource groups" with Deny effect to block creation of resource groups missing the tag.

---

**Q2.** You have a Standard Load Balancer with two VMs in the backend pool. Users report that the website is unreachable. What should you check first?

A) The VMs have public IP addresses
B) NSG rules allow traffic on port 80 to the backend VMs
C) The VMs are in the same availability set
D) DNS records are configured correctly

**Answer:** B) Standard Load Balancer backends are closed by default — NSG rules must explicitly allow the health probe source and load-balanced traffic.

---

**Q3.** You need to give a contractor read access to resources in a resource group, but they must not be able to see resources in other resource groups. What do you do?

A) Assign Reader role at the subscription level
B) Assign Reader role at the resource group level
C) Create a custom role with limited read access
D) Add them as a Guest user with no role

**Answer:** B) Assign Reader at the resource group scope. RBAC is scope-based — assigning at RG level limits visibility to that RG only.

---

**Q4.** A storage account has lifecycle management configured to move blobs to Archive tier after 90 days. A user tries to read a 100-day-old blob and gets an error. Why?

A) The blob was deleted by lifecycle management
B) The blob is in Archive tier and must be rehydrated first
C) The SAS token expired
D) The storage firewall blocked the request

**Answer:** B) Archive tier blobs are offline. They must be rehydrated to Hot or Cool tier before they can be read.

---

**Q5.** VNet A is peered with VNet B, and VNet B is peered with VNet C. Can resources in VNet A communicate with resources in VNet C?

A) Yes, peering is transitive
B) Yes, if all VNets are in the same region
C) No, VNet peering is non-transitive
D) Yes, if you enable "Allow gateway transit"

**Answer:** C) VNet peering is NOT transitive. To enable A↔C communication, you need direct peering, or use a hub VNet with an NVA/Azure Firewall and forwarding.

---

**Q6.** You want to create the most secure type of SAS token for Blob storage. Which type should you use?

A) Account SAS
B) Service SAS
C) User delegation SAS
D) SAS with stored access policy

**Answer:** C) User delegation SAS — signed with Entra ID credentials instead of the storage account key, making it the most secure option. Only works with Blob storage.

---

**Q7.** You need a VM deployment that provides a 99.99% SLA. Which option should you choose?

A) Single VM with Premium SSD
B) VMs in an availability set
C) VMs deployed across availability zones
D) VMs in a VMSS with zone balancing disabled

**Answer:** C) Availability zones provide 99.99% SLA by distributing VMs across physically separate datacenters. Availability sets provide 99.95%.

---

**Q8.** You need to route all internet-bound traffic from a subnet through a network virtual appliance (NVA) at 10.0.3.4. What do you configure?

A) NSG rule with deny internet
B) UDR with address prefix 0.0.0.0/0, next hop Virtual Appliance, IP 10.0.3.4
C) VNet peering with allow forwarded traffic
D) Service endpoint for Microsoft.Internet

**Answer:** B) A UDR with 0.0.0.0/0 pointing to the NVA's IP as a Virtual Appliance next hop overrides the default internet route.

---

**Q9.** A dynamic group in Entra ID is configured with the rule `user.department -eq "Sales"`. An employee transfers from Sales to Engineering. What happens?

A) The user stays in the group until manually removed
B) The user is automatically removed at next evaluation cycle
C) The user remains but with reduced permissions
D) Nothing — dynamic groups don't reevaluate existing members

**Answer:** B) Dynamic groups periodically reevaluate membership. When the department changes, the user no longer matches the rule and is automatically removed.

---

**Q10.** You want to be alerted when a VM's CPU exceeds 80% for 5 minutes. What type of alert should you create?

A) Activity log alert
B) Log alert (KQL query)
C) Metric alert
D) Service health alert

**Answer:** C) Metric alert — CPU percentage is a platform metric that supports near real-time evaluation. Metric alerts are the best fit for threshold-based monitoring of numeric values.

---

**Q11.** A ReadOnly lock is applied to a storage account. Which operation is blocked?

A) Reading blobs
B) Listing the storage account properties
C) Regenerating access keys
D) Viewing the storage account in the Portal

**Answer:** C) A ReadOnly lock prevents any write/modify operations, including regenerating access keys, uploading blobs, and modifying settings. Read operations like viewing and listing still work.

---

**Q12.** Which Traffic Manager routing method directs users to the endpoint with the lowest network latency?

A) Priority
B) Weighted
C) Geographic
D) Performance

**Answer:** D) Performance routing measures the latency from the user's DNS resolver to each endpoint region and returns the closest one.

---

**Q13.** You need to connect an App Service to a storage account's private endpoint. The App Service cannot resolve the private endpoint's FQDN. What is likely missing?

A) A service endpoint on the App Service subnet
B) A Private DNS zone linked to the App Service's VNet
C) An NSG rule allowing port 443
D) A public IP on the storage account

**Answer:** B) Private endpoints require a Private DNS zone (e.g., `privatelink.blob.core.windows.net`) linked to the VNet for proper FQDN resolution to the private IP.

---

**Q14.** You deploy a VMSS with a Rolling upgrade policy. What happens when you update the VM model?

A) All instances update simultaneously
B) Instances update in batches with a configurable pause between batches
C) Nothing — you must manually upgrade each instance
D) The VMSS creates new instances and deletes old ones

**Answer:** B) Rolling upgrade policy updates instances in batches. You configure max batch percentage and pause duration between batches.

---

**Q15.** Your backup policy retains daily backups for 7 days and weekly backups for 4 weeks. A VM is backed up every day. How many recovery points exist after 14 days?

A) 7
B) 9
C) 14
D) 11

**Answer:** B) 9 — 7 daily recovery points (last 7 days) plus 2 weekly recovery points (week 1 and week 2, where the daily points have expired but weekly retained).

---

### Knowledge Gaps

These skills are in the exam objectives but NOT covered in the cram session. Study these separately:

| Skill | Where to Learn |
|-------|---------------|
| Configure stored access policies | [Azure Storage docs](https://learn.microsoft.com/en-us/azure/storage/) |
| Configure blob versioning | [Azure Blob Storage docs](https://learn.microsoft.com/en-us/azure/storage/blobs/) |
| Configure encryption at host for VMs | [Azure VM docs](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes) |
| Configure certificates and TLS for App Service | [App Service docs](https://learn.microsoft.com/en-us/azure/app-service/) |
| Configure backup for App Service | [App Service docs](https://learn.microsoft.com/en-us/azure/app-service/) |
| Azure Site Recovery / failover | [Site Recovery docs](https://learn.microsoft.com/en-us/azure/site-recovery/) |
| Backup reports and alerts | [Azure Backup docs](https://learn.microsoft.com/en-us/azure/backup/) |
| Azure Backup vault vs Recovery Services vault | [Azure Backup docs](https://learn.microsoft.com/en-us/azure/backup/) |

---

### Official Resources

| Resource | Link |
|----------|------|
| Savill's AZ-104 Whiteboard | [View](https://github.com/johnthebrit/CertificationMaterials/blob/main/whiteboards/AZ-104-Whiteboard-v2.png) |
| Official Exam Study Guide | [View](https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/az-104) |
| Exam Registration & Learn Modules | [View](https://learn.microsoft.com/en-us/credentials/certifications/exams/az-104/) |
| Free Practice Assessment | [Take Now](https://learn.microsoft.com/en-us/credentials/certifications/exams/az-104/practice/assessment?assessment-type=practice&assessmentId=21) |
| Earn the Certification | [View](https://learn.microsoft.com/en-us/credentials/certifications/azure-administrator/) |
| Certification Renewal | [View](https://learn.microsoft.com/en-us/credentials/certifications/renew-your-microsoft-certification) |
| Exam Sandbox (try the interface) | [Try It](https://aka.ms/examdemo) |
| AZ-104 Video Playlist | [Watch](https://www.youtube.com/playlist?list=PLlVtbbG169nGlGPWs9xaLKT1KfwqREHbs) |
| Azure Pricing Calculator | [Use](https://azure.microsoft.com/pricing/calculator/) |
| Savill's Certification Repo | [View](https://github.com/johnthebrit/CertificationMaterials) |
| OnBoard to Azure Learning Path | [Start](https://learn.onboardtoazure.com) |
| Savill's FAQ | [View](https://savilltech.com/faq) |

---

### Recommended Study Schedule

#### Week 1: Identity, Governance & Networking Foundations
- **Day 1-2:** Module 01 (Identity) + Module 02 (Governance)
- **Day 3-4:** Module 03 (Networking) + Module 04 (DNS & Connectivity)
- **Day 5:** Review exercises for Modules 01-04
- **Weekend:** Watch cram session chapters 00:00–2:08:03

#### Week 2: Storage, Compute & Load Balancing
- **Day 1-2:** Module 06 (Storage)
- **Day 3-4:** Module 07 (Compute)
- **Day 5:** Module 05 (Load Balancing)
- **Weekend:** Watch cram session chapters 2:10:24–3:42:34

#### Week 3: Monitoring, Review & Practice
- **Day 1:** Module 08 (Monitoring & Backup)
- **Day 2-3:** Complete all exercises — focus on 🟡 and 🔴 difficulty
- **Day 4:** Study Knowledge Gaps (topics not in cram session)
- **Day 5:** Take the [Free Practice Assessment](https://learn.microsoft.com/en-us/credentials/certifications/exams/az-104/practice/assessment?assessment-type=practice&assessmentId=21)
- **Weekend:** Review weak areas, re-watch relevant cram session chapters

#### Week 4: Final Preparation
- **Day 1-2:** Retake practice assessment, aim for >80%
- **Day 3:** Review the Exam Readiness Checklist — fill gaps
- **Day 4:** Try the [Exam Sandbox](https://aka.ms/examdemo) to familiarize with interface
- **Day 5:** Light review only — rest before exam
- **Exam Day:** Confidence! You've got this. 🎯

---

### Next Steps

1. ✅ Complete all lab modules and exercises
2. 📝 Take the [Free Practice Assessment](https://learn.microsoft.com/en-us/credentials/certifications/exams/az-104/practice/assessment?assessment-type=practice&assessmentId=21)
3. 🧪 Try the [Exam Sandbox](https://aka.ms/examdemo) to experience the exam interface
4. 📅 [Register for AZ-104](https://learn.microsoft.com/en-us/credentials/certifications/exams/az-104/)
5. 🎓 [Earn your certification](https://learn.microsoft.com/en-us/credentials/certifications/azure-administrator/)
6. 🔄 [Plan for renewal](https://learn.microsoft.com/en-us/credentials/certifications/renew-your-microsoft-certification) (certifications expire annually)

---

> *Generated by CertForge v1.1 from [John Savill's AZ-104 Cram v2](https://www.youtube.com/watch?v=0Knf9nub4-k)*
