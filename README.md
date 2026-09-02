# CNAPP Module 7: Kubernetes Security Posture Management

This repository contains:

- A small static waiting page in `app/`
- A non-root NGINX container definition in `Dockerfile`
- Terraform configuration for the AKS lab in `terraform/`

The Terraform configuration deploys an Azure Kubernetes Service (AKS) cluster
with Azure defaults wherever practical:

- One resource group in `Norway East`
- One AKS cluster with a system-assigned managed identity
- One `Standard_D2_v2` node in the default system node pool
- The AKS-selected default Kubernetes version and networking settings

## Preview the waiting page

From the repository root, run:

```bash
python3 -m http.server 8080 --directory app
```

Then open [http://localhost:8080](http://localhost:8080). Stop the server with
<kbd>Ctrl</kbd>+<kbd>C</kbd>.

## Build and run the container

Build the image from the repository root:

```bash
docker build --tag skatteetaten-waiting-page:local .
```

Run it locally as an unprivileged NGINX container:

```bash
docker run --rm \
  --name skatteetaten-waiting-page \
  --publish 8080:8080 \
  skatteetaten-waiting-page:local
```

Open [http://localhost:8080](http://localhost:8080), then stop the container
with <kbd>Ctrl</kbd>+<kbd>C</kbd>.

> [!IMPORTANT]
> AKS worker nodes and related Azure resources incur charges. Run
> `terraform -chdir=terraform destroy` when you no longer need the lab.

## Prerequisites

- An Azure subscription
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [Docker](https://docs.docker.com/get-docker/) for building the application image
- [Terraform](https://developer.hashicorp.com/terraform/install) 1.5 or newer
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/)

## Deploy the cluster

Sign in and select the Azure subscription to use:

```bash
az login
az account list --output table
az account set --subscription "<subscription-id-or-name>"
az account show --output table
```

The AzureRM 4.x provider requires the subscription ID. Export the ID selected
above so it is not stored in source code:

```bash
export ARM_SUBSCRIPTION_ID="$(az account show --query id --output tsv)"
```

Initialize, preview, and deploy the Terraform configuration:

```bash
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=tfplan
terraform -chdir=terraform apply tfplan
```

The deployment commonly takes several minutes. To change the defaults, copy
the example variables file and edit it before running the plan:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

`terraform/terraform.tfvars` is ignored by Git.

## Connect to AKS

Make sure Azure CLI is signed in to the same subscription, then download and
merge the AKS credentials into your kubeconfig:

```bash
az login
az account set --subscription "$ARM_SUBSCRIPTION_ID"

az aks get-credentials \
  --resource-group "$(terraform -chdir=terraform output -raw resource_group_name)" \
  --name "$(terraform -chdir=terraform output -raw cluster_name)" \
  --overwrite-existing
```

Verify the active context and access to the cluster:

```bash
kubectl config current-context
kubectl cluster-info
kubectl get nodes
```

For a terminal without a browser, use `az login --use-device-code` instead of
`az login`.

## Remove the lab

```bash
terraform -chdir=terraform destroy
```
