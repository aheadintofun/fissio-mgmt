# Azure Deployment Guide

Complete instructions for deploying fissio-mgmt (OpenProject) and the full Fissio platform to Azure using Container Apps.

## Architecture Overview

```
                          Azure Front Door (CDN + WAF)
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
                    ▼               ▼               ▼
         ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
         │ fissio-site  │ │ fissio-docs  │ │ fissio-crmi  │
         │ Container App│ │ Container App│ │ Container App│
         └──────────────┘ └──────────────┘ └──────────────┘
                    │               │               │
                    ▼               ▼               ▼
         ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
         │ fissio-base  │ │ fissio-mgmt  │ │   Azure      │
         │ Container App│ │ Container App│ │  PostgreSQL  │
         └──────────────┘ └──────────────┘ └──────────────┘
```

## Prerequisites

### Local Tools

```bash
# Install Azure CLI
brew install azure-cli

# Install Docker
brew install --cask docker

# Login to Azure
az login

# Set subscription (if you have multiple)
az account set --subscription "Your Subscription Name"
```

### Azure Resources Needed

| Resource | Purpose | Estimated Cost |
|----------|---------|----------------|
| Resource Group | Container for all resources | Free |
| Container Registry | Store Docker images | ~$5/month (Basic) |
| Container Apps Environment | Run containers | Pay-per-use |
| Container Apps (x5) | Run each Fissio app | ~$0.000024/vCPU-s |
| Azure PostgreSQL Flexible | Database for CRM & MGMT | ~$30/month (Burstable) |
| Azure Blob Storage | File storage | ~$0.02/GB/month |
| Azure Front Door | CDN + SSL + WAF | ~$35/month |

**Estimated total: ~$80-120/month** for a small deployment

---

## Step 1: Create Azure Resources

### 1.1 Set Variables

```bash
# Configuration - EDIT THESE
RESOURCE_GROUP="fissio-prod"
LOCATION="eastus"
ACR_NAME="fissioacr"  # Must be globally unique, lowercase
ENVIRONMENT="fissio-env"

# App names
SITE_APP="fissio-site"
DOCS_APP="fissio-docs"
CRMI_APP="fissio-crmi"
BASE_APP="fissio-base"
MGMT_APP="fissio-mgmt"
```

### 1.2 Create Resource Group

```bash
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION
```

### 1.3 Create Container Registry

```bash
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Basic \
  --admin-enabled true

ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv)

az acr login --name $ACR_NAME
```

### 1.4 Create Container Apps Environment

```bash
az extension add --name containerapp --upgrade

az containerapp env create \
  --name $ENVIRONMENT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION
```

### 1.5 Create PostgreSQL for OpenProject

OpenProject needs its own PostgreSQL database (or you can use an external one):

```bash
# Create database for OpenProject
az postgres flexible-server db create \
  --resource-group $RESOURCE_GROUP \
  --server-name fissio-postgres \
  --database-name openproject
```

### 1.6 Create Blob Storage for OpenProject Assets

```bash
az storage container create \
  --name openproject-assets \
  --account-name fissiostorage
```

---

## Step 2: Deploy fissio-mgmt (OpenProject)

### 2.1 Deploy Container App

OpenProject uses the official Docker image directly (no custom build needed):

```bash
# Generate secret key
SECRET_KEY=$(openssl rand -hex 64)

# PostgreSQL connection
PG_HOST="fissio-postgres.postgres.database.azure.com"
PG_USER="fissio_admin"
PG_PASS="YourSecurePassword123!"

az containerapp create \
  --name $MGMT_APP \
  --resource-group $RESOURCE_GROUP \
  --environment $ENVIRONMENT \
  --image openproject/openproject:17 \
  --target-port 80 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 2 \
  --cpu 1.0 \
  --memory 2Gi \
  --env-vars \
    "SECRET_KEY_BASE=secretref:secret-key" \
    "OPENPROJECT_HOST__NAME=fissio-mgmt.azurecontainerapps.io" \
    "OPENPROJECT_HTTPS=true" \
    "OPENPROJECT_DEFAULT__LANGUAGE=en" \
    "DATABASE_URL=secretref:database-url"

# Add secrets
az containerapp secret set \
  --name $MGMT_APP \
  --resource-group $RESOURCE_GROUP \
  --secrets \
    "secret-key=$SECRET_KEY" \
    "database-url=postgresql://$PG_USER:$PG_PASS@$PG_HOST:5432/openproject?sslmode=require"
```

### 2.2 Configure Persistent Storage

For production, attach Azure Files for asset persistence:

```bash
# Create Azure Files share
az storage share create \
  --name openproject-assets \
  --account-name fissiostorage

# Get storage key
STORAGE_KEY=$(az storage account keys list \
  --resource-group $RESOURCE_GROUP \
  --account-name fissiostorage \
  --query "[0].value" -o tsv)

# Add storage to Container Apps environment
az containerapp env storage set \
  --name $ENVIRONMENT \
  --resource-group $RESOURCE_GROUP \
  --storage-name openproject-storage \
  --azure-file-account-name fissiostorage \
  --azure-file-account-key $STORAGE_KEY \
  --azure-file-share-name openproject-assets \
  --access-mode ReadWrite

# Mount to container
az containerapp update \
  --name $MGMT_APP \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars "OPENPROJECT_ATTACHMENTS__STORAGE__PATH=/var/openproject/assets"
```

---

## Step 3: Deploy Other Fissio Apps

See the DEPLOYMENT.md in each repository:
- [fissio-site/DEPLOYMENT.md](../fissio-site/DEPLOYMENT.md)
- [fissio-docs/DEPLOYMENT.md](../fissio-docs/DEPLOYMENT.md)
- [fissio-crmi/DEPLOYMENT.md](../fissio-crmi/DEPLOYMENT.md)
- [fissio-base/DEPLOYMENT.md](../fissio-base/DEPLOYMENT.md)

---

## Step 4: Configure Custom Domain

### 4.1 Get Default URL

```bash
az containerapp show --name $MGMT_APP --resource-group $RESOURCE_GROUP --query "properties.configuration.ingress.fqdn" -o tsv
```

### 4.2 Add Custom Domain

```bash
az containerapp hostname add \
  --name $MGMT_APP \
  --resource-group $RESOURCE_GROUP \
  --hostname "projects.fissio.com"

az containerapp hostname bind \
  --name $MGMT_APP \
  --resource-group $RESOURCE_GROUP \
  --hostname "projects.fissio.com" \
  --environment $ENVIRONMENT \
  --validation-method CNAME
```

**DNS Configuration**:

| Type | Name | Value |
|------|------|-------|
| CNAME | @ | fissio-site.azurecontainerapps.io |
| CNAME | docs | fissio-docs.azurecontainerapps.io |
| CNAME | crm | fissio-crmi.azurecontainerapps.io |
| CNAME | analytics | fissio-base.azurecontainerapps.io |
| CNAME | projects | fissio-mgmt.azurecontainerapps.io |

---

## Step 5: Set Up CI/CD with GitHub Actions

### 5.1 GitHub Actions Workflow

Create `.github/workflows/deploy.yml`:

```yaml
name: Build and Deploy to Azure

on:
  push:
    branches: [main]
  workflow_dispatch:

env:
  RESOURCE_GROUP: fissio-prod
  CONTAINER_APP_NAME: fissio-mgmt

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Login to Azure
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Deploy to Container App
        run: |
          az containerapp update \
            --name ${{ env.CONTAINER_APP_NAME }} \
            --resource-group ${{ env.RESOURCE_GROUP }} \
            --image openproject/openproject:17
```

### 5.2 Add GitHub Secrets

| Secret Name | Value |
|-------------|-------|
| `AZURE_CREDENTIALS` | JSON from service principal creation |

---

## Step 6: Monitoring and Logging

```bash
# Stream logs
az containerapp logs show \
  --name $MGMT_APP \
  --resource-group $RESOURCE_GROUP \
  --follow

# Check health
az containerapp show \
  --name $MGMT_APP \
  --resource-group $RESOURCE_GROUP \
  --query "properties.runningStatus"
```

---

## Step 7: Scaling Configuration

```bash
az containerapp update \
  --name $MGMT_APP \
  --resource-group $RESOURCE_GROUP \
  --min-replicas 1 \
  --max-replicas 3 \
  --scale-rule-name http-scaling \
  --scale-rule-type http \
  --scale-rule-http-concurrency 50
```

---

## Quick Reference

### URLs After Deployment

| App | Default URL | Custom Domain |
|-----|-------------|---------------|
| fissio-site | fissio-site.azurecontainerapps.io | fissio.com |
| fissio-docs | fissio-docs.azurecontainerapps.io | docs.fissio.com |
| fissio-crmi | fissio-crmi.azurecontainerapps.io | crm.fissio.com |
| fissio-base | fissio-base.azurecontainerapps.io | analytics.fissio.com |
| fissio-mgmt | fissio-mgmt.azurecontainerapps.io | projects.fissio.com |

### Useful Commands

```bash
# List all container apps
az containerapp list --resource-group $RESOURCE_GROUP -o table

# Restart OpenProject
az containerapp revision restart \
  --name $MGMT_APP \
  --resource-group $RESOURCE_GROUP

# Update environment variable
az containerapp update \
  --name $MGMT_APP \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars "NEW_VAR=value"

# Delete everything (careful!)
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

### Cost Optimization Tips

1. **Scale to zero** for dev/test environments (not recommended for OpenProject due to startup time)
2. Use **Burstable PostgreSQL** tier
3. Use **Basic Container Registry** tier initially
4. OpenProject needs ~1GB RAM minimum; don't under-provision

---

## Troubleshooting

### Container won't start

```bash
az containerapp logs show --name $MGMT_APP --resource-group $RESOURCE_GROUP
az containerapp revision list --name $MGMT_APP --resource-group $RESOURCE_GROUP -o table
```

### Database connection issues

```bash
# Test PostgreSQL connectivity
az postgres flexible-server connect \
  --name fissio-postgres \
  --admin-user fissio_admin \
  --admin-password "YourPassword"

# Verify database exists
az postgres flexible-server db list \
  --resource-group $RESOURCE_GROUP \
  --server-name fissio-postgres
```

### OpenProject specific issues

```bash
# Check Rails logs
az containerapp exec \
  --name $MGMT_APP \
  --resource-group $RESOURCE_GROUP \
  --command "tail -100 /var/log/openproject/production.log"

# Run database migrations
az containerapp exec \
  --name $MGMT_APP \
  --resource-group $RESOURCE_GROUP \
  --command "bundle exec rails db:migrate"
```
