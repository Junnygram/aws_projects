#### Commands:

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

---

### 🔄 Remove State from Project 1

Remove the instance from Terraform state without deleting the resource:

```bash
terraform state rm aws_instance.demo
```

---

### 🔍 Get EC2 Instance ID

1. Go to the **AWS EC2 Console**.
2. Copy the instance ID (e.g., `i-0abcd1234efgh5678`).

---

### ✨ Project 2 Configuration

---

### 🗺️ Import EC2 into Project 2

```bash
terraform init
terraform import aws_instance.demo i-0abcd1234efgh5678
```

---

### ✅ Verify the Import

```bash
terraform plan
```

- Output should show **no changes**, indicating that the instance is successfully managed by Project 2.

---

### 🌟 Apply to Verify Output

```bash
terraform apply -auto-approve
```

- You should see the instance details printed from the **output.tf** file.

---

This setup demonstrates moving an EC2 instance from one Terraform project to another by managing state and re-importing. Let me know if you need any adjustments!
