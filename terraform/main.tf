# pqc-bench Phase 7 — one nginx target + one load generator, same AZ, cluster placement.
# Both are plain Ubuntu 24.04 arm64: the target builds nginx itself (build time is one
# of the measurements), so no pre-baked AMI is used.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "pqc-bench", Phase = "7" }
  }
}

data "aws_ami" "ubuntu_arm64" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet" "az" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = "${var.region}${var.az_suffix}"
  default_for_az    = true
}

resource "aws_placement_group" "bench" {
  name     = "pqc-bench-phase7"
  strategy = "cluster"
}

resource "aws_security_group" "bench" {
  name        = "pqc-bench-phase7"
  description = "pqc-bench phase 7: ssh from operator, 443 between bench hosts"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "ssh from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }
  ingress {
    description = "https between bench hosts"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    self        = true
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

locals {
  # Raise fd limits for root/ubuntu sessions; nginx and the loadgen open many sockets.
  user_data = <<-EOF
    #!/bin/bash
    cat > /etc/security/limits.d/90-bench.conf <<'L'
    *    soft nofile 1048576
    *    hard nofile 1048576
    root soft nofile 1048576
    root hard nofile 1048576
    L
    sysctl -w net.ipv4.ip_local_port_range="1024 65535"
    sysctl -w net.ipv4.tcp_tw_reuse=1
    sysctl -w net.core.somaxconn=65535
    mkdir -p /opt/phase7 && chown ubuntu:ubuntu /opt/phase7
  EOF
}

resource "aws_instance" "target" {
  ami                    = data.aws_ami.ubuntu_arm64.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.az.id
  vpc_security_group_ids = [aws_security_group.bench.id]
  key_name               = var.key_name
  placement_group        = aws_placement_group.bench.id
  user_data              = local.user_data
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
  tags = { Name = "pqc-bench-phase7-target" }
}

resource "aws_instance" "loadgen" {
  ami                    = data.aws_ami.ubuntu_arm64.id
  instance_type          = var.loadgen_instance_type
  subnet_id              = data.aws_subnet.az.id
  vpc_security_group_ids = [aws_security_group.bench.id]
  key_name               = var.key_name
  placement_group        = aws_placement_group.bench.id
  user_data              = local.user_data
  root_block_device {
    volume_size = 12
    volume_type = "gp3"
  }
  tags = { Name = "pqc-bench-phase7-loadgen" }
}
