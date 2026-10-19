# Terraform Web Lab

A small AWS environment built entirely with Terraform: a VPC with a public subnet and a web server, checked automatically by a GitHub Actions pipeline on every push.

## What it builds

```
Internet
   │
Internet Gateway
   │
VPC 10.0.0.0/16  (ap-southeast-2, Sydney)
   └── Public subnet 10.0.1.0/24
         │   Route table: 0.0.0.0/0 → Internet Gateway
         │
         └── EC2 t3.micro (Amazon Linux 2023, Apache web server)
               Security group: inbound HTTP 80 only, all outbound
```

| Resource | Purpose |
| --- | --- |
| VPC | Private network for the lab |
| Public subnet | Holds the web server; instances get a public IP |
| Internet gateway + route table | Gives the subnet a route to the internet |
| Security group | Stateful firewall allowing HTTP in; no SSH port open |
| EC2 instance | Web server installed at first boot via User Data |

## Design choices

- **No hard-coded credentials.** Terraform uses the local AWS CLI profile.
- **No hard-coded AMI.** The latest Amazon Linux 2023 image is looked up from AWS Systems Manager Parameter Store.
- **No SSH access.** Port 22 is closed; the server is configured entirely by User Data.
- **IMDSv2 required** on the instance, a common security baseline.
- **Default tags** (`Project`, `ManagedBy`) on every resource for cost tracking and ownership.
- **Secrets and state kept out of Git** via `.gitignore`; the provider lock file is committed to pin versions.

## CI pipeline

`.github/workflows/terraform.yml` runs on every push and pull request:

1. `terraform fmt -check`: enforces standard formatting
2. `terraform init -backend=false`: downloads providers without needing AWS access
3. `terraform validate`: checks the configuration is valid

## Run it

Prerequisites: Terraform, the AWS CLI configured with `aws configure`.

```bash
terraform init
terraform plan
terraform apply      # prints website_url when done
terraform destroy    # removes everything
```

## Next steps

- **Remote state:** store state in S3 with locking so a team can share it safely.
- **Plan in CI:** run `terraform plan` in GitHub Actions using GitHub OIDC to assume an AWS IAM role, avoiding long-lived access keys.
- **High availability:** subnets in two Availability Zones, an Application Load Balancer and an Auto Scaling Group.
- **Private app tier:** move the server to a private subnet behind the load balancer, with a NAT gateway for outbound updates.
- **Modules:** split the network and compute into reusable Terraform modules.
- **Security scanning:** add a tool such as Checkov or tfsec to the pipeline.
