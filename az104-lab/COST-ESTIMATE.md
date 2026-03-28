# Cost Estimate

> ⚠️ **Disclaimer**: These estimates are based on East US pricing as of 2024. Actual costs may vary by region, subscription type, and Azure pricing changes. Always verify current pricing with the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/).

---

## Cost Breakdown by Module

| Module | Key Resources | Hourly | Daily (8hr) | Monthly (est.) |
|--------|---------------|--------|-------------|----------------|
| 00 Foundation | VNets, subnets, NSGs | Free | Free | Free |
| 01 Identity | Entra ID users/groups | Free | Free | Free* |
| 02 Governance | Policies, locks, budgets | Free | Free | Free |
| 03 Networking | Peering, NSGs, ASGs, public IPs | ~$0.01 | ~$0.08 | ~$3 |
| 04 DNS & Connectivity | DNS zones, Bastion, private endpoints | ~$0.20 | ~$1.60 | ~$7 |
| 05 Load Balancing | Load Balancer, Traffic Manager, App GW | ~$0.30 | ~$2.40 | ~$12 |
| 06 Storage | Storage accounts, blobs, file shares | ~$0.01 | ~$0.01 | ~$2 |
| 07 Compute | VMs, VMSS, ACI, App Service, ACR | ~$0.15 | ~$1.20 | ~$15 |
| 08 Monitoring | Log Analytics, alerts, Recovery Services | ~$0.01 | ~$0.05 | ~$5 |
| **Total** | | **~$0.68** | **~$5.34** | **~$44** |

\* Entra ID P1/P2 features (SSPR, conditional access) require additional licensing.

---

## Always-On vs On-Demand Resources

### Always-On (incur cost even when idle)

| Resource | Module | Approx. Cost | Notes |
|----------|--------|-------------|-------|
| Public IP addresses (Standard) | 03, 05 | ~$0.005/hr each | Charged when allocated |
| Azure DNS zones | 04 | ~$0.50/zone/month | Negligible |
| Private DNS zones | 04 | ~$0.25/zone/month | Negligible |
| Storage accounts | 06 | ~$0.02/GB/month | Negligible for lab data |
| Log Analytics workspace | 08 | Ingestion-based | 5 GB/month free tier |

### On-Demand (cost only when active)

| Resource | Module | Approx. Cost | Can Pause? |
|----------|--------|-------------|------------|
| VMs (B1s/B2s) | 07 | ~$0.01–0.04/hr | ✅ Deallocate |
| VMSS | 07 | ~$0.01–0.04/hr per instance | ✅ Scale to 0 |
| AKS cluster | 07 | ~$0.04/hr per node | ✅ Stop cluster |
| Azure Bastion (Developer) | 04 | ~$0.19/hr | ❌ Delete when done |
| App Gateway v2 | 05 | ~$0.25/hr | ❌ Delete when done |
| Azure Firewall (Basic) | 03 | ~$0.90/hr | ❌ Delete when done |
| Traffic Manager | 05 | ~$0.54/million queries | Negligible |

---

## Cost Optimization Tips

### 💰 Essential Practices

1. **Deallocate VMs when not studying** — stopped (deallocated) VMs don't incur compute charges
   ```bash
   az vm deallocate --resource-group rg-az104-lab-compute --name az104-lab-vm-linux
   ```

2. **Use auto-shutdown schedules** — already configured in lab templates to shut down at 10:00 PM local time

3. **Delete expensive resources after exercises** — Bastion, App Gateway, and Firewall should be destroyed after completing their respective module exercises
   ```bash
   ./scripts/destroy-module.sh 04-dns-connectivity  # Removes Bastion
   ./scripts/destroy-module.sh 05-load-balancing     # Removes App GW
   ```

4. **Use pause and resume scripts** to manage costs across study sessions:
   ```bash
   ./scripts/pause-resources.sh    # Deallocates VMs, stops AKS
   ./scripts/resume-resources.sh   # Restarts everything
   ```

5. **Deploy modules only when you're ready to study them** — don't deploy all modules at once

### 💡 Additional Savings

- Use **B-series burstable VMs** (already configured) — cheapest general-purpose option
- The lab uses **Developer SKU for Bastion** (~$0.19/hr vs ~$0.26/hr for Basic)
- **Storage costs are negligible** — lab data is minimal
- **Log Analytics** stays within the 5 GB/month free tier for normal lab usage

---

## Estimated Totals

| Scenario | Daily Cost | Monthly Cost |
|----------|-----------|-------------|
| Active study (8 hrs, all modules) | ~$3–5 | ~$40–60 |
| VMs paused, infrastructure running | <$1 | ~$10–15 |
| Only foundation + free modules | Free–$0.10 | ~$3 |
| Everything destroyed | $0 | $0 |

---

## Budget Alert

Module 02 (Governance) configures a **budget alert at $50/month** on your subscription. You will receive an email notification when spending approaches this threshold.

---

## Expensive Resource Warnings

> ⚠️ The following resources can generate significant costs if left running. Delete them promptly after completing the relevant exercises.

| Resource | Approx. Cost/hr | Module | Action |
|----------|-----------------|--------|--------|
| Azure Firewall (Basic) | ~$0.90/hr | 03 | Delete after networking exercises |
| VPN Gateway | ~$0.04/hr | 04 | Conceptual only — not deployed |
| App Gateway v2 | ~$0.25/hr | 05 | Delete after load balancing exercises |
| Azure Front Door | ~$0.01/hr + per request | 05 | Delete after exercises |
| Azure Bastion (Developer) | ~$0.19/hr | 04 | Delete after connectivity exercises |
| VMs (B1s/B2s) | ~$0.01–0.04/hr | 07 | Deallocate when not studying |
| AKS (1 node B2s) | ~$0.04/hr | 07 | Stop cluster when not studying |
| Log Analytics (above free tier) | ~$2.76/GB ingested | 08 | Stay within 5 GB/month free tier |

---

## Pricing Calculator

Use the Azure Pricing Calculator to estimate costs for your specific region and configuration:

🔗 [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
