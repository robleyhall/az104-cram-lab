# Exercise 07: Compute

[🎥 Cram Session: Compute (3:10:21–3:45:25)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=11421s)

> **Exam Domain**: Deploy and manage Azure compute resources (20–25%)
>
> These exercises cover VMs, ARM/Bicep templates, VMSS, containers (ACI, ACR), and App Service.

---

## Prerequisites

- An active Azure subscription with **Contributor** role
- Azure CLI v2.60+ authenticated (`az login`)
- Bicep CLI installed (`az bicep install`)
- Docker (optional, for container exercises)
- Module 00 (Foundation) deployed

```bash
az group create --name rg-az104-lab-compute --location eastus \
  --tags Environment=az104-lab Module=compute
```

---

## Exercise 7.1: Deploy a VM and Connect via SSH

**Difficulty**: 🟢 Guided

**Objectives**:
- Create a Linux VM in an availability zone
- Configure SSH access
- Understand VM components (NIC, disk, public IP)

[🎥 Virtual Machines (3:19:05)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=11945s)

**Steps**:

1. Create a VNet and subnet for compute:
   ```bash
   az network vnet create \
     --name vnet-compute \
     --resource-group rg-az104-lab-compute \
     --address-prefix 10.30.0.0/16 \
     --subnet-name snet-vms \
     --subnet-prefix 10.30.0.0/24
   ```

2. Create an NSG and allow SSH:
   ```bash
   az network nsg create \
     --name nsg-vms \
     --resource-group rg-az104-lab-compute

   az network nsg rule create \
     --nsg-name nsg-vms \
     --resource-group rg-az104-lab-compute \
     --name AllowSSH \
     --priority 100 --direction Inbound --access Allow \
     --protocol Tcp --destination-port-ranges 22 \
     --source-address-prefixes "$(curl -s https://ifconfig.me)/32"

   az network vnet subnet update \
     --name snet-vms --resource-group rg-az104-lab-compute \
     --vnet-name vnet-compute --network-security-group nsg-vms
   ```

3. Deploy a Linux VM in Availability Zone 1:
   ```bash
   az vm create \
     --name vm-web-01 \
     --resource-group rg-az104-lab-compute \
     --image Ubuntu2204 \
     --size Standard_B1s \
     --admin-username azurelab \
     --generate-ssh-keys \
     --zone 1 \
     --vnet-name vnet-compute \
     --subnet snet-vms \
     --public-ip-sku Standard \
     --nsg "" \
     --tags Environment=az104-lab Role=web
   ```

4. Get the VM's public IP and SSH into it:
   ```bash
   VM_IP=$(az vm show --name vm-web-01 --resource-group rg-az104-lab-compute \
     --show-details --query publicIps -o tsv)
   echo "SSH command: ssh azurelab@${VM_IP}"
   ```

5. Examine the VM's components:
   ```bash
   az vm show --name vm-web-01 --resource-group rg-az104-lab-compute \
     --query "{name:name, size:hardwareProfile.vmSize, zone:zones[0], osType:storageProfile.osDisk.osType, osDiskType:storageProfile.osDisk.managedDisk.storageAccountType}" \
     --output json
   ```

6. List all resources created for the VM:
   ```bash
   az resource list --resource-group rg-az104-lab-compute \
     --query "[].{name:name, type:type}" --output table
   ```

**Success Criteria**:
- [ ] VM deployed in Availability Zone 1
- [ ] SSH access works using the generated keys
- [ ] You can identify all resources created: VM, NIC, OS Disk, Public IP
- [ ] You understand that `Standard_B1s` is a burstable, cost-effective VM size

> 💡 **Exam Tip**: When you create a VM, Azure also creates: a **NIC**, an **OS Disk** (managed disk), and optionally a **Public IP** and **NSG**. These are separate resources. Deleting the VM does NOT automatically delete the disk or NIC — you must delete them separately (or use `--delete-option Delete`).

> ⚠️ **Common Mistake**: Using Basic public IP with Standard LB, or vice versa. **Standard LB requires Standard public IPs**. Standard public IPs are zone-redundant by default. Basic public IPs do NOT support availability zones.

---

## Exercise 7.2: Interpret and Deploy an ARM Template

**Difficulty**: 🟢 Guided

**Objectives**:
- Read an ARM template and identify resources, parameters, and outputs
- Deploy resources using an ARM template
- Understand ARM template structure

[🎥 Provisioning Resources (3:10:21)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=11421s)

**Steps**:

1. Create a sample ARM template:
   ```bash
   cat > sample-arm-template.json << 'ARMEOF'
   {
     "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
     "contentVersion": "1.0.0.0",
     "parameters": {
       "storageAccountName": {
         "type": "string",
         "metadata": { "description": "Name of the storage account" }
       },
       "location": {
         "type": "string",
         "defaultValue": "[resourceGroup().location]",
         "metadata": { "description": "Azure region for resources" }
       },
       "storageSku": {
         "type": "string",
         "defaultValue": "Standard_LRS",
         "allowedValues": ["Standard_LRS", "Standard_GRS", "Standard_ZRS"],
         "metadata": { "description": "Storage account SKU" }
       }
     },
     "variables": {
       "storageAccountFullName": "[toLower(parameters('storageAccountName'))]"
     },
     "resources": [
       {
         "type": "Microsoft.Storage/storageAccounts",
         "apiVersion": "2023-01-01",
         "name": "[variables('storageAccountFullName')]",
         "location": "[parameters('location')]",
         "kind": "StorageV2",
         "sku": {
           "name": "[parameters('storageSku')]"
         },
         "properties": {
           "accessTier": "Hot",
           "minimumTlsVersion": "TLS1_2",
           "supportsHttpsTrafficOnly": true
         },
         "tags": {
           "Environment": "az104-lab",
           "DeployedBy": "ARM"
         }
       }
     ],
     "outputs": {
       "storageAccountId": {
         "type": "string",
         "value": "[resourceId('Microsoft.Storage/storageAccounts', variables('storageAccountFullName'))]"
       },
       "primaryEndpoint": {
         "type": "string",
         "value": "[reference(variables('storageAccountFullName')).primaryEndpoints.blob]"
       }
     }
   }
   ARMEOF
   ```

2. **Interpret the template** — answer these questions:
   - How many parameters does it have? What are their types?
   - Which parameter has a default value?
   - What does the `allowedValues` constraint do for `storageSku`?
   - What function does `[resourceGroup().location]` call?
   - What outputs does the template produce?

3. Validate the template:
   ```bash
   az deployment group validate \
     --resource-group rg-az104-lab-compute \
     --template-file sample-arm-template.json \
     --parameters storageAccountName="starm$(date +%s | tail -c 9)"
   ```

4. Preview with what-if:
   ```bash
   ARM_STORAGE="starm$(date +%s | tail -c 9)"
   az deployment group create \
     --resource-group rg-az104-lab-compute \
     --template-file sample-arm-template.json \
     --parameters storageAccountName="$ARM_STORAGE" \
     --what-if
   ```

5. Deploy the template:
   ```bash
   az deployment group create \
     --resource-group rg-az104-lab-compute \
     --template-file sample-arm-template.json \
     --parameters storageAccountName="$ARM_STORAGE" \
     --query "properties.outputs"
   ```

**Success Criteria**:
- [ ] You can identify parameters, variables, resources, and outputs in the template
- [ ] Template validation passes
- [ ] Deployment creates the storage account with correct properties
- [ ] You can explain: parameters = inputs, variables = computed values, outputs = return values

> 💡 **Exam Tip**: ARM template sections: `$schema`, `contentVersion`, `parameters`, `variables`, `resources`, `outputs`. Key functions to know: `resourceGroup().location`, `resourceId()`, `reference()`, `concat()`, `toLower()`. The exam tests whether you can read and interpret templates, not write them from scratch.

---

## Exercise 7.3: Convert ARM to Bicep and Modify

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Decompile an ARM template to Bicep
- Understand Bicep syntax differences
- Modify and deploy a Bicep file

**Steps**:

1. Convert the ARM template to Bicep:
   ```bash
   az bicep decompile --file sample-arm-template.json
   ```

2. View the generated Bicep file:
   ```bash
   cat sample-arm-template.bicep
   ```

3. Compare the syntax:
   ```
   ARM JSON:  "type": "string", "defaultValue": "[resourceGroup().location]"
   Bicep:     param location string = resourceGroup().location
   
   ARM JSON:  "[toLower(parameters('storageAccountName'))]"
   Bicep:     var storageAccountFullName = toLower(storageAccountName)
   
   ARM JSON:  "type": "Microsoft.Storage/storageAccounts" with nested properties
   Bicep:     resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = { ... }
   ```

4. Modify the Bicep file to add a blob container:
   ```bash
   cat > modified-template.bicep << 'BICEPEOF'
   @description('Name of the storage account')
   param storageAccountName string

   @description('Azure region for resources')
   param location string = resourceGroup().location

   @allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
   @description('Storage account SKU')
   param storageSku string = 'Standard_LRS'

   @description('Name of the blob container')
   param containerName string = 'data'

   var storageAccountFullName = toLower(storageAccountName)

   resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
     name: storageAccountFullName
     location: location
     kind: 'StorageV2'
     sku: { name: storageSku }
     properties: {
       accessTier: 'Hot'
       minimumTlsVersion: 'TLS1_2'
       supportsHttpsTrafficOnly: true
     }
     tags: {
       Environment: 'az104-lab'
       DeployedBy: 'Bicep'
     }
   }

   resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
     parent: storageAccount
     name: 'default'
   }

   resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
     parent: blobService
     name: containerName
     properties: {
       publicAccess: 'None'
     }
   }

   output storageAccountId string = storageAccount.id
   output primaryEndpoint string = storageAccount.properties.primaryEndpoints.blob
   output containerName string = container.name
   BICEPEOF
   ```

5. Deploy the modified Bicep file:
   ```bash
   BICEP_STORAGE="stbicep$(date +%s | tail -c 9)"
   az deployment group create \
     --resource-group rg-az104-lab-compute \
     --template-file modified-template.bicep \
     --parameters storageAccountName="$BICEP_STORAGE" containerName="lab-data" \
     --query "properties.outputs"
   ```

**Success Criteria**:
- [ ] ARM template successfully decompiled to Bicep
- [ ] Modified Bicep adds a blob container as a child resource
- [ ] Deployment succeeds with both storage account and container
- [ ] You can explain the `parent` property for child resources in Bicep

> 💡 **Exam Tip**: The exam expects you to **read and interpret** both ARM JSON and Bicep. Key Bicep concepts: `param`, `var`, `resource`, `output`, `module`, `@decorators`. Bicep compiles to ARM JSON — they produce identical deployments. Know how to use `az bicep decompile` to convert between formats.

---

## Exercise 7.4: Configure VMSS with Autoscaling

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Create a Virtual Machine Scale Set
- Configure autoscale rules (scale out and scale in)
- Understand upgrade policies

[🎥 VMSS (3:30:54)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=12654s)

**Steps**:

1. Create a VMSS:
   ```bash
   az vmss create \
     --name vmss-web \
     --resource-group rg-az104-lab-compute \
     --image Ubuntu2204 \
     --vm-sku Standard_B1s \
     --instance-count 2 \
     --admin-username azurelab \
     --generate-ssh-keys \
     --upgrade-policy-mode Automatic \
     --vnet-name vnet-compute \
     --subnet snet-vms \
     --tags Environment=az104-lab
   ```

2. View the VMSS instances:
   ```bash
   az vmss list-instances \
     --name vmss-web \
     --resource-group rg-az104-lab-compute \
     --query "[].{id:instanceId, state:provisioningState}" --output table
   ```

3. Create autoscale settings:
   ```bash
   az monitor autoscale create \
     --name autoscale-vmss-web \
     --resource-group rg-az104-lab-compute \
     --resource vmss-web \
     --resource-type Microsoft.Compute/virtualMachineScaleSets \
     --min-count 2 \
     --max-count 5 \
     --count 2
   ```

4. Add a scale-out rule (CPU > 75%):
   ```bash
   az monitor autoscale rule create \
     --autoscale-name autoscale-vmss-web \
     --resource-group rg-az104-lab-compute \
     --condition "Percentage CPU > 75 avg 5m" \
     --scale out 1
   ```

5. Add a scale-in rule (CPU < 25%):
   ```bash
   az monitor autoscale rule create \
     --autoscale-name autoscale-vmss-web \
     --resource-group rg-az104-lab-compute \
     --condition "Percentage CPU < 25 avg 5m" \
     --scale in 1
   ```

6. Verify autoscale configuration:
   ```bash
   az monitor autoscale show \
     --name autoscale-vmss-web \
     --resource-group rg-az104-lab-compute \
     --query "{min:profiles[0].capacity.minimum, max:profiles[0].capacity.maximum, rules:profiles[0].rules[].{metric:metricTrigger.metricName, threshold:metricTrigger.threshold, direction:scaleAction.direction}}" \
     --output json
   ```

7. Manually scale to test:
   ```bash
   az vmss scale --name vmss-web --resource-group rg-az104-lab-compute --new-capacity 3
   az vmss list-instances --name vmss-web --resource-group rg-az104-lab-compute \
     --query "[].instanceId" -o tsv
   ```

**Success Criteria**:
- [ ] VMSS created with 2 instances and Automatic upgrade policy
- [ ] Autoscale configured: min=2, max=5
- [ ] Scale-out rule triggers at 75% CPU, scale-in at 25% CPU
- [ ] Manual scaling works

> 💡 **Exam Tip**: VMSS upgrade policies:
> - **Automatic**: Instances updated immediately when model changes
> - **Manual**: You must manually trigger upgrades on each instance
> - **Rolling**: Instances updated in batches with configurable batch size and pause
>
> The exam asks about upgrade policies and when each is appropriate. Rolling is best for zero-downtime updates.

> ⚠️ **Common Mistake**: Setting autoscale min and max to the same value — this disables scaling entirely. Also, not including a **scale-in** rule alongside scale-out causes instances to never decrease.

---

## Exercise 7.5: Deploy a Container to ACI

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Deploy a container to Azure Container Instances
- View container logs and status
- Understand ACI vs other container options

[🎥 Containers (3:34:35)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=12875s)

**Steps**:

1. Deploy a simple web container:
   ```bash
   az container create \
     --name aci-hello \
     --resource-group rg-az104-lab-compute \
     --image mcr.microsoft.com/azuredocs/aci-helloworld:latest \
     --dns-name-label "aci-az104-lab-$(date +%s | tail -c 6)" \
     --ports 80 \
     --cpu 0.5 \
     --memory 0.5 \
     --os-type Linux \
     --restart-policy OnFailure \
     --tags Environment=az104-lab
   ```

2. Check container status:
   ```bash
   az container show \
     --name aci-hello \
     --resource-group rg-az104-lab-compute \
     --query "{name:name, state:instanceView.state, fqdn:ipAddress.fqdn, ip:ipAddress.ip, ports:ipAddress.ports[].port}" \
     --output json
   ```

3. View container logs:
   ```bash
   az container logs --name aci-hello --resource-group rg-az104-lab-compute
   ```

4. Test the container (if it has a public FQDN):
   ```bash
   FQDN=$(az container show --name aci-hello --resource-group rg-az104-lab-compute \
     --query "ipAddress.fqdn" -o tsv)
   curl -s "http://${FQDN}" | head -5
   ```

5. View container events:
   ```bash
   az container show \
     --name aci-hello \
     --resource-group rg-az104-lab-compute \
     --query "containers[0].instanceView.events[].{type:type, message:message}" \
     --output table
   ```

**Success Criteria**:
- [ ] Container deployed and running
- [ ] You can view logs and container state
- [ ] FQDN resolves and the container responds to HTTP requests
- [ ] You understand restart policies (Always, OnFailure, Never)

> 💡 **Exam Tip**: ACI restart policies:
> - **Always**: Restart forever (good for web servers)
> - **OnFailure**: Restart only on non-zero exit code (good for batch jobs)
> - **Never**: Run once and stop (good for one-time tasks)
>
> ACI is best for **simple, isolated containers** — no orchestration. For complex workloads, use AKS or Container Apps.

---

## Exercise 7.6: Create an App Service with Deployment Slots

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Create an App Service plan and web app
- Configure a deployment slot
- Perform a slot swap

[🎥 App Service Plan (3:42:34)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=13354s)

**Steps**:

1. Create an App Service plan:
   ```bash
   az appservice plan create \
     --name plan-az104-lab \
     --resource-group rg-az104-lab-compute \
     --sku S1 \
     --is-linux \
     --tags Environment=az104-lab
   ```

2. Create a web app:
   ```bash
   APP_NAME="app-az104-lab-$(date +%s | tail -c 8)"
   az webapp create \
     --name "$APP_NAME" \
     --resource-group rg-az104-lab-compute \
     --plan plan-az104-lab \
     --runtime "NODE:18-lts" \
     --tags Environment=az104-lab
   echo "Web app: $APP_NAME"
   ```

3. Create a staging deployment slot:
   ```bash
   az webapp deployment slot create \
     --name "$APP_NAME" \
     --resource-group rg-az104-lab-compute \
     --slot staging
   ```

4. Configure different settings for staging:
   ```bash
   az webapp config appsettings set \
     --name "$APP_NAME" \
     --resource-group rg-az104-lab-compute \
     --slot staging \
     --settings ENVIRONMENT=staging VERSION=2.0
   ```

5. Compare production and staging settings:
   ```bash
   echo "=== Production Settings ==="
   az webapp config appsettings list \
     --name "$APP_NAME" \
     --resource-group rg-az104-lab-compute \
     --query "[].{name:name, value:value}" -o table

   echo "=== Staging Settings ==="
   az webapp config appsettings list \
     --name "$APP_NAME" \
     --resource-group rg-az104-lab-compute \
     --slot staging \
     --query "[].{name:name, value:value}" -o table
   ```

6. Perform a slot swap:
   ```bash
   az webapp deployment slot swap \
     --name "$APP_NAME" \
     --resource-group rg-az104-lab-compute \
     --slot staging \
     --target-slot production
   ```

7. Verify the swap:
   ```bash
   echo "Production settings after swap:"
   az webapp config appsettings list \
     --name "$APP_NAME" \
     --resource-group rg-az104-lab-compute \
     --query "[?name=='ENVIRONMENT'].value" -o tsv
   ```

**Success Criteria**:
- [ ] App Service plan (S1) and web app created
- [ ] Staging slot has different app settings
- [ ] Slot swap completes successfully
- [ ] Settings follow the swap (unless marked as "slot setting")

> 💡 **Exam Tip**: Deployment slots allow **zero-downtime deployments**. During a swap, the staging slot is warmed up before traffic switches. Slot-specific settings (marked as "slot settings") **stay with the slot** and don't swap. Connection strings marked as slot settings are commonly used for database connections. Slots require **Standard tier or higher**.

> ⚠️ **Common Mistake**: Forgetting that deployment slots require **Standard (S1) or higher** App Service plan. Free and Basic tiers do NOT support slots.

---

## Exercise 7.7: Design a Highly Available Compute Architecture

**Difficulty**: 🔴 Challenge

**Objectives**:
- Design a multi-layer compute architecture with high availability
- Choose the right compute service for each workload
- Meet specific SLA requirements

**Scenario**:

> *"Your application needs 99.95% SLA. It has a web frontend, an API backend, and background processing jobs. Design the compute architecture."*

**Your Task**:

1. Answer the key design question — Which VM deployment option achieves 99.95% SLA?

   | Option | SLA | Best For |
   |--------|-----|----------|
   | Single VM with Premium SSD | 99.9% | Dev/test, non-critical workloads |
   | Availability Set (2+ VMs) | 99.95% | Protection from rack/update failures |
   | Availability Zones (2+ VMs) | 99.99% | Protection from datacenter failures |
   | VMSS across zones | 99.99% | Auto-scaling with zone redundancy |

2. Design the architecture:

   | Component | Compute Service | HA Strategy | Justification |
   |-----------|----------------|-------------|---------------|
   | Web frontend | ________________ | ________________ | ________________ |
   | API backend | ________________ | ________________ | ________________ |
   | Background jobs | ________________ | ________________ | ________________ |
   | Static assets | ________________ | ________________ | ________________ |

3. Implement the HA configuration:
   ```bash
   # Create an Availability Set
   az vm availability-set create \
     --name avset-api \
     --resource-group rg-az104-lab-compute \
     --platform-fault-domain-count 2 \
     --platform-update-domain-count 5

   # Verify the availability set
   az vm availability-set show \
     --name avset-api \
     --resource-group rg-az104-lab-compute \
     --query "{name:name, faultDomains:platformFaultDomainCount, updateDomains:platformUpdateDomainCount}" \
     --output json
   ```

4. **Discussion questions**:
   - Can you mix Availability Sets and Availability Zones?
   - What happens during a planned maintenance event with Availability Sets?
   - When would you choose VMSS over individual VMs in an Availability Set?

**Success Criteria**:
- [ ] You correctly identified: Availability Zones provide 99.99% SLA (exceeds the 99.95% requirement)
- [ ] Architecture uses appropriate compute services for each workload type
- [ ] You can explain fault domains vs update domains
- [ ] You know: Availability Sets and Zones are **mutually exclusive** for a given VM

> 💡 **Exam Tip**: **Availability Sets** vs **Availability Zones**:
> - **Availability Set**: Multiple fault domains (racks) and update domains within ONE datacenter. 99.95% SLA.
> - **Availability Zone**: Separate physical datacenters within a region. 99.99% SLA.
> - A VM can be in an Availability Set OR an Availability Zone, **never both**.
>
> [🎥 Availability Sets and Zones (3:28:11)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=12491s)

---

## Exercise 7.8: Build and Push a Container to ACR, Deploy to ACI

**Difficulty**: 🔴 Challenge

**Objectives**:
- Create an Azure Container Registry
- Build and push a container image
- Deploy the custom image to ACI

**Steps**:

1. Create an Azure Container Registry:
   ```bash
   ACR_NAME="acraz104-lab$(date +%s | tail -c 8)"
   az acr create \
     --name "$ACR_NAME" \
     --resource-group rg-az104-lab-compute \
     --sku Basic \
     --admin-enabled true \
     --tags Environment=az104-lab
   echo "ACR: $ACR_NAME"
   ```

2. Create a simple Dockerfile:
   ```bash
   mkdir -p az104-lab-app && cd az104-lab-app

   cat > index.html << 'EOF'
   <!DOCTYPE html>
   <html><body>
     <h1>AZ-104 CertLab</h1>
     <p>Container running on Azure Container Instances</p>
     <p>Deployed from Azure Container Registry</p>
   </body></html>
   EOF

   cat > Dockerfile << 'EOF'
   FROM nginx:alpine
   COPY index.html /usr/share/nginx/html/index.html
   EXPOSE 80
   EOF
   ```

3. Build the image using ACR Tasks (no local Docker needed):
   ```bash
   az acr build \
     --registry "$ACR_NAME" \
     --image az104-lab-web:v1 \
     --file Dockerfile \
     .
   ```

4. Verify the image in the registry:
   ```bash
   az acr repository list --name "$ACR_NAME" -o table
   az acr repository show-tags --name "$ACR_NAME" --repository az104-lab-web -o table
   ```

5. Deploy the custom image from ACR to ACI:
   ```bash
   ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" -o tsv)

   az container create \
     --name aci-az104-lab-web \
     --resource-group rg-az104-lab-compute \
     --image "${ACR_NAME}.azurecr.io/az104-lab-web:v1" \
     --registry-login-server "${ACR_NAME}.azurecr.io" \
     --registry-username "$ACR_NAME" \
     --registry-password "$ACR_PASSWORD" \
     --dns-name-label "az104-lab-web-$(date +%s | tail -c 6)" \
     --ports 80 \
     --cpu 0.5 --memory 0.5 \
     --tags Environment=az104-lab
   ```

6. Test the deployment:
   ```bash
   FQDN=$(az container show --name aci-az104-lab-web --resource-group rg-az104-lab-compute \
     --query "ipAddress.fqdn" -o tsv)
   echo "App URL: http://${FQDN}"
   curl -s "http://${FQDN}"
   ```

7. Clean up the app directory:
   ```bash
   cd .. && rm -rf az104-lab-app
   ```

**Success Criteria**:
- [ ] ACR created and image pushed via ACR Tasks
- [ ] Custom container deployed to ACI from ACR
- [ ] Container responds with the custom HTML page
- [ ] You understand ACR SKUs (Basic, Standard, Premium) and when to use each

> 💡 **Exam Tip**: ACR SKUs:
> - **Basic**: Dev/test, limited storage and throughput
> - **Standard**: Most production workloads
> - **Premium**: Geo-replication, private endpoints, content trust
>
> **ACR Tasks** let you build images in the cloud — no local Docker needed. The exam may test this as a scenario for CI/CD without local build tools.

> 📖 **Deep Dive**: [Azure Container Instances](https://learn.microsoft.com/en-us/azure/container-instances/) | [Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/) | [App Service](https://learn.microsoft.com/en-us/azure/app-service/)

---

## Clean Up

```bash
# Remove ACI containers
az container delete --name aci-hello --resource-group rg-az104-lab-compute --yes 2>/dev/null
az container delete --name aci-az104-lab-web --resource-group rg-az104-lab-compute --yes 2>/dev/null

# Remove local template files
rm -f sample-arm-template.json sample-arm-template.bicep modified-template.bicep

# Remove resource group (removes all compute resources)
az group delete --name rg-az104-lab-compute --yes --no-wait

echo "✅ Compute lab resources cleaned up"
```

---

## Key Concepts for the Exam

| Concept | Details |
|---------|---------|
| ARM Templates | JSON format: parameters, variables, resources, outputs. Idempotent deployments. |
| Bicep | Cleaner syntax, compiles to ARM JSON. `param`, `var`, `resource`, `output`, `module` |
| Availability Sets | Fault domains (racks) + update domains. 99.95% SLA. Within one datacenter. |
| Availability Zones | Separate datacenters in a region. 99.99% SLA. Cannot combine with Avail Sets. |
| VMSS | Auto-scaling VMs. Upgrade policies: Automatic, Manual, Rolling. |
| ACI | Simple containers, no orchestration. Restart policies: Always, OnFailure, Never. |
| ACR | Container registry. SKUs: Basic, Standard, Premium (geo-replication). ACR Tasks for cloud builds. |
| App Service Slots | Zero-downtime deployments. Require Standard tier+. Slot settings stay with slot. |
| App Service Plans | Free, Basic (no slots), Standard (slots), Premium (scale), Isolated (dedicated) |

---

*Previous: [Exercise 06 — Storage](06-storage-exercises.md) | Next: [Exercise 08 — Monitoring](08-monitoring-exercises.md)*
