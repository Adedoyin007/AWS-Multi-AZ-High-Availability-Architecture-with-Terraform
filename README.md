# AWS Multi-AZ High Availability Architecture with Terraform

## 1. Project Overview

This project deploys a highly available Nginx web application on AWS using Terraform (Infrastructure as Code). The infrastructure spans two Availability Zones in the London region (`eu-west-2`).

An internet-facing Application Load Balancer distributes incoming HTTP traffic across EC2 instances managed by an Auto Scaling Group. Each instance runs Nginx and displays its instance ID and Availability Zone.

## 2. Architecture

- **VPC:** `10.0.0.0/16`
- **Public subnets:** Host the Application Load Balancer and NAT Gateways.
- **Private subnets:** Host Nginx EC2 instances.
- **Application Load Balancer:** Routes HTTP requests to healthy instances.
- **NAT Gateways:** One per Availability Zone for outbound internet access from private subnets.
- **Auto Scaling Group:** Minimum 2, desired 2, maximum 4 instances.
- **CPU target tracking:** Target average CPU utilization of 50%.
- **Launch Template:** Defines the EC2 instance and its bootstrap script.

## 3. Technologies Used

AWS, Terraform, Amazon EC2, Amazon VPC, Application Load Balancer, Auto Scaling, NAT Gateway, Ubuntu 24.04 LTS, Nginx, AWS CLI, and Bash.

## 4. Project Structure and Configuration

### 4.1 `providers.tf`

**Purpose:** Sets the minimum Terraform version, specifies the AWS provider, and configures the deployment region.

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

### 4.2 `variables.tf`

**Purpose:** Defines reusable inputs for the AWS region, project name, EC2 instance type, Auto Scaling capacity, and CPU target.

```hcl
variable "aws_region" {
  description = "AWS region for the deployment"
  type        = string
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Name used to identify project resources"
  type        = string
  default     = "multiaz-nginx"
}

variable "instance_type" {
  description = "EC2 instance type for the web servers"
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  description = "Minimum number of EC2 instances"
  type        = number
  default     = 2
}

variable "desired_capacity" {
  description = "Desired number of EC2 instances"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of EC2 instances"
  type        = number
  default     = 4
}

variable "cpu_target_value" {
  description = "Target average CPU utilization for scaling"
  type        = number
  default     = 50
}
```

### 4.3 `networking.tf`

**Purpose:** Creates the VPC, two public subnets, two private subnets, Internet Gateway, Elastic IPs, NAT Gateways, route tables, and subnet associations. Each private subnet routes outbound traffic through its own Availability Zone's NAT Gateway.

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  availability_zones = slice(
    data.aws_availability_zones.available.names,
    0,
    2
  )

  public_subnets = {
    public_a = {
      cidr = "10.0.1.0/24"
      az   = local.availability_zones[0]
    }
    public_b = {
      cidr = "10.0.2.0/24"
      az   = local.availability_zones[1]
    }
  }

  private_subnets = {
    private_a = {
      cidr    = "10.0.11.0/24"
      az      = local.availability_zones[0]
      nat_key = "a"
    }
    private_b = {
      cidr    = "10.0.12.0/24"
      az      = local.availability_zones[1]
      nat_key = "b"
    }
  }

  nat_gateways = {
    a = { public_subnet_key = "public_a" }
    b = { public_subnet_key = "public_b" }
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-${each.key}"
    Project = var.project_name
    Tier    = "public"
  }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = {
    Name    = "${var.project_name}-${each.key}"
    Project = var.project_name
    Tier    = "private"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "${var.project_name}-public-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  for_each = local.nat_gateways

  domain = "vpc"

  tags = {
    Name    = "${var.project_name}-nat-eip-${each.key}"
    Project = var.project_name
  }
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_gateways

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.value.public_subnet_key].id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name    = "${var.project_name}-nat-${each.key}"
    Project = var.project_name
  }
}

resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[each.value.nat_key].id
  }

  tags = {
    Name    = "${var.project_name}-${each.key}-rt"
    Project = var.project_name
    Tier    = "private"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
```

### 4.4 `security.tf`

**Purpose:** Controls inbound and outbound traffic. The ALB accepts HTTP requests on port 80, while EC2 web servers accept HTTP only from the ALB security group.

```hcl
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  description = "Allow HTTP traffic to the Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward traffic to web servers"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-alb-sg"
    Project = var.project_name
  }
}

resource "aws_security_group" "web" {
  name_prefix = "${var.project_name}-web-"
  description = "Allow HTTP traffic only from the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from the load balancer"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-web-sg"
    Project = var.project_name
  }
}
```

### 4.5 `load_balancer.tf`

**Purpose:** Creates the target group, internet-facing Application Load Balancer, and HTTP listener. The target group checks `/` and forwards requests to healthy EC2 instances.

```hcl
resource "aws_lb_target_group" "web" {
  name        = "${var.project_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name    = "${var.project_name}-target-group"
    Project = var.project_name
  }
}

resource "aws_lb" "web" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  tags = {
    Name    = "${var.project_name}-alb"
    Project = var.project_name
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
```

### 4.6 `launch_template.tf`

**Purpose:** Selects the current Ubuntu 24.04 LTS AMI and defines the EC2 instance type, security group, IMDSv2 metadata settings, and bootstrap script.

```hcl
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-"
  image_id      = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.web.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = filebase64("${path.module}/user_data.sh")

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name    = "${var.project_name}-web"
      Project = var.project_name
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

### 4.7 `autoscaling.tf`

**Purpose:** Maintains the desired EC2 capacity across the private subnets and registers instances with the load balancer. CPU target tracking is configured to target 50% average utilization.

```hcl
resource "aws_autoscaling_group" "web" {
  name                = "${var.project_name}-asg"
  min_size            = var.min_size
  desired_capacity    = var.desired_capacity
  max_size            = var.max_size
  vpc_zone_identifier = [for subnet in aws_subnet.private : subnet.id]

  target_group_arns = [aws_lb_target_group.web.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-web"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${var.project_name}-cpu-target"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.web.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = var.cpu_target_value
  }
}
```

### 4.8 `outputs.tf`

**Purpose:** Displays useful information after deployment, including the VPC ID, Availability Zones, ALB DNS name, application URL, and Auto Scaling Group name.

```hcl
output "vpc_id" {
  description = "ID of the project VPC"
  value       = aws_vpc.main.id
}

output "availability_zones" {
  description = "Availability Zones used by the project"
  value       = local.availability_zones
}

output "load_balancer_dns" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.web.dns_name
}

output "application_url" {
  description = "URL of the Nginx web application"
  value       = "http://${aws_lb.web.dns_name}"
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.web.name
}
```

### 4.9 `user_data.sh`

**Purpose:** Installs Nginx on each new EC2 instance, retrieves its instance ID and Availability Zone using IMDSv2, writes a custom HTML page, and enables and restarts Nginx.

```bash
#!/bin/bash
set -euxo pipefail

apt-get update
apt-get install -y nginx

TOKEN=$(curl -sS -X PUT \
  "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -sS \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

AZ=$(curl -sS \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat > /var/www/html/index.nginx-debian.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Multi-AZ Nginx Application</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      max-width: 700px;
      margin: 80px auto;
      padding: 24px;
      background: #f4f7fb;
      color: #172b4d;
    }
    main {
      background: white;
      padding: 32px;
      border-radius: 12px;
      box-shadow: 0 4px 18px #0001;
    }
    h1 { color: #1463c5; }
  </style>
</head>
<body>
  <main>
    <h1>Multi-AZ High Availability Project</h1>
    <p>Nginx is running successfully on AWS EC2.</p>
    <p><strong>Instance ID:</strong> ${INSTANCE_ID}</p>
    <p><strong>Availability Zone:</strong> ${AZ}</p>
    <p>Served through an Application Load Balancer.</p>
  </main>
</body>
</html>
EOF

systemctl enable nginx
systemctl restart nginx
```

### 4.10 `.gitignore`

**Purpose:** Excludes local Terraform state, provider downloads, plans, and variable files that should not be committed to Git.

```gitignore
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
terraform.tfvars
terraform.tfvars.json
crash.log
crash.*.log
```

Preserve any additional exclusions already present in your project's `.gitignore`.

## 5. Deployment Steps

### Step 1: Configure AWS Access

```bash
aws configure
aws sts get-caller-identity
```

### Step 2: Initialize Terraform

```bash
terraform init
```

### Step 3: Format and Validate

```bash
terraform fmt
terraform validate
```

### Step 4: Review and Deploy

```bash
terraform plan
terraform apply
```

Review the plan and confirm when prompted.

### Step 5: Retrieve the Application URL

```bash
terraform output application_url
```

Open the returned URL in a browser.

## 6. Verification Results

- Both EC2 instances are `InService` and `Healthy`.
- The instances run in `eu-west-2a` and `eu-west-2b`.
- The application is reachable through the Application Load Balancer.
- The Auto Scaling Group is configured with minimum 2, desired 2, and maximum 4 instances.
- CPU target tracking is configured for 50% average utilization.
- Recent instance launch and termination activities completed successfully.

## 7. Security and Cost Considerations

- EC2 instances are deployed in private subnets.
- Web traffic to EC2 is allowed only from the ALB security group.
- IMDSv2 is required for instance metadata access.
- Do not commit AWS credentials or Terraform state files to a public repository.
- EC2, NAT Gateways, the ALB, and data transfer can incur AWS charges. Monitor resource usage while the project is running.

## 8. Conclusion

This project demonstrates how Terraform can provision a Multi-AZ web application architecture on AWS using network isolation, load balancing, health checks, and CPU-based Auto Scaling. Both application instances were verified as healthy and reachable through the load balancer.
