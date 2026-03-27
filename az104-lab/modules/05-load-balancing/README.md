# Module 05: Load Balancing

Configure and manage Azure load-balancing services for the AZ-104 certification lab. This module deploys a **Standard public Azure Load Balancer** and a **Traffic Manager profile**, with conceptual coverage of Application Gateway and Front Door.

> **Cram Video:** [John Savill's AZ-104 Cram](https://www.youtube.com/watch?v=0Knf9nub4-k)
>
> | Topic | Timestamp |
> |---|---|
> | Load Balancing Overview | [2:10:24](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7824s) |
> | Azure Load Balancer | [2:12:03](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7923s) |
> | Application Gateway | [2:18:13](https://www.youtube.com/watch?v=0Knf9nub4-k&t=8293s) |
> | Traffic Manager | [2:25:01](https://www.youtube.com/watch?v=0Knf9nub4-k&t=8701s) |
> | Cross-Region Load Balancer | [2:26:51](https://www.youtube.com/watch?v=0Knf9nub4-k&t=8811s) |
> | Front Door | [2:28:09](https://www.youtube.com/watch?v=0Knf9nub4-k&t=8889s) |

## Learning Objectives

After completing this module you should be able to:

- **Configure a public load balancer** — frontend IP, backend pool, health probes, LB rules, NAT rules
- **Configure an internal load balancer** — same concepts, private frontend IP (conceptual)
- **Troubleshoot load balancing** — health probe failures, NSG misconfigurations, backend pool membership
- **Choose the right load balancer** — Layer 4 vs Layer 7, regional vs global
- **Configure Traffic Manager** — routing methods, endpoint types, health monitoring

## Azure Load Balancing Comparison

This is a **high-frequency exam topic**. Know which load balancer to pick for a given scenario.

| Feature | Azure Load Balancer | Application Gateway | Traffic Manager | Front Door |
|---|---|---|---|---|
| **OSI Layer** | 4 (Transport) | 7 (Application) | DNS-based | 7 (Application) |
| **Scope** | Regional | Regional | Global | Global |
| **Protocol** | TCP / UDP | HTTP / HTTPS / WS | DNS (any protocol) | HTTP / HTTPS |
| **Key Feature** | High-perf L4 balancing | WAF, SSL offload, URL routing | DNS routing policies | Global CDN + WAF |
| **Session Affinity** | 5-tuple / Client IP | Cookie-based | N/A (DNS) | Cookie / IP |
| **Health Probes** | TCP / HTTP / HTTPS | HTTP / HTTPS | HTTP / HTTPS / TCP | HTTP / HTTPS |
| **SKUs** | Basic ¹ / Standard | Standard / WAF v2 | — | Standard / Premium |
| **Estimated Cost** | Low (~$0.025/rule/hr) | Medium–High (~$0.25/hr+) | Low (~$0.54/M queries) | Medium (~$0.35/hr+) |

> ¹ Basic Load Balancer is being retired. The exam focuses on Standard SKU.

### Decision Flowchart (Exam Shortcut)

```
Is it global (multi-region)?
├── Yes → Is it HTTP/HTTPS?
│         ├── Yes → Front Door
│         └── No  → Traffic Manager (DNS-level, any protocol)
└── No  → Is it HTTP/HTTPS and needs WAF / URL routing / SSL offload?
          ├── Yes → Application Gateway
          └── No  → Azure Load Balancer (Standard)
```

## What Gets Deployed

| Resource | Name | Purpose |
|---|---|---|
| Public IP | `pip-certlab-lb` | Standard SKU, static — frontend IP for the LB |
| Load Balancer | `lb-certlab-web` | Standard public LB with HTTP rule + SSH NAT rules |
| Backend Pool | `bp-certlab-web` | Target pool for VMs (VMs added in Module 07) |
| Health Probe | `hp-http` | HTTP probe on port 80, path `/`, interval 15 s |
| LB Rule | `rule-http` | Port 80 → 80, TCP, no session persistence |
| NAT Rule | `natrule-ssh-vm1` | Port 50001 → 22 (SSH to VM1) |
| NAT Rule | `natrule-ssh-vm2` | Port 50002 → 22 (SSH to VM2) |
| Traffic Manager | `tm-certlab-web` | Performance routing, HTTP monitor on port 80 |

All resources are tagged with `Environment=certlab`, `Project=az104-lab`, `Module=load-balancing`.

## Prerequisites

- **Module 03 (Networking) deployed** — provides the spoke subnet for backend pool references
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (v2.60+)
- [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) (bundled with Azure CLI)

```bash
az --version
az bicep version
```

## Deploy

```bash
# 1. Create the resource group
az group create --name rg-certlab-load-balancing --location eastus

# 2. Preview changes (always do this first!)
az deployment group create \
  --resource-group rg-certlab-load-balancing \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --what-if

# 3. Deploy
az deployment group create \
  --resource-group rg-certlab-load-balancing \
  --template-file main.bicep \
  --parameters main.bicepparam

# Optional: pass the spoke subnet from Module 03
az deployment group create \
  --resource-group rg-certlab-load-balancing \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters spoke1SubnetId="$(az network vnet subnet show \
      --resource-group rg-certlab-networking \
      --vnet-name vnet-certlab-spoke1 \
      --name default \
      --query id -o tsv)"
```

## Verify

```bash
# Confirm Load Balancer
az network lb show \
  --resource-group rg-certlab-load-balancing \
  --name lb-certlab-web \
  --query '{name:name, sku:sku.name, frontendIP:frontendIPConfigurations[0].name, rules:loadBalancingRules[].name, probes:probes[].name}' \
  --output json

# List backend pool (empty until VMs are added in Module 07)
az network lb address-pool show \
  --resource-group rg-certlab-load-balancing \
  --lb-name lb-certlab-web \
  --name bp-certlab-web \
  --query '{name:name, backendAddresses:backendAddresses}' \
  --output json

# List inbound NAT rules
az network lb inbound-nat-rule list \
  --resource-group rg-certlab-load-balancing \
  --lb-name lb-certlab-web \
  --output table

# Show public IP assigned to the LB
az network public-ip show \
  --resource-group rg-certlab-load-balancing \
  --name pip-certlab-lb \
  --query '{ip:ipAddress, sku:sku.name, allocation:publicIPAllocationMethod}' \
  --output json

# Confirm Traffic Manager profile
az network traffic-manager profile show \
  --resource-group rg-certlab-load-balancing \
  --name tm-certlab-web \
  --query '{name:name, fqdn:dnsConfig.fqdn, routing:trafficRoutingMethod, status:profileStatus}' \
  --output json
```

## Conceptual: Application Gateway

> **⚠️ Not deployed** — Application Gateway costs ~$0.25/hr (~$180/month) even when idle.

Key exam points:

- **Layer 7** (HTTP/HTTPS) load balancer — can inspect headers, cookies, URL paths
- **Components**: Frontend IP → Listener → Rule → Backend Pool (+ HTTP Settings + Health Probe)
- **URL-based routing**: `/images/*` → image pool, `/api/*` → api pool
- **Multi-site hosting**: route by `Host` header to different backend pools
- **SSL/TLS termination**: offload encryption at the gateway
- **WAF (Web Application Firewall)**: OWASP rule sets for SQL injection, XSS, etc.
- **Autoscaling**: WAF_v2 SKU supports autoscale (0–125 instances)
- **Redirection**: HTTP → HTTPS redirect, external URL redirect
- **Session affinity**: cookie-based (gateway-managed or application cookie)

## Conceptual: Azure Front Door

> **⚠️ Not deployed** — Front Door incurs per-request and bandwidth charges.

Key exam points:

- **Global Layer 7** load balancer with built-in CDN and WAF
- Uses Microsoft's global edge network (anycast)
- **Split TCP**: client connects to nearest PoP; PoP maintains persistent connection to origin
- **URL-based routing** and **multi-site hosting** (similar to App Gateway, but global)
- **Caching**: static content served from edge PoPs
- **Session affinity**: cookie-based
- **Health probes** to origins; automatic failover
- **Private Link origins**: connect to App Service / Storage without public endpoint
- **Tiers**: Standard (CDN + basic routing) and Premium (CDN + WAF + Private Link)

## Exam Tips — Common Traps

1. **Standard vs Basic LB**: Standard requires NSG on backend NICs; Basic does not. Standard supports availability zones; Basic does not. Basic is being retired.
2. **Traffic Manager is DNS-only**: It does NOT sit in the data path. Clients resolve the CNAME and connect directly to the endpoint. This means it works with any protocol (not just HTTP).
3. **Health probe failures**: If all backends are unhealthy, the LB sends traffic to ALL backends (fail-open). Traffic Manager removes unhealthy endpoints from DNS.
4. **Floating IP**: Required for SQL AlwaysOn listeners and any scenario where the backend must respond on the frontend IP.
5. **Outbound rules**: Standard LB can control outbound SNAT with explicit outbound rules; Basic LB uses implicit SNAT.
6. **App Gateway vs Front Door**: Both are Layer 7 — App Gateway is regional, Front Door is global.

## Clean Up

```bash
# Remove the load-balancing resource group and all resources
az group delete --name rg-certlab-load-balancing --yes --no-wait

# Verify deletion is in progress
az group show --name rg-certlab-load-balancing --query 'properties.provisioningState' --output tsv 2>/dev/null || echo "Deleted"
```

## Cost Notes

| Resource | Estimated Cost | Notes |
|---|---|---|
| Standard Load Balancer | ~$0.025/rule/hr (~$18/month) | First 5 rules included |
| Standard Public IP | ~$0.005/hr (~$3.60/month) | Static allocation |
| Traffic Manager | ~$0.54/million queries | Plus $0.36/health check/month |
| **Application Gateway** | **~$0.25/hr+ (~$180/month)** | **Not deployed — too expensive for lab** |
| **Front Door** | **~$0.35/hr+ per routing rule** | **Not deployed — too expensive for lab** |

> 💡 Always run `az group delete` when you're done practicing to avoid surprise charges.
