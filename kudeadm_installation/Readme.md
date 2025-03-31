# Kubeadm Installation Guide on AWS EC2

This guide outlines the steps to set up a Kubernetes cluster using kubeadm on AWS EC2 instances.

---

Resources

https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm

## https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises

## Prerequisites

- **Ubuntu 22.04 (or later)** on EC2 instances
- **sudo privileges** on all nodes
- **AWS account with EC2 access**
- **Security group rules configured**:
  - Allow **SSH (22)**, **API Server (6443)**, and **NodePort range (30000-32767)**.
  - Allow **all traffic between nodes** within the same security group.

---

## Step 1: Launch EC2 Instances

1. Log in to AWS and create **three** Ubuntu 22.04 instances.
2. Assign names:
   - **Control Plane Node** → `k8s-master`
   - **Worker Nodes** → `k8s-worker1`, `k8s-worker2`
3. Configure security group rules as mentioned in prerequisites.

---

## Step 2: Prepare Nodes (Master & Worker

Execute the following commands **on all nodes**:

**User Data Script:**

```bash
#!bin/bash
```

or

**Switch to Root User:**

```bash
sudo su -
```

### Install kubectl

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
chmod +x kubectl
mkdir -p ~/.local/bin
mv ./kubectl ~/.local/bin/kubectl

# and then append (or prepend) ~/.local/bin to $PATH
kubectl version --client
```

### Disable Swap

```bash
sudo swapoff -a
```

### Create the .conf file to load the modules at bootup

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

### Configure Sysctl Parameters

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### Install CRI-O Runtime

```bash
sudo apt-get update -y
sudo apt-get install -y software-properties-common curl apt-transport-https ca-certificates gpg

sudo curl -fsSL https://pkgs.k8s.io/addons:/cri-o:/prerelease:/main/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://pkgs.k8s.io/addons:/cri-o:/prerelease:/main/deb/ /" | sudo tee /etc/apt/sources.list.d/cri-o.list

sudo apt-get update -y
sudo apt-get install -y cri-o

sudo systemctl daemon-reload
sudo systemctl enable crio --now
sudo systemctl start crio.service
```

---

## Step 3: Install Kubernetes Components

Run these commands **on all nodes**.

### Add Kubernetes Repository & Configure Kubelet to Use systemd Cgroup Driver

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y
sudo apt-get install -y kubelet="1.29.0-*" kubectl="1.29.0-*" kubeadm="1.29.0-*"
sudo apt-get update -y
sudo apt-get install -y jq

sudo systemctl enable --now kubelet
sudo systemctl start kubelet
```

---

## Step 4: Initialize Master Node and Install Calico CNI Plugin

Run these commands **only on `k8s-master`**.

```bash
sudo kubeadm config images pull

sudo kubeadm init

 mkdir -p "$HOME"/.kube
 sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
 sudo chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config

 # Network Plugin = calico
 kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml


```

Ensure **port 6443** is open in the security group to allow worker nodes to connect.

---

## Step 5: Generate token on masternode for worker node to join

Run these commands **only on `k8s-worker1` and `k8s-worker2`**.

## Generate on master node

```bash
kubeadm token create --print-join-command
```

### Reset Kubeadm (if rejoining)

```bash
sudo kubeadm reset --force
```

### Run Join Command (From Master Node)

```bash
kubeadm join <master-node-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash> --v=5
```

### Verify Cluster Status (On Master Node)

```bash
kubectl get nodes
```

## Step 6: Deploy nginx App

### **Imperative Deployment**

```bash
kubectl create deployment nginx --image=nginx
kubectl create svc nodeport nginx --tcp=80:80
kubectl get svc
kubectl describe deployment nginx
kubectl scale deployment nginx --replicas=3
```

### **Accessing the Service**

1. Edit inbound rules to allow traffic on the **NodePort**.
2. Find the **NodePort** using:

   ```bash
   kubectl get svc nginx
   ```

3. Access the service using:

   ```bash
   http://<master-node-public-ip>:<NodePort>
   ```

   - You can also use the worker node's IP.

---

## **Declarative YAML Approach**

### **Step 1: Create Deployment YAML**

Create a file named `k8s-deploy.yml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: k8s-deployment
  labels:
    app: k8s-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: k8s-app
  template:
    metadata:
      labels:
        app: k8s-app
    spec:
      containers:
        - name: k8s-app
          image: junny27/hello-k8s
          ports:
            - containerPort: 3000
```

---

### **Step 2: Create Service YAML**

Create a file named `k8s-svc.yml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: k8s-app-service
spec:
  selector:
    app: k8s-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 3000
  type: NodePort
```

---

### **Step 3: Apply the YAML Files**

```bash
kubectl apply -f k8s-deploy.yml
kubectl apply -f k8s-svc.yml
```

---

## **Checking Resources**

```bash
kubectl get pods -o wide
kubectl get svc
kubectl get nodes
kubectl describe service k8s-app-service
```

---

Now lets update the deployment kind so the variable cant be access in the depoloyment from the configmap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
data:
  APP_NAME: 'hello-k8s-app'
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: k8s-deployment
  labels:
    app: k8s-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: k8s-app
  template:
    metadata:
      labels:
        app: k8s-app
    spec:
      containers:
        - name: k8s-app
          image: junny27/hello-k8s
          ports:
            - containerPort: 3000
          env:
            - name: APP_NAME
              valueFrom:
                configMapKeyRef:
                  name: my-config
                  key: APP_NAME
```

## Verify

```bash
kubectl exec -it <pod-name> -- env | grep APP_NAME
```

Always treat confimap immmutable obejct .. because whenever yiou change the value.. it gets configured but pod dont know that it change... now for you to change .. you need to rename the update the metadat.name in the configmap .. then rerefrence it in the deployment ...

Always treat a ConfigMap as an immutable object. When you update its values, the changes are applied, but existing pods won’t automatically detect them. To ensure updates take effect, create a new ConfigMap or update the metadata.name in the configmap with a different name, update the reference in your deployment, and then reapply both the ConfigMap and the deployment.

Lastly always apply resource limit

```yaml
# Always Apply Resource Limits
Setting resource limits ensures fair resource allocation, prevents crashes, and improves cluster stability.

Example:
apiVersion: v1
kind: Pod
metadata:
  name: example-pod
spec:
  containers:
    - name: example-container
      image: nginx
      resources:
        requests:
          memory: "128Mi"  # Guaranteed min resources
          cpu: "250m"
        limits:
          memory: "256Mi"  # Max allowed resources
          cpu: "500m"
```

If a pod exceeds its **CPU limit**, it's throttled. If it exceeds **memory limits**, it's restarted. 🚀

### Troubleshooting & Debugging

- **Live Logs:** View real-time logs for your app:
  ```bash
  kubectl logs -f -l app=deployment-label
  ```
- **Rolling Restart:** Restart a deployment to apply changes:
  ```bash
  kubectl rollout restart deployment <deployment-name>
  ```

To started with Helm charts for your Kubernetes setup with dev and production environments, follow these steps:

### 1. **Install Helm**

If you haven't installed Helm yet, do so with:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 2. **Create a Helm Chart**

Generate a new Helm chart for your app:

```bash
helm create k8s-app
cd k8s-app
```

### 3. **Define Configurations for Dev and Prod**

Inside `k8s-app/values.yaml`, define default values. Then create separate `values-dev.yaml` and `values-prod.yaml` for environment-specific settings.

Example structure:

```
k8s-app/
│── charts/
│── templates/
│── values.yaml
│── values-dev.yaml
│── values-prod.yaml
│── Chart.yaml
```

### 4. **Modify `values.yaml`**

Edit `values.yaml` to include common configurations:

```yaml
replicaCount: 2
image:
  repository: junny27/hello-k8s
  tag: 'latest'
  pullPolicy: IfNotPresent

service:
  type: NodePort
  port: 80
```

### 5. **Customize Dev and Prod Configurations**

Create `values-dev.yaml` for dev:

```yaml
replicaCount: 1
image:
  tag: 'dev'
service:
  type: NodePort
  port: 3000
```

Create `values-prod.yaml` for production:

```yaml
replicaCount: 3
image:
  tag: 'prod'
service:
  type: LoadBalancer
  port: 80
```

### 6. **Deploy with Helm**

For Dev:

```bash
helm install k8s-app-dev ./k8s-app -f values-dev.yaml
```

For Prod:

```bash
helm install k8s-app-prod ./k8s-app -f values-prod.yaml
```

### 7. **Update and Rollout Changes**

If you make changes:

```bash
helm upgrade k8s-app-dev ./k8s-app -f values-dev.yaml
helm upgrade k8s-app-prod ./k8s-app -f values-prod.yaml
```

## Step 7: Auto-Scale Worker Nodes with AWS Lambda

### 1. Install aws cli on OS and Tag Worker Nodes for Auto-Shutdown

```bash
#!/bin/bash

# Change directory to /tmp
cd /tmp

# Download the AWS CLI installation package
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

# Unzip the downloaded package
unzip awscliv2.zip

# Run the AWS CLI installation script
sudo ./aws/install

# Verify the installation
aws --version
```

```bash
aws ec2 create-tags --resources <Instance-ID-2> <Instance-ID-3> <Instance-ID-4> <Instance-ID-5> --tags Key=AutoShutdown,Value=True
```

### 2. Create a Lambda Function (Python 3.x)

```python
import boto3
import datetime

REGION = "us-east-1"
TAG_KEY = "AutoShutdown"
TAG_VALUE = "True"

def get_instances(action):
    ec2 = boto3.client("ec2", region_name=REGION)
    filters = [{"Name": f"tag:{TAG_KEY}", "Values": [TAG_VALUE]}]
    response = ec2.describe_instances(Filters=filters)
    instances = [instance["InstanceId"] for reservation in response["Reservations"] for instance in reservation["Instances"]]
    if instances:
        getattr(ec2, f"{action}_instances")(InstanceIds=instances)
        print(f"{action.capitalize()}ing instances: {instances}")

def lambda_handler(event, context):
    hour = datetime.datetime.utcnow().hour
    get_instances("stop" if 19 <= hour or hour < 8 else "start")
```

### 3. Schedule Lambda with AWS EventBridge

- **Stop at 7 PM:** `cron(0 19 * * ? *)`
- **Start at 8 AM:** `cron(0 8 * * ? *)`

🚀 Now your cluster is optimized for cost efficiency!

---

## Conclusion

Setting up Kubernetes with `kubeadm` on AWS EC2 provides **full control, cost savings, and a valuable learning experience**. However, for **large-scale production deployments**, managed services like **EKS** or **GKE** offer better automation, security, and scalability.

---

To set up CloudWatch alarms that send email notifications when a **pod** or **EC2 instance** goes **down** or **comes back up**, follow these steps:

---

## **Step 1: Create an SNS Topic for Email Alerts**

1. Go to **AWS SNS Console** → [Amazon SNS](https://console.aws.amazon.com/sns/)
2. Click **Create topic**.
3. Select **Standard**.
4. Set **Topic name** to `KubernetesAlerts`.
5. Click **Create topic**.
6. Under **Subscriptions**, click **Create subscription**.
   - **Protocol:** `Email`
   - **Endpoint:** Enter your email.
   - Click **Create subscription**.
7. **Confirm your subscription** via email.

---

## **Step 2: Monitor Pod Status with CloudWatch (UI & CLI)**

### **(UI) Using AWS Console**

1. Go to **CloudWatch** → **Alarms** → **Create Alarm**.
2. Click **Select metric** → Choose **Browse**.
3. Navigate to **Container Insights** → `Performance Metrics`.
4. Find **Pod Count by Status**.
5. Select **Failed Pods Count**.
6. Click **Select metric**.
7. Set the **Threshold**:
   - **Condition**: `Greater than or equal to 1`
   - **Alarm Trigger**: When 1 or more pods fail.
8. Click **Next**.
9. Under **Notification**, select the SNS topic (`KubernetesAlerts`).
10. Click **Create alarm**.

---

### **(CLI) Create CloudWatch Alarm for Pods**

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "PodDownAlarm" \
    --metric-name "kube_pod_status_phase" \
    --namespace "ContainerInsights" \
    --dimensions Name=ClusterName,Value=<Your-Cluster-Name> \
    --statistic "Sum" \
    --period 60 \
    --threshold 1 \
    --comparison-operator "GreaterThanOrEqualToThreshold" \
    --evaluation-periods 1 \
    --alarm-actions "arn:aws:sns:us-east-1:123456789012:KubernetesAlerts"
```

✅ **Now, you will get an email if any pod goes down!**

---

## **Step 3: Monitor EC2 Instance Health (UI & CLI)**

### **(UI) Using AWS Console**

1. Go to **CloudWatch** → **Alarms** → **Create Alarm**.
2. Click **Select metric** → **Browse**.
3. Navigate to **EC2 Metrics** → `StatusCheckFailed_Instance`.
4. Select the metric.
5. Set the **Threshold**:
   - **Condition**: `Greater than or equal to 1`
   - **Alarm Trigger**: When an EC2 instance fails.
6. Click **Next**.
7. Under **Notification**, select `KubernetesAlerts`.
8. Click **Create alarm**.

---

### **(CLI) Create CloudWatch Alarm for EC2**

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "EC2InstanceDownAlarm" \
    --metric-name "StatusCheckFailed_Instance" \
    --namespace "AWS/EC2" \
    --dimensions Name=InstanceId,Value=<Your-Instance-ID> \
    --statistic "Maximum" \
    --period 60 \
    --threshold 1 \
    --comparison-operator "GreaterThanOrEqualToThreshold" \
    --evaluation-periods 1 \
    --alarm-actions "arn:aws:sns:us-east-1:123456789012:KubernetesAlerts"
```

✅ **Now, you will get an email if an EC2 instance fails!**

---

## **Step 4: Monitor When Resources Come Back Up**

We can create a second alarm that triggers when a **pod or EC2 instance recovers**.

### **(CLI) Create an Alarm for Recovery**

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "PodRecoveredAlarm" \
    --metric-name "kube_pod_status_phase" \
    --namespace "ContainerInsights" \
    --dimensions Name=ClusterName,Value=<Your-Cluster-Name> \
    --statistic "Sum" \
    --period 60 \
    --threshold 0 \
    --comparison-operator "LessThanOrEqualToThreshold" \
    --evaluation-periods 1 \
    --alarm-actions "arn:aws:sns:us-east-1:123456789012:KubernetesAlerts"
```

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "EC2InstanceRecoveredAlarm" \
    --metric-name "StatusCheckFailed_Instance" \
    --namespace "AWS/EC2" \
    --dimensions Name=InstanceId,Value=<Your-Instance-ID> \
    --statistic "Maximum" \
    --period 60 \
    --threshold 0 \
    --comparison-operator "LessThanOrEqualToThreshold" \
    --evaluation-periods 1 \
    --alarm-actions "arn:aws:sns:us-east-1:123456789012:KubernetesAlerts"
```

✅ **Now, you will get an email when a pod or EC2 instance recovers!**

---

## **Step 5: Test the Setup**

1. **Kill a Pod**:
   ```bash
   kubectl delete pod <pod-name>
   ```
2. **Stop an EC2 Instance**:
   ```bash
   aws ec2 stop-instances --instance-ids <Your-Instance-ID>
   ```
3. Check **CloudWatch Alarms** and confirm you received an email.
4. **Restart the instance and pod**:
   ```bash
   kubectl apply -f <pod.yaml>
   aws ec2 start-instances --instance-ids <Your-Instance-ID>
   ```
5. Confirm you received a **recovery email**.

---

✅ **Your monitoring system is now fully set up!** 🚀 Let me know if you need any refinements!
