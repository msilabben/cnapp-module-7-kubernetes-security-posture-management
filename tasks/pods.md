# Pods


## Access kubernetes 

1. Open a codespace in this repository. 
2. Use the command `az login` to log into the azure environment from the terminal. Use your given credentials.
3. List the accounts connected to the Azure tennent with the command `az account list --output table`. 
4. Choose the one called "sandbox" with the command `az account set --subscription sandbox`.
5. Get your aks credentials with the command `az aks get-credentials --resource-group module-7-aks-rg --name module-7-aks`. 
6. View current nodes with `kubectl get nodes`


## Raw Pod

**Deploy a pod** 
1. Create file "nginx-pod.yaml", with `vim nginx-pod.yaml`. 
2. Paste the following into the file, and update with your own name: 
```
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
```

**Find pod information**
1. View the pod name with the command: `kubectl get pod nginx-<name> -o jsonpath='{.metadata.name}'`
2. View the pod IP with the command: `kubectl get pod nginx-<name> -o jsonpath='{.status.podIP}'`
3. View the pod node with the command: `kubectl get pod nginx-<name> -o jsonpath='{.spec.nodeName}'`
4. View the pod container image with the command: `kubectl get pod nginx-<name> -o jsonpath='{.spec.containers[0].image}'`
5. View the pod labels with the command `kubectl get pod nginx-<name> --show-labels`
6. View the pod's current phase with the command `kubectl get pod nginx-<name> -o jsonpath='{.status.phase}'`
7. To see all information at once, you can use the command `kubectl describe pod nginx-<name>`.

**Read the logs**
1. View the pods logs with the command `kubectl logs -f nginx-<name>`

**Open shell inside the container**
1. To open a shell inside the container use the command `kubectl exec -it nginx-<name> -- /bin/bash`

**Delete a pod**
1. Check to see which pods are currently running with the command `kubectl get pods`
2. Delete your pod with the command `kubectl delete pod nginx-<name>`
3. Use the same command as step 1 to see that the pod is deleted. 


## Deployment

**Deploy through deployment**
1. Make a new file called "<name>-deployment.yaml". 
2. Paste the following into the file, and update with your own name: 
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment-<name>
  labels:
    app: nginx-<name>
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-<name>
  template:
    metadata:
      labels:
        app: nginx-<name>
        env: demo
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
```
3. To apply a deployment, use the command `kubectl apply -f <name>-deployment.yaml`.
4. Check that a pod has been spun up with the command `kubectl get pods -o wide`

**Reconfigure deployment**
1. Reconfigure the deployment by editing the deployment file and change from 1 to 2 replicas, and apply the deployment again. 
2. View the pods running now, and check that there is two replicas running for your pod. 

**View information about deployment**
1. View information about the deployment using the command `kubectl get deployment`. 
2. View information about the replicasets with the command `kubectl get replicasets`.
3. View information about the pods with the command `kubectl get pods`

**Delete a pod**
1. Delete one of the pods with the commandi, and watch what happens with the pods 
```
kubectl delete pod <name-of-pod>
kubectl get pods --watch
```

 **Scale deployment**
1. Scale the deployment to 3 replicas, by using the commad `kubectl scale deployment nginx-deployment-<name> --replicas=3`. 
2. View the pods running now, and check that there is three replicas running for your pod. 

**Delete deployment**
1. Delete the deployment with the command `kubectl delete deployment nginx-deployment-<name>`


