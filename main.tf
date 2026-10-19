# main.tf - a small public web server on AWS, built with Terraform.
# Creates: VPC -> public subnet -> internet gateway -> route table -> security group -> EC2 web server.

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# The provider tells Terraform which cloud and Region to talk to.
# Credentials come from `aws configure`, so no keys appear in this file.
provider "aws" {
  region = var.region

  # Every resource gets these tags automatically: good practice for cost tracking and ownership.
  default_tags {
    tags = {
      Project   = "terraform-web-lab"
      ManagedBy = "Terraform"
      Owner     = "Lime"
    }
  }
}

variable "region" {
  description = "AWS Region to deploy into"
  type        = string
  default     = "ap-southeast-2" # Sydney
}

variable "instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t3.micro"
}

# Look up the latest Amazon Linux 2023 image ID from AWS, instead of hard-coding one.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Pick the first Availability Zone in the Region.
data "aws_availability_zones" "available" {
  state = "available"
}

# 1. The private network. 10.0.0.0/16 gives 65,536 addresses.
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "lab-vpc" }
}

# 2. A public subnet: a /24 slice (256 addresses, 251 usable) in one AZ.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true # instances here get a public IP

  tags = { Name = "lab-public-subnet" }
}

# 3. The internet gateway: the VPC's door to the internet.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "lab-igw" }
}

# 4. A route table that sends all internet-bound traffic (0.0.0.0/0) through the gateway.
#    This route is what makes the subnet "public".
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "lab-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# 5. A security group: a stateful firewall around the instance.
#    Allows HTTP (port 80) in from anywhere, and all traffic out.
#    No SSH port is opened: there is no need to log in to this server.
resource "aws_security_group" "web" {
  name        = "lab-web-sg"
  description = "Allow HTTP in, all traffic out"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "lab-web-sg" }
}

# 6. The web server. User Data runs once at first boot and installs a web page.
resource "aws_instance" "web" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y httpd
    echo "<h1>Hello from Terraform</h1><p>Built by Lemuel on AWS.</p>" > /var/www/html/index.html
    systemctl enable --now httpd
  EOF

  # Require IMDSv2 (session tokens for instance metadata): a common security baseline.
  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "lab-web-server" }
}

# Printed after `terraform apply`.
output "website_url" {
  description = "Open this in your browser (allow 1-2 minutes after apply)"
  value       = "http://${aws_instance.web.public_ip}"
}
