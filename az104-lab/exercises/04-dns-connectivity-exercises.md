# Exercise 04: DNS & Connectivity

[🎥 Cram Session: DNS & Connectivity (1:38:41–2:10:24)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=5921s)

> **Exam Domain**: Implement and manage virtual networking (15–20%)
>
> These exercises cover Azure DNS, Private DNS, UDRs, service endpoints, private endpoints, and Azure Bastion.

---

## Prerequisites

- An active Azure subscription with **Contributor** role
- Azure CLI v2.60+ authenticated (`az login`)
- Module 00 (Foundation) and Module 03 (Networking) exercises completed (or create equivalent VNets)

```bash
az group create --name rg-certlab-dns --location eastus \
  --tags Environment=certlab Module=dns-connectivity

# Create a VNet if not already available
az network vnet create \
  --name vnet-dns-lab \
  --resource-group rg-certlab-dns \
  --address-prefix 10.10.0.0/16 \
  --subnet-name snet-default \
  --subnet-prefix 10.10.0.0/24
```

---

## Exercise 4.1: Create a Public DNS Zone with Records

**Difficulty**: 🟢 Guided

**Objectives**:
- Create an Azure DNS zone
- Add A, CNAME, and TXT records
- Understand record types and TTL

[🎥 Azure DNS (1:38:41)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=5921s)

**Steps**:

1. Create a DNS zone (use a custom domain or a test domain):
   ```bash
   # Use a domain you own, or a lab domain for practice
   DNS_ZONE="certlab.example.com"

   az network dns zone create \
     --name "$DNS_ZONE" \
     --resource-group rg-certlab-dns \
     --tags Environment=certlab
   ```

2. Add an A record pointing to a web server:
   ```bash
   az network dns record-set a add-record \
     --zone-name "$DNS_ZONE" \
     --resource-group rg-certlab-dns \
     --record-set-name "www" \
     --ipv4-address 10.10.0.10

   # Set TTL to 300 seconds
   az network dns record-set a update \
     --zone-name "$DNS_ZONE" \
     --resource-group rg-certlab-dns \
     --name "www" \
     --set ttl=300
   ```

3. Add a CNAME record:
   ```bash
   az network dns record-set cname set-record \
     --zone-name "$DNS_ZONE" \
     --resource-group rg-certlab-dns \
     --record-set-name "blog" \
     --cname "www.${DNS_ZONE}"
   ```

4. Add a TXT record (commonly used for domain verification):
   ```bash
   az network dns record-set txt add-record \
     --zone-name "$DNS_ZONE" \
     --resource-group rg-certlab-dns \
     --record-set-name "@" \
     --value "v=spf1 include:_spf.example.com ~all"
   ```

5. Add an MX record:
   ```bash
   az network dns record-set mx add-record \
     --zone-name "$DNS_ZONE" \
     --resource-group rg-certlab-dns \
     --record-set-name "@" \
     --exchange "mail.${DNS_ZONE}" \
     --preference 10
   ```

6. List all records in the zone:
   ```bash
   az network dns record-set list \
     --zone-name "$DNS_ZONE" \
     --resource-group rg-certlab-dns \
     --query "[].{name:name, type:type, ttl:ttl}" --output table
   ```

7. View the NS records (Azure-assigned nameservers):
   ```bash
   az network dns zone show \
     --name "$DNS_ZONE" \
     --resource-group rg-certlab-dns \
     --query "nameServers" --output tsv
   ```

**Success Criteria**:
- [ ] DNS zone exists with A, CNAME, TXT, and MX records
- [ ] You can list the Azure-assigned nameservers for the zone
- [ ] You understand when to use each record type (A = IP, CNAME = alias, TXT = verification)

> 💡 **Exam Tip**: Azure DNS supports **alias record sets** which can point directly to Azure resources (Public IP, Traffic Manager, CDN). Alias records auto-update when the target resource's IP changes. The exam tests alias records vs standard records.

> ⚠️ **Common Mistake**: CNAME records cannot coexist with other record types at the same name. You cannot have both a CNAME and an A record for `www`. The apex/root (`@`) cannot be a CNAME — use an alias record instead.

---

## Exercise 4.2: Create a Private DNS Zone and Link to VNet

**Difficulty**: 🟢 Guided

**Objectives**:
- Create a Private DNS zone for internal name resolution
- Link the zone to a VNet with auto-registration enabled
- Understand how Private DNS resolves names within VNets

[🎥 Azure Private DNS (1:41:35)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=6095s)

**Steps**:

1. Create a Private DNS zone:
   ```bash
   az network private-dns zone create \
     --name "certlab.internal" \
     --resource-group rg-certlab-dns \
     --tags Environment=certlab
   ```

2. Link the zone to the VNet with auto-registration:
   ```bash
   az network private-dns link vnet create \
     --name "link-dns-lab" \
     --resource-group rg-certlab-dns \
     --zone-name "certlab.internal" \
     --virtual-network vnet-dns-lab \
     --registration-enabled true
   ```

3. Add a manual A record for a service:
   ```bash
   az network private-dns record-set a add-record \
     --zone-name "certlab.internal" \
     --resource-group rg-certlab-dns \
     --record-set-name "db" \
     --ipv4-address 10.10.0.50
   ```

4. Verify the link and records:
   ```bash
   echo "=== VNet Links ==="
   az network private-dns link vnet list \
     --zone-name "certlab.internal" \
     --resource-group rg-certlab-dns \
     --query "[].{name:name, vnet:virtualNetwork.id, registration:registrationEnabled}" \
     --output table

   echo "=== DNS Records ==="
   az network private-dns record-set list \
     --zone-name "certlab.internal" \
     --resource-group rg-certlab-dns \
     --query "[].{name:name, type:type, ttl:ttl}" --output table
   ```

5. **Explore**: Link the Private DNS zone to an additional VNet (if available from Module 03):
   ```bash
   # Read-only link (no auto-registration) — a zone supports auto-reg for only one VNet
   # but can have multiple read-only links
   az network private-dns link vnet create \
     --name "link-readonly" \
     --resource-group rg-certlab-dns \
     --zone-name "certlab.internal" \
     --virtual-network "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-certlab-networking/providers/Microsoft.Network/virtualNetworks/vnet-hub" \
     --registration-enabled false 2>/dev/null || echo "ℹ️ Hub VNet not found — skip this step if Module 03 is not deployed"
   ```

**Success Criteria**:
- [ ] Private DNS zone `certlab.internal` is created
- [ ] Zone is linked to VNet with auto-registration enabled
- [ ] Manual A record resolves `db.certlab.internal` to 10.10.0.50
- [ ] You understand that auto-registration creates A records automatically when VMs are created in the linked VNet

> 💡 **Exam Tip**: Private DNS zones support **auto-registration** — VMs created in a linked VNet automatically get an A record. Key limits: a VNet can link to only **one Private DNS zone with auto-registration** enabled, but can link to up to 1000 zones for resolution. The exam tests these limits.

---

## Exercise 4.3: Configure a Route Table with UDRs

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Create a route table with user-defined routes
- Understand next hop types (VirtualAppliance, VNetGateway, Internet, None)
- Associate route tables with subnets

[🎥 User Defined Routes (1:58:36)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7116s)

**Steps**:

1. Create a route table:
   ```bash
   az network route-table create \
     --name rt-spoke-default \
     --resource-group rg-certlab-dns \
     --disable-bgp-route-propagation false \
     --tags Environment=certlab
   ```

2. Add a route to send all traffic through a virtual appliance (NVA):
   ```bash
   az network route-table route create \
     --name route-to-nva \
     --route-table-name rt-spoke-default \
     --resource-group rg-certlab-dns \
     --address-prefix 0.0.0.0/0 \
     --next-hop-type VirtualAppliance \
     --next-hop-ip-address 10.0.0.4
   ```

3. Add a route to send traffic to a specific subnet via the VNet gateway:
   ```bash
   az network route-table route create \
     --name route-to-onprem \
     --route-table-name rt-spoke-default \
     --resource-group rg-certlab-dns \
     --address-prefix 192.168.0.0/16 \
     --next-hop-type VirtualNetworkGateway
   ```

4. Add a blackhole route to drop traffic to a specific range:
   ```bash
   az network route-table route create \
     --name route-blackhole \
     --route-table-name rt-spoke-default \
     --resource-group rg-certlab-dns \
     --address-prefix 172.16.0.0/12 \
     --next-hop-type None
   ```

5. List all routes:
   ```bash
   az network route-table route list \
     --route-table-name rt-spoke-default \
     --resource-group rg-certlab-dns \
     --query "[].{name:name, prefix:addressPrefix, nextHop:nextHopType, nextHopIP:nextHopIpAddress}" \
     --output table
   ```

6. Associate the route table with a subnet:
   ```bash
   az network vnet subnet update \
     --name snet-default \
     --resource-group rg-certlab-dns \
     --vnet-name vnet-dns-lab \
     --route-table rt-spoke-default
   ```

7. Verify the effective routes (requires a NIC in the subnet):
   ```bash
   # Create a test NIC
   az network nic create \
     --name nic-route-test \
     --resource-group rg-certlab-dns \
     --vnet-name vnet-dns-lab \
     --subnet snet-default

   # View effective routes
   az network nic show-effective-route-table \
     --name nic-route-test \
     --resource-group rg-certlab-dns \
     --query "value[].{source:source, prefix:addressPrefix[0], nextHop:nextHopType, nextHopIP:nextHopIpAddress[0]}" \
     --output table
   ```

**Success Criteria**:
- [ ] Route table has three UDRs with different next hop types
- [ ] Route table is associated with the subnet
- [ ] Effective routes show both system routes and UDRs
- [ ] You can explain each next hop type and when to use it

> 💡 **Exam Tip**: UDR next hop types to know:
> - **VirtualAppliance**: Forward to an NVA IP (firewall, router)
> - **VirtualNetworkGateway**: Forward to VPN/ExpressRoute gateway
> - **VirtualNetwork**: Route within the VNet (default behavior)
> - **Internet**: Route to the internet
> - **None**: Drop the traffic (blackhole)
>
> UDRs override system routes. The most specific prefix wins (longest prefix match).

---

## Exercise 4.4: Set Up a Service Endpoint for Storage

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Enable a service endpoint on a subnet
- Configure storage firewall to allow traffic only from the VNet
- Understand the difference between service endpoints and private endpoints

[🎥 Service Endpoints (1:59:55)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7195s)

**Steps**:

1. Enable the Microsoft.Storage service endpoint on the subnet:
   ```bash
   az network vnet subnet update \
     --name snet-default \
     --resource-group rg-certlab-dns \
     --vnet-name vnet-dns-lab \
     --service-endpoints Microsoft.Storage
   ```

2. Create a storage account:
   ```bash
   STORAGE_NAME="stdns$(date +%s | tail -c 9)"
   az storage account create \
     --name "$STORAGE_NAME" \
     --resource-group rg-certlab-dns \
     --sku Standard_LRS \
     --location eastus \
     --tags Environment=certlab
   echo "Storage account: $STORAGE_NAME"
   ```

3. Configure the storage firewall to allow only VNet traffic:
   ```bash
   # Set default action to Deny
   az storage account update \
     --name "$STORAGE_NAME" \
     --resource-group rg-certlab-dns \
     --default-action Deny

   # Add VNet rule
   SUBNET_ID=$(az network vnet subnet show \
     --name snet-default \
     --resource-group rg-certlab-dns \
     --vnet-name vnet-dns-lab \
     --query id -o tsv)

   az storage account network-rule add \
     --account-name "$STORAGE_NAME" \
     --resource-group rg-certlab-dns \
     --subnet "$SUBNET_ID"
   ```

4. Verify the network rules:
   ```bash
   az storage account show \
     --name "$STORAGE_NAME" \
     --resource-group rg-certlab-dns \
     --query "{defaultAction:networkRuleSet.defaultAction, vnets:networkRuleSet.virtualNetworkRules[].{subnet:virtualNetworkResourceId, action:action}}" \
     --output json
   ```

5. Test access from outside the VNet (should fail from CLI if not in the VNet):
   ```bash
   az storage container list --account-name "$STORAGE_NAME" --auth-mode login 2>&1 \
     || echo "⛔ Access denied — storage firewall is working!"
   ```

**Success Criteria**:
- [ ] Service endpoint enabled on the subnet
- [ ] Storage account firewall default action is "Deny"
- [ ] VNet subnet is whitelisted in storage network rules
- [ ] You can explain: service endpoints keep traffic on the Azure backbone but use the service's public IP

> 💡 **Exam Tip**: **Service endpoints** vs **Private endpoints** — the exam loves this comparison:
> | Feature | Service Endpoint | Private Endpoint |
> |---------|-----------------|-----------------|
> | IP used | Service's public IP | Private IP in your VNet |
> | DNS | No change | Requires Private DNS zone |
> | On-prem access | ❌ VNet traffic only | ✅ Via VPN/ExpressRoute |
> | Cost | Free | Per-hour + per-GB charge |
> | Scope | Subnet-level | Resource-level |

---

## Exercise 4.5: Create a Private Endpoint for Storage

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Create a private endpoint for a storage account
- Configure Private DNS for endpoint resolution
- Compare with service endpoints

[🎥 Private Endpoints (2:04:50)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7490s)

**Steps**:

1. Create a subnet for private endpoints:
   ```bash
   az network vnet subnet create \
     --name snet-private-endpoints \
     --resource-group rg-certlab-dns \
     --vnet-name vnet-dns-lab \
     --address-prefix 10.10.1.0/24
   ```

2. Create a private endpoint for the storage account:
   ```bash
   STORAGE_ID=$(az storage account show --name "$STORAGE_NAME" \
     --resource-group rg-certlab-dns --query id -o tsv)

   az network private-endpoint create \
     --name "pe-${STORAGE_NAME}" \
     --resource-group rg-certlab-dns \
     --vnet-name vnet-dns-lab \
     --subnet snet-private-endpoints \
     --private-connection-resource-id "$STORAGE_ID" \
     --group-id blob \
     --connection-name "pec-${STORAGE_NAME}"
   ```

3. Get the private IP assigned to the endpoint:
   ```bash
   az network private-endpoint show \
     --name "pe-${STORAGE_NAME}" \
     --resource-group rg-certlab-dns \
     --query "customDnsConfigs[].{fqdn:fqdn, ipAddresses:ipAddresses}" \
     --output json
   ```

4. Create a Private DNS zone for blob storage and link it:
   ```bash
   az network private-dns zone create \
     --name "privatelink.blob.core.windows.net" \
     --resource-group rg-certlab-dns

   az network private-dns link vnet create \
     --name "link-blob-dns" \
     --resource-group rg-certlab-dns \
     --zone-name "privatelink.blob.core.windows.net" \
     --virtual-network vnet-dns-lab \
     --registration-enabled false
   ```

5. Create a DNS zone group to auto-register the private endpoint:
   ```bash
   az network private-endpoint dns-zone-group create \
     --name "default" \
     --endpoint-name "pe-${STORAGE_NAME}" \
     --resource-group rg-certlab-dns \
     --private-dns-zone "privatelink.blob.core.windows.net" \
     --zone-name "blob"
   ```

6. Verify the DNS record was created:
   ```bash
   az network private-dns record-set list \
     --zone-name "privatelink.blob.core.windows.net" \
     --resource-group rg-certlab-dns \
     --query "[?type=='Microsoft.Network/privateDnsZones/A'].{name:name, ip:aRecords[0].ipv4Address}" \
     --output table
   ```

**Success Criteria**:
- [ ] Private endpoint exists with a private IP in the 10.10.1.0/24 range
- [ ] Private DNS zone `privatelink.blob.core.windows.net` has an A record for the storage account
- [ ] You understand: traffic now goes to the private IP instead of the public endpoint
- [ ] You can explain why DNS configuration is critical for private endpoints

> 💡 **Exam Tip**: Private endpoints require **DNS configuration** to work correctly. Without the Private DNS zone, clients will still resolve to the public IP. The DNS zone must follow the naming pattern: `privatelink.<service>.core.windows.net`. The exam tests this DNS requirement heavily.

> ⚠️ **Common Mistake**: Forgetting to create the Private DNS zone or VNet link. The private endpoint will exist, but name resolution will still go to the public IP, bypassing the private endpoint entirely.

---

## Exercise 4.6: Design DNS for a Hybrid Environment

**Difficulty**: 🔴 Challenge

**Objectives**:
- Design DNS resolution for Azure + on-premises connectivity
- Configure conditional forwarding concepts
- Handle private endpoint resolution from on-premises

**Scenario**:

> *"VMs in spoke1 need to resolve storage account private endpoints. On-premises servers also need to resolve Azure private endpoints via a VPN connection. Design the complete DNS configuration."*

**Your Task**:

1. Document the DNS resolution flow for each scenario:

   **Scenario A**: VM in spoke1 resolves `mystorageacct.blob.core.windows.net`
   ```
   Flow: VM → Azure DNS (168.63.129.16) → Private DNS zone → Private IP
   
   Required configuration:
   - Private DNS zone: privatelink.blob.core.windows.net
   - VNet link from spoke1 VNet to the Private DNS zone
   - Private endpoint with DNS zone group
   ```

   **Scenario B**: On-premises server resolves `mystorageacct.blob.core.windows.net`
   ```
   Flow: Server → On-prem DNS → Conditional forwarder → Azure DNS Private Resolver → Private DNS zone → Private IP
   
   Required configuration:
   - Azure DNS Private Resolver with inbound endpoint in hub VNet
   - On-prem DNS conditional forwarder for *.blob.core.windows.net → Private Resolver IP
   - Private DNS zone linked to the resolver's VNet
   ```

2. Design the architecture (fill in):

   | Component | Location | Purpose |
   |-----------|----------|---------|
   | Private DNS Zone | `rg-certlab-dns` | Store private endpoint A records |
   | VNet Link (spoke1) | Linked to `vnet-spoke1` | Allow spoke1 VMs to resolve |
   | VNet Link (hub) | Linked to `vnet-hub` | Allow hub services to resolve |
   | DNS Private Resolver | Hub VNet, dedicated subnet | Forward on-prem queries to Azure DNS |
   | On-prem DNS Forwarder | On-premises | Conditional forward to Azure |

3. Create the DNS Private Resolver (if budget allows):
   ```bash
   # Create a subnet for the resolver (minimum /28)
   az network vnet subnet create \
     --name snet-dns-resolver-inbound \
     --resource-group rg-certlab-dns \
     --vnet-name vnet-dns-lab \
     --address-prefix 10.10.2.0/28 \
     --delegations "Microsoft.Network/dnsResolvers"

   # Create the resolver
   az dns-resolver create \
     --name "dnspr-certlab" \
     --resource-group rg-certlab-dns \
     --location eastus \
     --id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-certlab-dns/providers/Microsoft.Network/virtualNetworks/vnet-dns-lab"

   # Create inbound endpoint
   az dns-resolver inbound-endpoint create \
     --name "inbound-endpoint" \
     --dns-resolver-name "dnspr-certlab" \
     --resource-group rg-certlab-dns \
     --location eastus \
     --ip-configurations "[{\"private-ip-allocation-method\":\"Dynamic\",\"id\":\"/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-certlab-dns/providers/Microsoft.Network/virtualNetworks/vnet-dns-lab/subnets/snet-dns-resolver-inbound\"}]"
   ```

4. **Design Questions** (answer these):
   - Why can't on-premises servers use 168.63.129.16 directly?
   - What happens if the Private DNS zone is not linked to the VNet where the resolver lives?
   - How would you handle DNS resolution for multiple private endpoint types (blob, table, queue)?

**Success Criteria**:
- [ ] You documented the DNS resolution flow for both Azure VMs and on-premises servers
- [ ] You understand why a DNS Private Resolver is needed for hybrid scenarios
- [ ] You can answer: 168.63.129.16 is only accessible from within Azure VNets — on-prem servers cannot reach it
- [ ] Your design handles multiple private endpoint DNS zones

> 💡 **Exam Tip**: **Azure Bastion** SKUs to know for connectivity:
> - **Developer**: Free-tier, no dedicated deployment, one VM at a time
> - **Basic**: Dedicated deployment, supports multiple sessions, RDP/SSH
> - **Standard**: All Basic features + native client support, IP-based connection, shareable link
>
> [🎥 Azure Bastion (2:08:03)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7683s)

> 📖 **Deep Dive**: [Azure DNS Private Resolver](https://learn.microsoft.com/en-us/azure/dns/) | [Azure Bastion](https://learn.microsoft.com/en-us/azure/bastion/)

---

## Clean Up

```bash
# Remove private endpoint and DNS zone group
az network private-endpoint delete --name "pe-${STORAGE_NAME}" \
  --resource-group rg-certlab-dns --no-wait 2>/dev/null

# Remove DNS resolver (if created)
az dns-resolver inbound-endpoint delete --name "inbound-endpoint" \
  --dns-resolver-name "dnspr-certlab" --resource-group rg-certlab-dns --yes 2>/dev/null
az dns-resolver delete --name "dnspr-certlab" \
  --resource-group rg-certlab-dns --yes 2>/dev/null

# Remove private DNS zones and links
az network private-dns link vnet delete --name "link-blob-dns" \
  --zone-name "privatelink.blob.core.windows.net" --resource-group rg-certlab-dns --yes 2>/dev/null
az network private-dns link vnet delete --name "link-dns-lab" \
  --zone-name "certlab.internal" --resource-group rg-certlab-dns --yes 2>/dev/null
az network private-dns link vnet delete --name "link-readonly" \
  --zone-name "certlab.internal" --resource-group rg-certlab-dns --yes 2>/dev/null
az network private-dns zone delete --name "privatelink.blob.core.windows.net" \
  --resource-group rg-certlab-dns --yes 2>/dev/null
az network private-dns zone delete --name "certlab.internal" \
  --resource-group rg-certlab-dns --yes 2>/dev/null

# Remove public DNS zone
az network dns zone delete --name "$DNS_ZONE" --resource-group rg-certlab-dns --yes 2>/dev/null

# Remove NICs and route tables
az network nic delete --name nic-route-test --resource-group rg-certlab-dns 2>/dev/null
az network route-table delete --name rt-spoke-default --resource-group rg-certlab-dns 2>/dev/null

# Remove resource group
az group delete --name rg-certlab-dns --yes --no-wait

echo "✅ DNS & connectivity lab resources cleaned up"
```

---

## Key Concepts for the Exam

| Concept | Details |
|---------|---------|
| DNS Record Types | A (IPv4), AAAA (IPv6), CNAME (alias), MX (mail), TXT (verification), NS (nameserver) |
| Alias Records | Point to Azure resources; auto-update when IP changes |
| Private DNS | Auto-registration creates A records for VMs; max 1 auto-reg VNet per zone |
| UDR Next Hops | VirtualAppliance, VirtualNetworkGateway, VirtualNetwork, Internet, None |
| Service Endpoints | Free, subnet-level, public IP, VNet traffic only |
| Private Endpoints | Per-hour cost, private IP, requires DNS config, works from on-prem |
| DNS Private Resolver | Enables on-prem to resolve Azure Private DNS zones |
| Bastion SKUs | Developer (free/limited), Basic (dedicated), Standard (full features) |

---

*Previous: [Exercise 03 — Networking](03-networking-exercises.md) | Next: [Exercise 05 — Load Balancing](05-load-balancing-exercises.md)*
