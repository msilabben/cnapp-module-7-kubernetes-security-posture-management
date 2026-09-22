# Admission policies 

## Create an admission policy 
0. If you have kubeconfig enforced, use command `unset KUBECONFIG` to unset the configuration. 
1. Create your own cluster within the resource group we have used, with the command: 
```
az aks create \
  --resource-group module-7-aks-rg \
  --name <name>-aks \
  --location norwayeast \
  --node-count 1 \
  --node-vm-size Standard_D2_v2 \
  --tags owner=<name>-workshop \
  --generate-ssh-keys
```
2. Try to spin up a privileged deployment. Make a file called privileged-deployment.yaml, and populate with the following information: 
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: privileged-test
  labels:
    app: privileged-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: privileged-test
  template:
    metadata:
      labels:
        app: privileged-test
    spec:
      containers:
      - name: privileged-container
        image: nginx:latest
        securityContext:
          privileged: true
      restartPolicy: Always
```
Use the command `kubectl apply -f privileged-deployment.yaml` to spin up the deployment. See that it spins up with `kubectl get deployment privileged-test`. After checking that it has spun up, take it down again with `kubectl delete deployment privileged-test`
3. Enable azure policy add-on with the command `az aks enable-addons --addons azure-policy --name <name>-aks --resource-group module-7-aks-rg`.
4. Find the subcription ID with the command `az account show --query id -o tsv`
5. Google or read the documentation to find the azure policy ID for denying privileged containers, 
6. Add the "deny privileged container" policy with the following command: 
```
az policy assignment create \
  --name deny-privileged-containers \
  --display-name "Deny privileged containers in AKS" \
  --policy "<policy-id>" \
  --params '{ "effect": { "value": "deny" } }' \
  --scope /subscriptions/<subscription-id>/resourceGroups/module-7-aks-rg/providers/Microsoft.ContainerService/managedClusters/<name>-aks
```
This assignment will deny all privileged containers. If you want to allow privileged container, but rather log that it is non-compliant, set the value to "audit" rather than "deny". It will take some time before this takes effect (5-15 min). 
7. Try to deploy the privileged deployment again, with the same deployment as in step 2. See that it does not spin up a pod, and that with the command `kubectl events deployments privileged-test` it shows that the reason for this is because it is denied. 