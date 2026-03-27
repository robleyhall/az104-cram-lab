# Exercise 03: Virtual Networking

[🎥 Cram Session: Networking (1:09:28–1:38:41)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=4168s)

> **Exam Domain**: Implement and manage virtual networking (15–20%)
>
> These exercises cover VNets, subnets, NSGs, ASGs, VNet peering, and network security.

---

## Prerequisites

- An active Azure subscription with **Contributor** role
- Azure CLI v2.60+ authenticated (`az login`)
- Module 00 (Foundation) deployed

```bash
az group create --name rg-certlab-networking --location eastus \
  --tags Environment=certlab Module=networking
```

---

## Exercise 3.1: Create VNets and Subnets

**Difficulty**: 🟢 Guided

**Objectives**:
- Create virtual networks with specific address spaces
- Add subnets with appropriate CIDR ranges
- Verify address space allocation and overlap rules

[🎥 Virtual Network (1:10:15)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=4215s)

**Steps**:

1. Create a hub VNet:
   ```bash
   az network vnet create \
     --name vnet-hub \
     --resource-group rg-certlab-networking \
     --address-prefix 10.0.0.0/16 \
     --subnet-name snet-shared \
     --subnet-prefix 10.0.0.0/24 \
     --tags Environment=certlab Role=hub
   ```

2. Add additional subnets to the hub:
   ```bash
   az network vnet subnet create \
     --name snet-management \
     --resource-group rg-certlab-networking \
     --vnet-name vnet-hub \
     --address-prefix 10.0.1.0/24

   az network vnet subnet create \
     --name AzureBastionSubnet \
     --resource-group rg-certlab-networking \
     --vnet-name vnet-hub \
     --address-prefix 10.0.2.0/26
   ```

3. Create spoke VNets:
   ```bash
   az network vnet create \
     --name vnet-spoke1 \
     --resource-group rg-certlab-networking \
     --address-prefix 10.1.0.0/16 \
     --subnet-name snet-web \
     --subnet-prefix 10.1.0.0/24 \
     --tags Environment=certlab Role=spoke

   az network vnet create \
     --name vnet-spoke2 \
     --resource-group rg-certlab-networking \
     --address-prefix 10.2.0.0/16 \
     --subnet-name snet-app \
     --subnet-prefix 10.2.0.0/24 \
     --tags Environment=certlab Role=spoke
   ```

4. Add a backend subnet to spoke2:
   ```bash
   az network vnet subnet create \
     --name snet-db \
     --resource-group rg-certlab-networking \
     --vnet-name vnet-spoke2 \
     --address-prefix 10.2.1.0/24
   ```

5. Verify all VNets and subnets:
   ```bash
   echo "=== Hub VNet ==="
   az network vnet show --name vnet-hub --resource-group rg-certlab-networking \
     --query "{name:name, addressSpace:addressSpace.addressPrefixes, subnets:subnets[].{name:name, prefix:addressPrefix}}" \
     --output json

   echo "=== Spoke VNets ==="
   az network vnet list --resource-group rg-certlab-networking \
     --query "[].{name:name, addressSpace:addressSpace.addressPrefixes[0]}" --output table
   ```

6. **Verify**: Try to create an overlapping subnet (should fail):
   ```bash
   az network vnet subnet create \
     --name snet-overlap-test \
     --resource-group rg-certlab-networking \
     --vnet-name vnet-hub \
     --address-prefix 10.0.0.128/25 2>&1 || echo "⛔ Overlap detected — subnet rejected!"
   ```

**Success Criteria**:
- [ ] Hub VNet (10.0.0.0/16) has 3 subnets with no overlap
- [ ] Two spoke VNets with non-overlapping address spaces (10.1.0.0/16, 10.2.0.0/16)
- [ ] Overlapping subnet creation is correctly rejected
- [ ] You can explain why VNet address spaces must not overlap for peering

> 💡 **Exam Tip**: Azure reserves **5 IP addresses** in each subnet: network address, default gateway, 2 for Azure DNS mapping, and broadcast. So a /24 gives 251 usable IPs, not 256. The exam often asks: "How many usable IPs does a /26 subnet have?" Answer: 64 − 5 = **59**.

> ⚠️ **Common Mistake**: Naming the Bastion subnet anything other than `AzureBastionSubnet` — it **must** be this exact name. Similarly, `GatewaySubnet` is required for VPN/ExpressRoute gateways.

---

## Exercise 3.2: Create and Configure NSG Rules

**Difficulty**: 🟢 Guided

**Objectives**:
- Create an NSG and understand default rules
- Add inbound and outbound security rules with priorities
- Associate NSGs with subnets

[🎥 Network Security Group (1:28:47)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=5327s)

**Steps**:

1. Create an NSG for the web tier:
   ```bash
   az network nsg create \
     --name nsg-web \
     --resource-group rg-certlab-networking \
     --tags Environment=certlab Tier=web
   ```

2. View the default rules (three inbound, three outbound):
   ```bash
   az network nsg rule list \
     --nsg-name nsg-web \
     --resource-group rg-certlab-networking \
     --include-default \
     --query "[].{name:name, priority:priority, direction:direction, access:access, source:sourceAddressPrefix, dest:destinationAddressPrefix, port:destinationPortRange}" \
     --output table
   ```

3. Add a rule to allow HTTP traffic from the internet:
   ```bash
   az network nsg rule create \
     --nsg-name nsg-web \
     --resource-group rg-certlab-networking \
     --name AllowHTTP \
     --priority 100 \
     --direction Inbound \
     --access Allow \
     --protocol Tcp \
     --source-address-prefixes Internet \
     --destination-port-ranges 80 443 \
     --description "Allow HTTP and HTTPS from internet"
   ```

4. Add a rule to allow SSH only from the management subnet:
   ```bash
   az network nsg rule create \
     --nsg-name nsg-web \
     --resource-group rg-certlab-networking \
     --name AllowSSHFromMgmt \
     --priority 110 \
     --direction Inbound \
     --access Allow \
     --protocol Tcp \
     --source-address-prefixes 10.0.1.0/24 \
     --destination-port-ranges 22 \
     --description "Allow SSH from management subnet only"
   ```

5. Add a rule to explicitly deny all other inbound traffic:
   ```bash
   az network nsg rule create \
     --nsg-name nsg-web \
     --resource-group rg-certlab-networking \
     --name DenyAllInbound \
     --priority 4000 \
     --direction Inbound \
     --access Deny \
     --protocol '*' \
     --source-address-prefixes '*' \
     --destination-port-ranges '*' \
     --description "Deny all other inbound traffic"
   ```

6. Associate the NSG with the web subnet:
   ```bash
   az network vnet subnet update \
     --name snet-web \
     --resource-group rg-certlab-networking \
     --vnet-name vnet-spoke1 \
     --network-security-group nsg-web
   ```

7. Verify the association:
   ```bash
   az network vnet subnet show \
     --name snet-web \
     --resource-group rg-certlab-networking \
     --vnet-name vnet-spoke1 \
     --query "{subnet:name, nsg:networkSecurityGroup.id}" --output json
   ```

**Success Criteria**:
- [ ] NSG has custom rules for HTTP (100), SSH (110), and DenyAll (4000)
- [ ] NSG is associated with snet-web subnet
- [ ] Default rules are still present alongside custom rules
- [ ] You can explain how priority numbers determine rule evaluation order

> 💡 **Exam Tip**: NSG rules are evaluated by **priority** (lowest number = highest priority). Rules are evaluated in order until a match is found. Default rules have priorities 65000–65500 and **cannot be deleted** but can be overridden by lower-priority custom rules. The exam tests priority ordering extensively.

---

## Exercise 3.3: Set Up VNet Peering and Test Connectivity

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Create bidirectional VNet peering
- Understand that peering is non-transitive
- Configure peering settings (traffic forwarding, gateway transit)

[🎥 Peering (1:20:00)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=4800s)

**Steps**:

1. Create peering from hub to spoke1:
   ```bash
   az network vnet peering create \
     --name hub-to-spoke1 \
     --resource-group rg-certlab-networking \
     --vnet-name vnet-hub \
     --remote-vnet vnet-spoke1 \
     --allow-vnet-access true \
     --allow-forwarded-traffic true
   ```

2. Create the reverse peering from spoke1 to hub:
   ```bash
   az network vnet peering create \
     --name spoke1-to-hub \
     --resource-group rg-certlab-networking \
     --vnet-name vnet-spoke1 \
     --remote-vnet vnet-hub \
     --allow-vnet-access true \
     --allow-forwarded-traffic true
   ```

3. Create peering between hub and spoke2:
   ```bash
   az network vnet peering create \
     --name hub-to-spoke2 \
     --resource-group rg-certlab-networking \
     --vnet-name vnet-hub \
     --remote-vnet vnet-spoke2 \
     --allow-vnet-access true \
     --allow-forwarded-traffic true

   az network vnet peering create \
     --name spoke2-to-hub \
     --resource-group rg-certlab-networking \
     --vnet-name vnet-spoke2 \
     --remote-vnet vnet-hub \
     --allow-vnet-access true \
     --allow-forwarded-traffic true
   ```

4. Verify peering status (both sides must show "Connected"):
   ```bash
   echo "=== Hub peerings ==="
   az network vnet peering list \
     --resource-group rg-certlab-networking \
     --vnet-name vnet-hub \
     --query "[].{name:name, state:peeringState, remoteVnet:remoteVirtualNetwork.id}" \
     --output table

   echo "=== Spoke1 peerings ==="
   az network vnet peering list \
     --resource-group rg-certlab-networking \
     --vnet-name vnet-spoke1 \
     --query "[].{name:name, state:peeringState}" --output table
   ```

5. **Key question**: Can spoke1 (10.1.0.0/16) communicate directly with spoke2 (10.2.0.0/16)?

   Think about it, then verify:
   ```bash
   # Check if spoke1 has peering to spoke2
   az network vnet peering list \
     --resource-group rg-certlab-networking \
     --vnet-name vnet-spoke1 \
     --query "[?contains(remoteVirtualNetwork.id,'spoke2')]" --output table
   ```

6. **Explore**: Examine the peering settings:
   ```bash
   az network vnet peering show \
     --name hub-to-spoke1 \
     --resource-group rg-certlab-networking \
     --vnet-name vnet-hub \
     --query "{allowVnetAccess:allowVirtualNetworkAccess, allowForwarded:allowForwardedTraffic, allowGatewayTransit:allowGatewayTransit, useRemoteGateways:useRemoteGateways}"
   ```

**Success Criteria**:
- [ ] Hub ↔ Spoke1 peering shows "Connected" on both sides
- [ ] Hub ↔ Spoke2 peering shows "Connected" on both sides
- [ ] You understand that Spoke1 ↔ Spoke2 cannot communicate directly (peering is NOT transitive)
- [ ] You can explain when to use `allowGatewayTransit` and `useRemoteGateways`

> 💡 **Exam Tip**: **VNet peering is NOT transitive!** If VNet-A peers with VNet-B, and VNet-B peers with VNet-C, VNet-A cannot reach VNet-C through VNet-B unless you configure UDR forwarding through an NVA or use Azure Virtual Network Manager. This is one of the most commonly tested networking concepts.

> ⚠️ **Common Mistake**: Creating peering in only one direction. VNet peering requires **two peering links** — one from each VNet. If only one side is configured, the state will show "Initiated" (not "Connected") and traffic won't flow.

---

## Exercise 3.4: Create ASGs and Use in NSG Rules

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Create Application Security Groups for logical grouping
- Use ASGs in NSG rules instead of IP addresses
- Understand the benefits of ASG-based rules

[🎥 NSG & ASG (1:28:47)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=5327s)

**Steps**:

1. Create ASGs for different application tiers:
   ```bash
   az network asg create \
     --name asg-webservers \
     --resource-group rg-certlab-networking \
     --tags Environment=certlab

   az network asg create \
     --name asg-appservers \
     --resource-group rg-certlab-networking \
     --tags Environment=certlab

   az network asg create \
     --name asg-dbservers \
     --resource-group rg-certlab-networking \
     --tags Environment=certlab
   ```

2. Create an NSG with ASG-based rules:
   ```bash
   az network nsg create \
     --name nsg-app-tier \
     --resource-group rg-certlab-networking \
     --tags Environment=certlab
   ```

3. Allow web servers to communicate with app servers on port 8080:
   ```bash
   az network nsg rule create \
     --nsg-name nsg-app-tier \
     --resource-group rg-certlab-networking \
     --name AllowWebToApp \
     --priority 100 \
     --direction Inbound \
     --access Allow \
     --protocol Tcp \
     --source-asgs asg-webservers \
     --destination-asgs asg-appservers \
     --destination-port-ranges 8080 \
     --description "Allow web tier to app tier on port 8080"
   ```

4. Allow app servers to communicate with DB servers on port 1433:
   ```bash
   az network nsg rule create \
     --nsg-name nsg-app-tier \
     --resource-group rg-certlab-networking \
     --name AllowAppToDb \
     --priority 110 \
     --direction Inbound \
     --access Allow \
     --protocol Tcp \
     --source-asgs asg-appservers \
     --destination-asgs asg-dbservers \
     --destination-port-ranges 1433 \
     --description "Allow app tier to database tier on port 1433"
   ```

5. Deny direct internet access to app and DB servers:
   ```bash
   az network nsg rule create \
     --nsg-name nsg-app-tier \
     --resource-group rg-certlab-networking \
     --name DenyInternetToBackend \
     --priority 200 \
     --direction Inbound \
     --access Deny \
     --protocol '*' \
     --source-address-prefixes Internet \
     --destination-asgs asg-appservers asg-dbservers \
     --destination-port-ranges '*' \
     --description "Block direct internet access to app and db tiers"
   ```

6. List all rules to verify:
   ```bash
   az network nsg rule list \
     --nsg-name nsg-app-tier \
     --resource-group rg-certlab-networking \
     --query "[].{name:name, priority:priority, access:access, srcASG:sourceApplicationSecurityGroups[0].id, dstASG:destinationApplicationSecurityGroups[0].id, port:destinationPortRange}" \
     --output table
   ```

**Success Criteria**:
- [ ] Three ASGs created (web, app, db)
- [ ] NSG rules use ASGs instead of IP addresses
- [ ] Traffic flow: Internet → Web ✅ | Web → App:8080 ✅ | App → DB:1433 ✅ | Internet → App ❌ | Internet → DB ❌
- [ ] You can explain why ASGs are easier to maintain than IP-based rules

> 💡 **Exam Tip**: ASGs allow you to group NICs logically and use those groups in NSG rules. This is much more maintainable than IP-based rules because when VMs scale, you just add the NIC to the ASG — no rule changes needed. **Key constraint**: All NICs in the same ASG must be in the same VNet.

---

## Exercise 3.5: Evaluate Effective Security Rules

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Understand how multiple NSGs combine (subnet + NIC level)
- Use Azure CLI to check effective security rules
- Troubleshoot connectivity issues using effective rules

**Steps**:

1. Create a test NIC to examine effective rules:
   ```bash
   az network nic create \
     --name nic-test-web \
     --resource-group rg-certlab-networking \
     --vnet-name vnet-spoke1 \
     --subnet snet-web \
     --tags Environment=certlab
   ```

2. Check the effective security rules on the NIC:
   ```bash
   az network nic list-effective-nsg \
     --name nic-test-web \
     --resource-group rg-certlab-networking \
     --query "value[0].effectiveSecurityRules[].{name:name, protocol:protocol, srcPrefix:sourceAddressPrefix, dstPort:destinationPortRange, access:access, priority:priority, direction:direction}" \
     --output table
   ```

3. Add an NSG directly to the NIC (creating a two-level NSG):
   ```bash
   az network nsg create \
     --name nsg-nic-level \
     --resource-group rg-certlab-networking

   az network nsg rule create \
     --nsg-name nsg-nic-level \
     --resource-group rg-certlab-networking \
     --name AllowHTTPSOnly \
     --priority 100 \
     --direction Inbound \
     --access Allow \
     --protocol Tcp \
     --source-address-prefixes '*' \
     --destination-port-ranges 443

   az network nic update \
     --name nic-test-web \
     --resource-group rg-certlab-networking \
     --network-security-group nsg-nic-level
   ```

4. Re-check effective rules (now combining subnet NSG + NIC NSG):
   ```bash
   az network nic list-effective-nsg \
     --name nic-test-web \
     --resource-group rg-certlab-networking \
     --query "value[].effectiveSecurityRules[?direction=='Inbound'].{name:name, protocol:protocol, dstPort:destinationPortRange, access:access, priority:priority}" \
     --output table
   ```

5. **Question**: If the subnet NSG allows port 80 but the NIC NSG does not allow port 80, can traffic reach the VM on port 80?

**Success Criteria**:
- [ ] You can view effective security rules combining subnet + NIC NSGs
- [ ] You understand that traffic must be allowed by BOTH NSGs (most restrictive wins)
- [ ] Answer: No — traffic must pass through both the subnet NSG AND NIC NSG. Both must allow it.

> 💡 **Exam Tip**: When both a subnet NSG and a NIC NSG exist, inbound traffic must be allowed by **both** (subnet first, then NIC). It's like two firewalls in series — traffic passes through both. For outbound traffic, the order is reversed: NIC first, then subnet. The exam tests this "most restrictive wins" concept.

---

## Exercise 3.6: Design a Hub-Spoke Topology with Tiered NSG Rules

**Difficulty**: 🔴 Challenge

**Objectives**:
- Design a complete network security architecture
- Implement NSG rules for a multi-tier application
- Validate traffic flows against requirements

**Scenario**:

> *"Web servers need to talk to app servers on port 8080, but app servers should not be accessible from the internet. Database servers should only accept traffic from app servers on port 1433. Management access (SSH/RDP) should only come through the hub network's management subnet."*

**Requirements**:

| Source | Destination | Port | Allow/Deny |
|--------|------------|------|------------|
| Internet | Web Servers | 80, 443 | ✅ Allow |
| Web Servers | App Servers | 8080 | ✅ Allow |
| App Servers | DB Servers | 1433 | ✅ Allow |
| Hub Management (10.0.1.0/24) | All Servers | 22, 3389 | ✅ Allow |
| Internet | App Servers | Any | ❌ Deny |
| Internet | DB Servers | Any | ❌ Deny |
| Any | Any | Any | ❌ Deny (default) |

**Your Task**:

1. Design NSG rules for each tier (web, app, db) using the ASGs from Exercise 3.4

2. Create an NSG for the app subnet:
   ```bash
   az network nsg create \
     --name nsg-app-subnet \
     --resource-group rg-certlab-networking

   # Rule 1: Allow traffic from web ASG on port 8080
   az network nsg rule create \
     --nsg-name nsg-app-subnet \
     --resource-group rg-certlab-networking \
     --name AllowFromWebTier \
     --priority 100 --direction Inbound --access Allow \
     --protocol Tcp --source-asgs asg-webservers \
     --destination-port-ranges 8080

   # Rule 2: Allow SSH from management subnet
   az network nsg rule create \
     --nsg-name nsg-app-subnet \
     --resource-group rg-certlab-networking \
     --name AllowSSHFromMgmt \
     --priority 110 --direction Inbound --access Allow \
     --protocol Tcp --source-address-prefixes 10.0.1.0/24 \
     --destination-port-ranges 22 3389

   # Rule 3: Deny everything else from internet
   az network nsg rule create \
     --nsg-name nsg-app-subnet \
     --resource-group rg-certlab-networking \
     --name DenyInternetInbound \
     --priority 4000 --direction Inbound --access Deny \
     --protocol '*' --source-address-prefixes Internet \
     --destination-port-ranges '*'
   ```

3. Create an NSG for the database subnet:
   ```bash
   az network nsg create \
     --name nsg-db-subnet \
     --resource-group rg-certlab-networking

   # Only allow SQL from app tier
   az network nsg rule create \
     --nsg-name nsg-db-subnet \
     --resource-group rg-certlab-networking \
     --name AllowSQLFromAppTier \
     --priority 100 --direction Inbound --access Allow \
     --protocol Tcp --source-asgs asg-appservers \
     --destination-port-ranges 1433

   # Allow management access
   az network nsg rule create \
     --nsg-name nsg-db-subnet \
     --resource-group rg-certlab-networking \
     --name AllowMgmtAccess \
     --priority 110 --direction Inbound --access Allow \
     --protocol Tcp --source-address-prefixes 10.0.1.0/24 \
     --destination-port-ranges 22 3389

   # Deny all other inbound
   az network nsg rule create \
     --nsg-name nsg-db-subnet \
     --resource-group rg-certlab-networking \
     --name DenyAllInbound \
     --priority 4000 --direction Inbound --access Deny \
     --protocol '*' --source-address-prefixes '*' \
     --destination-port-ranges '*'
   ```

4. Associate NSGs with subnets:
   ```bash
   az network vnet subnet update \
     --name snet-app --resource-group rg-certlab-networking \
     --vnet-name vnet-spoke2 --network-security-group nsg-app-subnet

   az network vnet subnet update \
     --name snet-db --resource-group rg-certlab-networking \
     --vnet-name vnet-spoke2 --network-security-group nsg-db-subnet
   ```

5. Document your design — validate every requirement row:
   ```bash
   echo "=== Web NSG Rules ==="
   az network nsg rule list --nsg-name nsg-web \
     --resource-group rg-certlab-networking \
     --query "[].{name:name, priority:priority, access:access, port:destinationPortRange}" -o table

   echo "=== App NSG Rules ==="
   az network nsg rule list --nsg-name nsg-app-subnet \
     --resource-group rg-certlab-networking \
     --query "[].{name:name, priority:priority, access:access, port:destinationPortRange}" -o table

   echo "=== DB NSG Rules ==="
   az network nsg rule list --nsg-name nsg-db-subnet \
     --resource-group rg-certlab-networking \
     --query "[].{name:name, priority:priority, access:access, port:destinationPortRange}" -o table
   ```

**Success Criteria**:
- [ ] Every requirement from the table is implemented
- [ ] Traffic flows match the allowed/denied patterns exactly
- [ ] Management access (SSH/RDP) is restricted to the hub management subnet
- [ ] No unnecessary "allow all" rules exist

> 💡 **Exam Tip**: The exam often presents a scenario with multiple tiers and asks you to choose the correct NSG rules. Remember: NSG rules are **stateful** — if you allow inbound traffic, the return traffic is automatically allowed. You don't need separate outbound rules for response traffic.

> 📖 **Deep Dive**: [NSG Documentation](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)

---

## Clean Up

```bash
# Remove NIC
az network nic delete --name nic-test-web --resource-group rg-certlab-networking --no-wait

# Remove NSG associations from subnets (set to empty)
for subnet_vnet in "snet-web vnet-spoke1" "snet-app vnet-spoke2" "snet-db vnet-spoke2"; do
  snet=$(echo $subnet_vnet | cut -d' ' -f1)
  vnet=$(echo $subnet_vnet | cut -d' ' -f2)
  az network vnet subnet update --name "$snet" --resource-group rg-certlab-networking \
    --vnet-name "$vnet" --network-security-group "" 2>/dev/null
done

# Remove VNet peerings
az network vnet peering delete --name hub-to-spoke1 --resource-group rg-certlab-networking --vnet-name vnet-hub 2>/dev/null
az network vnet peering delete --name spoke1-to-hub --resource-group rg-certlab-networking --vnet-name vnet-spoke1 2>/dev/null
az network vnet peering delete --name hub-to-spoke2 --resource-group rg-certlab-networking --vnet-name vnet-hub 2>/dev/null
az network vnet peering delete --name spoke2-to-hub --resource-group rg-certlab-networking --vnet-name vnet-spoke2 2>/dev/null

# Remove resource group (removes all networking resources)
az group delete --name rg-certlab-networking --yes --no-wait

echo "✅ Networking lab resources cleaned up"
```

---

## Key Concepts for the Exam

| Concept | Details |
|---------|---------|
| Reserved IPs | Azure reserves **5 IPs per subnet** (.0, .1, .2, .3, .255) |
| NSG Priority | Lower number = higher priority; range 100–4096; default rules 65000–65500 |
| NSG Statefulness | NSG rules are **stateful** — return traffic is automatic |
| NSG Levels | Subnet NSG + NIC NSG — traffic must pass **both** |
| VNet Peering | **Not transitive**; requires peering on both sides; address spaces must not overlap |
| ASGs | Logical NIC grouping for rules; all members must be in the same VNet |
| Special Subnets | `AzureBastionSubnet` (min /26), `GatewaySubnet` — exact names required |
| Default Rules | AllowVNetInBound, AllowAzureLoadBalancerInBound, DenyAllInBound (and outbound equivalents) |

---

*Previous: [Exercise 02 — Governance](02-governance-exercises.md) | Next: [Exercise 04 — DNS & Connectivity](04-dns-connectivity-exercises.md)*
