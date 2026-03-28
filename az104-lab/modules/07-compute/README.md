# Module 07: Compute

> **AZ-104 Domain:** Deploy and Manage Azure Compute Resources (~20–25% of exam)
>
> **Savill Cram Timestamps:**
> [Provisioning 3:10:21](https://www.youtube.com/watch?v=0Knf9nub4-k&t=11421s) •
> [Service Types 3:15:07](https://www.youtube.com/watch?v=0Knf9nub4-k&t=11707s) •
> [VMs 3:19:05](https://www.youtube.com/watch?v=0Knf9nub4-k&t=11945s) •
> [Availability 3:28:11](https://www.youtube.com/watch?v=0Knf9nub4-k&t=12491s) •
> [VMSS 3:30:54](https://www.youtube.com/watch?v=0Knf9nub4-k&t=12654s) •
> [Containers 3:34:35](https://www.youtube.com/watch?v=0Knf9nub4-k&t=12875s) •
> [AKS 3:37:25](https://www.youtube.com/watch?v=0Knf9nub4-k&t=13045s) •
> [App Service 3:42:34](https://www.youtube.com/watch?v=0Knf9nub4-k&t=13354s)

This is the **largest module** in the lab. It covers virtual machines, scale sets, containers, and App Service — the four major compute pillars tested on AZ-104.

## Learning Objectives

After completing this module you will be able to:

- **ARM / Bicep:** Interpret ARM JSON templates and understand parameter → variable → resource → output flow
- **Virtual Machines:** Create Linux (SSH key) and Windows (password) VMs with different sizes and disk types
- **Encryption at host:** Understand Azure Disk Encryption vs server-side encryption vs encryption at host
- **VM sizes & disks:** Identify VM families (B/D/E/F-series) and managed disk tiers (Standard/Premium/Ultra)
- **Availability zones vs sets:** Know when to use zones (datacenter-level) vs sets (rack-level)
- **VMSS:** Configure autoscale rules, upgrade policies, and scaling boundaries
- **ACR:** Create a container registry, push/pull images, understand SKU tiers
- **ACI:** Deploy serverless containers with public IPs and resource limits
- **Container Apps:** Understand when to use Container Apps vs ACI vs AKS (not deployed but tested on exam)
- **App Service:** Configure plans, runtimes, HTTPS, deployment slots, and slot swaps

## What Gets Deployed

| Resource | Name | Type | Key Concepts |
|----------|------|------|-------------|
| Linux VM | `vm-az104-lab-linux1` | Standard_B1s, Ubuntu 22.04 | SSH auth, zone 1, custom script extension |
| Windows VM | `vm-az104-lab-win1` | Standard_B2s, Windows Server 2022 | Password auth, availability set |
| Availability Set | `avset-az104-lab-win` | 2 FDs, 5 UDs | Rack isolation, update domains |
| VMSS | `vmss-az104-lab-web` | Standard_B1s × 2 | Autoscale, rolling upgrade policy |
| ACR | `acraz104-lab{suffix}` | Basic SKU | Container image registry |
| ACI | `ci-az104-lab-hello` | 0.5 CPU, 0.5 GB | Serverless container, public IP |
| App Service Plan | `plan-az104-lab-web` | B1 Linux | Cheapest plan with slot support |
| App Service | `app-az104-lab-web-{suffix}` | Node 18 LTS | HTTPS only, staging slot |

## Container Service Comparison

> AZ-104 frequently tests *when* to use each service. Memorize this table.

| Feature | ACI | Container Apps | AKS | App Service |
|---------|-----|---------------|-----|-------------|
| **Best for** | Simple/short-lived tasks | Microservices, event-driven | Complex orchestration | Web apps, APIs |
| **Scaling** | Manual (replica count) | Built-in (KEDA, HTTP) | Full Kubernetes HPA/VPA | Built-in rules or manual |
| **Networking** | Public IP or VNet | Ingress controller, VNet | Full K8s networking | VNet integration |
| **Persistent storage** | Azure Files mount | Azure Files mount | Full PV/PVC support | Local or mounted storage |
| **Management overhead** | Lowest | Low | Highest | Low |
| **Startup time** | Seconds | Seconds | Minutes (cluster) | Seconds (app), minutes (plan) |
| **Cost model** | Per-second (vCPU + mem) | Per-second (vCPU + mem) | Per-node VM cost | Per-plan (fixed) |
| **Min cost** | ~$0 (pay per use) | ~$0 (scale to zero) | ~$60/mo (1 node) | ~$13/mo (B1) |
| **Deployment slots** | ❌ | ✅ (revisions) | ✅ (via manifests) | ✅ (native) |

## VM Size Families

> Know the letter prefix and what it's optimized for.

| Series | Type | Use Case | Example |
|--------|------|----------|---------|
| **B** | Burstable | Dev/test, low-traffic web | B1s, B2s — cheapest option |
| **D** | General purpose | Most production workloads | D2s_v5, D4s_v5 |
| **E** | Memory optimized | Databases, in-memory caching | E2s_v5, E4s_v5 |
| **F** | Compute optimized | Batch processing, gaming servers | F2s_v2, F4s_v2 |
| **L** | Storage optimized | Big data, large databases | L8s_v3, L16s_v3 |
| **N** | GPU | ML/AI, rendering | NC6s_v3, NV6 |
| **M** | Memory intensive | SAP HANA, very large DBs | M32ts, M64s |

**Naming convention:** `Standard_D2s_v5` → D-series, 2 vCPUs, "s" = premium storage capable, v5 = generation.

## Managed Disk Types

| Type | IOPS | Use Case | Cost |
|------|------|----------|------|
| Standard HDD (Standard_LRS) | Up to 500 | Backup, dev/test | Cheapest |
| Standard SSD (StandardSSD_LRS) | Up to 6,000 | Web servers, light workloads | Low |
| Premium SSD (Premium_LRS) | Up to 20,000 | Production databases | Medium |
| Ultra Disk | Up to 160,000 | SAP HANA, top-tier DBs | Highest |

## Prerequisites

- **Module 03 (Networking)** must be deployed — this module references spoke1 subnet IDs
- An SSH key pair for the Linux VM:
  ```bash
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/az104-az104-lab -N ""
  ```
- Azure CLI with Bicep support:
  ```bash
  az --version   # 2.60+ recommended
  az bicep version
  ```

## Deploy

### 1. Create the resource group

```bash
az group create --name rg-az104-lab-compute --location eastus
```

### 2. Get subnet IDs from Module 03

```bash
# Fetch spoke1 subnet IDs (adjust resource group name if different)
SPOKE1_DEFAULT_SUBNET=$(az network vnet subnet show \
  --resource-group rg-az104-lab-networking \
  --vnet-name vnet-az104-lab-spoke1 \
  --name default \
  --query id -o tsv)

SPOKE1_APP_SUBNET=$(az network vnet subnet show \
  --resource-group rg-az104-lab-networking \
  --vnet-name vnet-az104-lab-spoke1 \
  --name app \
  --query id -o tsv)
```

### 3. Preview the deployment

```bash
az deployment group what-if \
  --resource-group rg-az104-lab-compute \
  --template-file main.bicep \
  --parameters \
    spoke1DefaultSubnetId="$SPOKE1_DEFAULT_SUBNET" \
    spoke1AppSubnetId="$SPOKE1_APP_SUBNET" \
    adminPublicKey="$(cat ~/.ssh/az104-az104-lab.pub)" \
    adminPassword='YourP@ssw0rd!23'
```

### 4. Deploy

```bash
az deployment group create \
  --resource-group rg-az104-lab-compute \
  --template-file main.bicep \
  --parameters \
    spoke1DefaultSubnetId="$SPOKE1_DEFAULT_SUBNET" \
    spoke1AppSubnetId="$SPOKE1_APP_SUBNET" \
    adminPublicKey="$(cat ~/.ssh/az104-az104-lab.pub)" \
    adminPassword='YourP@ssw0rd!23'
```

> ⏱ This deployment takes **10–15 minutes** due to VM provisioning and extensions.

## Verify

```bash
# List all resources in the compute resource group
az resource list --resource-group rg-az104-lab-compute -o table

# Check Linux VM status
az vm show --resource-group rg-az104-lab-compute --name vm-az104-lab-linux1 \
  --query '{name:name, size:hardwareProfile.vmSize, zone:zones[0], os:storageProfile.osDisk.osType}' -o table

# Check Windows VM and its availability set
az vm show --resource-group rg-az104-lab-compute --name vm-az104-lab-win1 \
  --query '{name:name, size:hardwareProfile.vmSize, availSet:availabilitySet.id}' -o table

# Check VMSS instances
az vmss list-instances --resource-group rg-az104-lab-compute --name vmss-az104-lab-web -o table

# Verify autoscale settings
az monitor autoscale show --resource-group rg-az104-lab-compute --name autoscale-vmss-az104-lab-web \
  --query '{min:profiles[0].capacity.minimum, max:profiles[0].capacity.maximum, rules:profiles[0].rules[].metricTrigger.metricName}' -o json

# Check ACR
az acr show --resource-group rg-az104-lab-compute --name $(az acr list --resource-group rg-az104-lab-compute --query '[0].name' -o tsv) --query '{name:name, loginServer:loginServer, sku:sku.name}' -o table

# Check ACI
az container show --resource-group rg-az104-lab-compute --name ci-az104-lab-hello \
  --query '{name:name, state:instanceView.state, ip:ipAddress.ip, image:containers[0].image}' -o table

# Check App Service and staging slot
az webapp show --resource-group rg-az104-lab-compute --name $(az webapp list --resource-group rg-az104-lab-compute --query '[0].name' -o tsv) \
  --query '{name:name, state:state, url:defaultHostName}' -o table

az webapp deployment slot list --resource-group rg-az104-lab-compute \
  --name $(az webapp list --resource-group rg-az104-lab-compute --query '[0].name' -o tsv) -o table
```

## ARM Template Interpretation Exercise

The file `sample-arm-template.json` is included for exam-style practice. Try answering these questions by reading the template:

1. What resource type does it deploy?
2. What happens if you pass `skuName = "Premium_ZRS"` — does it succeed or fail?
3. How is the storage account name made unique?
4. What is the default location if no value is provided?
5. What are the two outputs, and what functions do they use?

## Cost Warning

> ⚠ **VMs cost money even when idle!** Only a `Deallocated` VM stops billing for compute.
>
> | Resource | Estimated Cost |
> |----------|---------------|
> | Standard_B1s (Linux) | ~$0.008/hr ($6/mo) |
> | Standard_B2s (Windows) | ~$0.042/hr ($31/mo) |
> | VMSS (2 × B1s) | ~$0.016/hr ($12/mo) |
> | ACI (0.5 CPU) | ~$0.002/hr ($1.50/mo) |
> | App Service (B1) | ~$0.018/hr ($13/mo) |
> | ACR (Basic) | ~$0.007/hr ($5/mo) |
> | **Total (running)** | **~$0.09/hr (~$69/mo)** |
>
> **Deallocate VMs when not studying:**
> ```bash
> az vm deallocate --resource-group rg-az104-lab-compute --name vm-az104-lab-linux1 --no-wait
> az vm deallocate --resource-group rg-az104-lab-compute --name vm-az104-lab-win1 --no-wait
> az vmss deallocate --resource-group rg-az104-lab-compute --name vmss-az104-lab-web --no-wait
> ```
>
> Auto-shutdown is configured for 10 PM (UTC) as a safety net.

## Clean Up

```bash
# Delete the entire resource group and all resources within it
az group delete --name rg-az104-lab-compute --yes --no-wait

# Or deallocate VMs to stop compute billing but keep resources:
az vm deallocate --resource-group rg-az104-lab-compute --name vm-az104-lab-linux1 --no-wait
az vm deallocate --resource-group rg-az104-lab-compute --name vm-az104-lab-win1 --no-wait
az vmss deallocate --resource-group rg-az104-lab-compute --name vmss-az104-lab-web --no-wait
```

## AZ-104 Exam Tips

- **ARM templates vs Bicep:** The exam shows both. ARM uses JSON with `concat()`, `reference()`, `resourceId()`. Bicep uses string interpolation, dot notation, and symbolic names. Know how to read both.
- **VM sizes:** The letter indicates the family (B=burstable, D=general, E=memory, F=compute). The "s" suffix means premium storage support.
- **Availability sets vs zones:** Sets protect against rack failures (same datacenter). Zones protect against datacenter failures (different physical buildings). You **cannot** use both for the same VM.
- **VMSS autoscale:** Know metric-based (CPU, memory, queue length) vs schedule-based (time of day, day of week) scaling. The cooldown period prevents flapping.
- **ACR SKUs:** Basic (dev/test), Standard (production), Premium (geo-replication, private link, content trust).
- **ACI restart policies:** Always (web servers), OnFailure (batch jobs), Never (one-time tasks).
- **App Service slots:** B1+ required. Swap exchanges routing, not code. "Sticky" settings stay with the slot (e.g., connection strings marked as slot settings).
- **Encryption:** Server-side encryption (SSE) is on by default for managed disks. Azure Disk Encryption (ADE) uses BitLocker/DM-Crypt. Encryption at host encrypts temp disks and caches.
