## Pods


### Access kubernetes 

1. Log into the Azure portal with your given credentials.
2. Click on the cloud shell button on the top right to open a shell. These tasks are written for the "bash" shell.
3. List the accounts connected to the Azure tennent with the command `az account list --output table`. 
4. Choose the one called "sandbox" with the command `az account set --subscription sandbox`.
5. Get your aks credentials with the command `az aks get-credentials --resource-group module-7-aks-rg --name module-7-aks`. 
6. View current nodes with `kubectl get nodes`


### Deploy a pod 
1. Create file "nginx-pod.yaml", with `vim nginx-pod.yaml`. 
2. Paste the following into the file, and update with your own name: 
'''
apiVersion: v1
kind: Pod
metadata:
  name: nginx-<name>
  labels:
    app: nginx-<name>
    env: demo
spec:
  containers:
  - name: nginx-<name>
    image: nginx:latest
    ports:
    - containerPort: 80
''' 
3. View the pod name with the command: `kubectl get pod nginx-<name> -o jsonpath='{.metadata.name}'`
4. View the pod IP with the command: `kubectl get pod nginx-<name> -o jsonpath='{.status.podIP}'`
5. View the pod node with the command: `kubectl get pod nginx-<name> -o jsonpath='{.spec.nodeName}'`
6. View the pod container image with the command: `kubectl get pod nginx-<name> -o jsonpath='{.spec.containers[0].image}'`
View information about you pod with the commamd `kubectl describe pod nginx-<name>`.
