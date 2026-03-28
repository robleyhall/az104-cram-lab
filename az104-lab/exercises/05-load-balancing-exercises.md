# Exercise 05: Load Balancing

[🎥 Cram Session: Load Balancing (2:10:24–2:31:50)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7824s)

> **Exam Domain**: Implement and manage virtual networking (15–20%)
>
> These exercises cover Azure Load Balancer, Application Gateway, Traffic Manager, and Front Door.

---

## Prerequisites

- An active Azure subscription with **Contributor** role
- Azure CLI v2.60+ authenticated (`az login`)
- Module 00 (Foundation) deployed

```bash
az group create --name rg-az104-lab-lb --location eastus \
  --tags Environment=az104-lab Module=load-balancing

# Create a VNet for load balancing exercises
az network vnet create \
  --name vnet-lb-lab \
  --resource-group rg-az104-lab-lb \
  --address-prefix 10.20.0.0/16 \
  --subnet-name snet-web \
  --subnet-prefix 10.20.0.0/24
```

---

## Load Balancer Comparison Table

Before starting the exercises, understand when to use each service:

| Feature | Azure Load Balancer | Application Gateway | Traffic Manager | Front Door |
|---------|-------------------|-------------------|----------------|------------|
| **OSI Layer** | Layer 4 (TCP/UDP) | Layer 7 (HTTP/S) | DNS-based | Layer 7 (HTTP/S) |
| **Scope** | Regional | Regional | Global | Global |
| **Protocol** | Any TCP/UDP | HTTP, HTTPS, WebSocket | Any (DNS) | HTTP, HTTPS |
| **SSL Offload** | ❌ | ✅ | ❌ | ✅ |
| **URL Routing** | ❌ | ✅ | ❌ | ✅ |
| **WAF** | ❌ | ✅ | ❌ | ✅ |
| **Health Probes** | TCP, HTTP, HTTPS | HTTP, HTTPS | HTTP, HTTPS, TCP | HTTP, HTTPS |
| **Session Affinity** | Source IP hash | Cookie-based | ❌ | Cookie-based |
| **Use Case** | Non-HTTP traffic, high performance | Web apps, SSL termination | Multi-region DNS routing | Global web apps + CDN |

> [🎥 Load Balancing Overview (2:10:24)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7824s)

---

## Exercise 5.1: Configure a Public Load Balancer with Backend Pool

**Difficulty**: 🟢 Guided

**Objectives**:
- Create a Standard public load balancer
- Configure a backend pool
- Set up a load balancing rule

[🎥 Azure Load Balancer (2:12:03)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7923s)

**Steps**:

1. Create a public IP for the load balancer:
   ```bash
   az network public-ip create \
     --name pip-lb-web \
     --resource-group rg-az104-lab-lb \
     --sku Standard \
     --allocation-method Static \
     --zone 1 2 3 \
     --tags Environment=az104-lab
   ```

2. Create the load balancer:
   ```bash
   az network lb create \
     --name lb-web \
     --resource-group rg-az104-lab-lb \
     --sku Standard \
     --frontend-ip-name fe-web \
     --public-ip-address pip-lb-web \
     --backend-pool-name be-web \
     --tags Environment=az104-lab
   ```

3. Create two NICs for backend VMs:
   ```bash
   for i in 1 2; do
     az network nic create \
       --name "nic-web-vm${i}" \
       --resource-group rg-az104-lab-lb \
       --vnet-name vnet-lb-lab \
       --subnet snet-web \
       --lb-name lb-web \
       --lb-address-pools be-web
   done
   ```

4. Verify the backend pool:
   ```bash
   az network lb address-pool show \
     --lb-name lb-web \
     --resource-group rg-az104-lab-lb \
     --name be-web \
     --query "{name:name, nicCount:backendIPConfigurations | length(@)}" \
     --output json
   ```

**Success Criteria**:
- [ ] Standard Load Balancer created with public IP
- [ ] Backend pool contains 2 NICs
- [ ] You understand why Standard SKU is required for availability zone support

> 💡 **Exam Tip**: **Basic vs Standard Load Balancer** — the exam tests this heavily:
> | Feature | Basic | Standard |
> |---------|-------|----------|
> | Backend pool size | Up to 300 | Up to 1000 |
> | Availability Zones | ❌ | ✅ |
> | SLA | None | 99.99% |
> | NSG required | Optional | **Required** on subnet/NIC |
> | Secure by default | ❌ Open | ✅ Closed (needs NSG rule) |
> | Health probes | TCP, HTTP | TCP, HTTP, HTTPS |
>
> Standard is **closed by default** — you must add NSG rules to allow traffic!

---

## Exercise 5.2: Configure Health Probes and Load Balancing Rules

**Difficulty**: 🟢 Guided

**Objectives**:
- Create health probes (HTTP and TCP)
- Configure load balancing rules
- Understand session persistence options

**Steps**:

1. Create an HTTP health probe:
   ```bash
   az network lb probe create \
     --lb-name lb-web \
     --resource-group rg-az104-lab-lb \
     --name probe-http \
     --protocol Http \
     --port 80 \
     --path "/" \
     --interval 15 \
     --threshold 2
   ```

2. Create a TCP health probe for a backend service:
   ```bash
   az network lb probe create \
     --lb-name lb-web \
     --resource-group rg-az104-lab-lb \
     --name probe-tcp-8080 \
     --protocol Tcp \
     --port 8080 \
     --interval 15 \
     --threshold 2
   ```

3. Create a load balancing rule for HTTP traffic:
   ```bash
   az network lb rule create \
     --lb-name lb-web \
     --resource-group rg-az104-lab-lb \
     --name rule-http \
     --protocol Tcp \
     --frontend-port 80 \
     --backend-port 80 \
     --frontend-ip-name fe-web \
     --backend-pool-name be-web \
     --probe-name probe-http \
     --idle-timeout 15 \
     --enable-tcp-reset true
   ```

4. Create a rule with session persistence (client IP affinity):
   ```bash
   az network lb rule create \
     --lb-name lb-web \
     --resource-group rg-az104-lab-lb \
     --name rule-https-sticky \
     --protocol Tcp \
     --frontend-port 443 \
     --backend-port 443 \
     --frontend-ip-name fe-web \
     --backend-pool-name be-web \
     --probe-name probe-http \
     --load-distribution SourceIP
   ```

5. Verify all rules and probes:
   ```bash
   echo "=== Health Probes ==="
   az network lb probe list --lb-name lb-web --resource-group rg-az104-lab-lb \
     --query "[].{name:name, protocol:protocol, port:port, interval:intervalInSeconds}" -o table

   echo "=== Load Balancing Rules ==="
   az network lb rule list --lb-name lb-web --resource-group rg-az104-lab-lb \
     --query "[].{name:name, frontPort:frontendPort, backPort:backendPort, persistence:loadDistribution, probe:probe.id}" -o table
   ```

**Success Criteria**:
- [ ] HTTP health probe checks port 80 at "/" every 15 seconds
- [ ] TCP health probe checks port 8080
- [ ] Load balancing rule distributes traffic with health probe association
- [ ] You understand the three session persistence modes

> 💡 **Exam Tip**: Session persistence (distribution) modes:
> - **None** (default): 5-tuple hash (source IP, source port, dest IP, dest port, protocol) — most distributed
> - **SourceIP**: 2-tuple hash (source IP, dest IP) — same client always hits same backend
> - **SourceIPProtocol**: 3-tuple hash (source IP, dest IP, protocol)
>
> The exam asks which mode to use for scenarios like "sticky sessions for a stateful app."

> ⚠️ **Common Mistake**: Health probe failures with Standard LB often happen because there's no NSG rule allowing the probe traffic. The Azure Load Balancer health probes come from IP **168.63.129.16** — this must be allowed in NSG rules.

---

## Exercise 5.3: Configure Inbound NAT Rules for SSH Access

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Create inbound NAT rules to access individual VMs through the load balancer
- Map different frontend ports to the same backend port
- Understand when NAT rules vs load balancing rules are appropriate

**Steps**:

1. Create NAT rules for SSH access to each backend VM:
   ```bash
   az network lb inbound-nat-rule create \
     --lb-name lb-web \
     --resource-group rg-az104-lab-lb \
     --name nat-ssh-vm1 \
     --protocol Tcp \
     --frontend-port 2201 \
     --backend-port 22 \
     --frontend-ip-name fe-web \
     --backend-pool-name be-web

   az network lb inbound-nat-rule create \
     --lb-name lb-web \
     --resource-group rg-az104-lab-lb \
     --name nat-ssh-vm2 \
     --protocol Tcp \
     --frontend-port 2202 \
     --backend-port 22 \
     --frontend-ip-name fe-web \
     --backend-pool-name be-web
   ```

2. View the NAT rules:
   ```bash
   az network lb inbound-nat-rule list \
     --lb-name lb-web \
     --resource-group rg-az104-lab-lb \
     --query "[].{name:name, fePort:frontendPort, bePort:backendPort, protocol:protocol}" \
     --output table
   ```

3. View the complete load balancer configuration:
   ```bash
   az network lb show \
     --name lb-web \
     --resource-group rg-az104-lab-lb \
     --query "{frontend:frontendIPConfigurations[0].name, backendPools:backendAddressPools[].name, rules:loadBalancingRules[].name, probes:probes[].name, natRules:inboundNatRules[].name}" \
     --output json
   ```

4. **Explore**: How would you SSH to VM1 vs VM2 through the load balancer?
   ```bash
   LB_IP=$(az network public-ip show --name pip-lb-web \
     --resource-group rg-az104-lab-lb --query ipAddress -o tsv)
   echo "SSH to VM1: ssh user@${LB_IP} -p 2201"
   echo "SSH to VM2: ssh user@${LB_IP} -p 2202"
   ```

**Success Criteria**:
- [ ] NAT rule maps port 2201 → VM1:22 and port 2202 → VM2:22
- [ ] You understand: NAT rules target specific VMs; LB rules distribute across all backends
- [ ] You can explain when to use NAT rules vs Azure Bastion for management access

> 💡 **Exam Tip**: Inbound NAT rules direct traffic to a **specific** backend instance, while load balancing rules distribute across **all** healthy backends. Use NAT rules for management access (SSH/RDP) to individual VMs. However, **Azure Bastion** is the recommended approach for secure management access.

---

## Exercise 5.4: Set Up Traffic Manager with Performance Routing

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Create a Traffic Manager profile with performance routing
- Add endpoints in different regions
- Understand Traffic Manager routing methods

[🎥 Azure Traffic Manager (2:25:01)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=8701s)

**Steps**:

1. Create a Traffic Manager profile:
   ```bash
   az network traffic-manager profile create \
     --name "tm-az104-lab-$(date +%s | tail -c 6)" \
     --resource-group rg-az104-lab-lb \
     --routing-method Performance \
     --unique-dns-name "tm-az104-lab-$(date +%s | tail -c 6)" \
     --ttl 60 \
     --protocol HTTP \
     --port 80 \
     --path "/" \
     --tags Environment=az104-lab
   ```

2. Store the profile name:
   ```bash
   TM_NAME=$(az network traffic-manager profile list \
     --resource-group rg-az104-lab-lb \
     --query "[0].name" -o tsv)
   echo "Traffic Manager: $TM_NAME"
   ```

3. Add an external endpoint (simulating a service in East US):
   ```bash
   az network traffic-manager endpoint create \
     --name "ep-eastus" \
     --profile-name "$TM_NAME" \
     --resource-group rg-az104-lab-lb \
     --type externalEndpoints \
     --target "www.example.com" \
     --endpoint-location "eastus" \
     --endpoint-status Enabled
   ```

4. Add another endpoint (simulating a service in West Europe):
   ```bash
   az network traffic-manager endpoint create \
     --name "ep-westeurope" \
     --profile-name "$TM_NAME" \
     --resource-group rg-az104-lab-lb \
     --type externalEndpoints \
     --target "www.example.co.uk" \
     --endpoint-location "westeurope" \
     --endpoint-status Enabled
   ```

5. View the profile and endpoints:
   ```bash
   az network traffic-manager profile show \
     --name "$TM_NAME" \
     --resource-group rg-az104-lab-lb \
     --query "{name:name, dns:dnsConfig.fqdn, routing:trafficRoutingMethod, status:profileStatus, endpoints:endpoints[].{name:name, target:target, location:endpointLocation, status:endpointStatus}}" \
     --output json
   ```

6. **Explore**: Change the routing method and observe:
   ```bash
   # Switch to Weighted routing
   az network traffic-manager profile update \
     --name "$TM_NAME" \
     --resource-group rg-az104-lab-lb \
     --routing-method Weighted

   # Set weights on endpoints
   az network traffic-manager endpoint update \
     --name "ep-eastus" \
     --profile-name "$TM_NAME" \
     --resource-group rg-az104-lab-lb \
     --type externalEndpoints \
     --weight 70

   az network traffic-manager endpoint update \
     --name "ep-westeurope" \
     --profile-name "$TM_NAME" \
     --resource-group rg-az104-lab-lb \
     --type externalEndpoints \
     --weight 30

   # Verify
   az network traffic-manager endpoint list \
     --profile-name "$TM_NAME" \
     --resource-group rg-az104-lab-lb \
     --query "[].{name:name, weight:weight, location:endpointLocation}" -o table
   ```

**Success Criteria**:
- [ ] Traffic Manager profile created with performance routing
- [ ] Two endpoints in different regions
- [ ] You can switch between routing methods (Performance, Weighted, Priority, Geographic)
- [ ] You understand that Traffic Manager works at the DNS level (not in the data path)

> 💡 **Exam Tip**: Traffic Manager routing methods:
> - **Priority**: Active/passive failover (primary + backup)
> - **Weighted**: Distribute by percentage (70/30 split)
> - **Performance**: Route to closest region (lowest latency)
> - **Geographic**: Route by user's geographic location
> - **MultiValue**: Return multiple healthy endpoints
> - **Subnet**: Map specific IP ranges to specific endpoints
>
> Key point: Traffic Manager is **DNS-based** — it returns a DNS answer, not a proxy. The client connects directly to the endpoint.

---

## Exercise 5.5: Design a Multi-Region Load Balancing Solution

**Difficulty**: 🔴 Challenge

**Objectives**:
- Design a complete multi-region architecture
- Choose the right load balancing services for each tier
- Handle failover scenarios

**Scenario**:

> *"Your web application needs to handle 10,000 concurrent users across two regions (East US and West Europe) with automatic failover. The application has a web tier (HTTP/HTTPS), an API tier (TCP port 8443), and a database tier. Which load balancing services would you use?"*

**Your Task**:

1. Design the architecture and fill in the table:

   | Tier | Service | Justification |
   |------|---------|---------------|
   | Global DNS routing | ________________ | Route users to closest region |
   | Regional web tier | ________________ | SSL offload, URL routing, WAF |
   | Regional API tier | ________________ | TCP load balancing, high performance |
   | Database tier | ________________ | No LB — use Azure SQL failover groups |

2. Answer these design questions:
   - Why not use Azure Load Balancer for the global tier?
   - Why not use Traffic Manager for the web tier?
   - What happens when an entire region fails?
   - How would your design change if you needed WAF at the global level?

3. Implement the global + regional architecture:
   ```bash
   # Global tier: Traffic Manager (or Front Door for HTTP)
   az network traffic-manager profile create \
     --name "tm-global-web" \
     --resource-group rg-az104-lab-lb \
     --routing-method Priority \
     --unique-dns-name "tm-global-web-$(date +%s | tail -c 6)" \
     --ttl 30 \
     --protocol HTTPS \
     --port 443 \
     --path "/health"

   # Regional tier: Application Gateway per region (conceptual)
   # In a real deployment, you'd create an App Gateway in each region
   # with backend pools pointing to regional VMs/VMSS

   # Add regional LB public IPs as Traffic Manager endpoints
   LB_IP=$(az network public-ip show --name pip-lb-web \
     --resource-group rg-az104-lab-lb --query ipAddress -o tsv 2>/dev/null || echo "20.0.0.1")

   az network traffic-manager endpoint create \
     --name "ep-primary-eastus" \
     --profile-name "tm-global-web" \
     --resource-group rg-az104-lab-lb \
     --type externalEndpoints \
     --target "$LB_IP" \
     --endpoint-location "eastus" \
     --priority 1

   az network traffic-manager endpoint create \
     --name "ep-secondary-westeurope" \
     --profile-name "tm-global-web" \
     --resource-group rg-az104-lab-lb \
     --type externalEndpoints \
     --target "20.0.0.2" \
     --endpoint-location "westeurope" \
     --priority 2
   ```

4. **Alternative design with Front Door**: When would you choose Front Door over Traffic Manager?
   ```
   Use Front Door when:
   - You need WAF at the global level
   - You need SSL offload at the edge
   - You need URL-based routing globally
   - You need caching/CDN capabilities
   
   Use Traffic Manager when:
   - You have non-HTTP traffic (TCP/UDP)
   - You want DNS-only routing (no proxy)
   - You need geographic routing for compliance
   - Lower cost requirement
   ```

**Success Criteria**:
- [ ] Architecture uses Traffic Manager (or Front Door) globally + regional LBs
- [ ] You chose Application Gateway for web tier (L7) and Load Balancer for API tier (L4)
- [ ] Failover is automatic via Traffic Manager health probes
- [ ] You can justify each service choice with specific capabilities needed

> 💡 **Exam Tip**: The exam loves "which load balancing service should you use?" questions. Decision tree:
> 1. **Global or Regional?** → Global: Traffic Manager or Front Door; Regional: LB or App Gateway
> 2. **HTTP or non-HTTP?** → HTTP: App Gateway or Front Door; Non-HTTP: Load Balancer or Traffic Manager
> 3. **Need WAF?** → Yes: App Gateway or Front Door
> 4. **Need SSL offload?** → Yes: App Gateway or Front Door
>
> [🎥 Azure Front Door (2:28:09)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=8889s) | [🎥 Cross-Region LB (2:26:51)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=8811s)

> 📖 **Deep Dive**: [Application Gateway](https://learn.microsoft.com/en-us/azure/application-gateway/) | [Azure Front Door](https://learn.microsoft.com/en-us/azure/frontdoor/)

---

## Clean Up

```bash
# Remove Traffic Manager profiles
for tm in $(az network traffic-manager profile list --resource-group rg-az104-lab-lb --query "[].name" -o tsv); do
  az network traffic-manager profile delete --name "$tm" --resource-group rg-az104-lab-lb
done

# Remove NICs, LB, and public IP
az network nic delete --name nic-web-vm1 --resource-group rg-az104-lab-lb --no-wait 2>/dev/null
az network nic delete --name nic-web-vm2 --resource-group rg-az104-lab-lb --no-wait 2>/dev/null
az network lb delete --name lb-web --resource-group rg-az104-lab-lb 2>/dev/null
az network public-ip delete --name pip-lb-web --resource-group rg-az104-lab-lb 2>/dev/null

# Remove resource group
az group delete --name rg-az104-lab-lb --yes --no-wait

echo "✅ Load balancing lab resources cleaned up"
```

---

## Key Concepts for the Exam

| Concept | Details |
|---------|---------|
| LB SKUs | **Basic**: No AZ, no SLA, open by default. **Standard**: AZ support, 99.99% SLA, closed by default |
| Health Probes | LB: TCP/HTTP/HTTPS. Probe source IP: **168.63.129.16** |
| Session Persistence | None (5-tuple), SourceIP (2-tuple), SourceIPProtocol (3-tuple) |
| NAT Rules | Target specific backend instance; LB rules distribute across all |
| Traffic Manager | DNS-based, global, not a proxy. Routing: Priority, Weighted, Performance, Geographic |
| App Gateway | L7, regional, WAF, SSL offload, URL routing, cookie affinity |
| Front Door | L7, global, WAF, SSL offload, CDN, caching |
| Cross-Region LB | L4, global, Standard LB as backends |

---

*Previous: [Exercise 04 — DNS & Connectivity](04-dns-connectivity-exercises.md) | Next: [Exercise 06 — Storage](06-storage-exercises.md)*
