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

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_ssm_parameter" "amazon_linux" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_key_pair" "deploy" {
  key_name   = "mango-cats-deploy"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_security_group" "app" {
  name        = "mango-cats-app"
  description = "Public app and restricted SSH access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Public web app"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from deployment computer"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  egress {
    description = "Outbound access for OS updates"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "mango-cats-app" }
}

resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.amazon_linux.value
  instance_type               = "t3.micro"
  subnet_id                   = sort(data.aws_subnets.default.ids)[0]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.deploy.key_name
  vpc_security_group_ids      = [aws_security_group.app.id]

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens = "required"
  }

  credit_specification {
    cpu_credits = "standard"
  }

  lifecycle {
    ignore_changes = [ami]
  }

  tags = { Name = "mango-cats" }
}

output "public_ip" {
  value = aws_instance.app.public_ip
}

output "app_url" {
  value = "http://${aws_instance.app.public_ip}:8080"
}

output "health_url" {
  value = "http://${aws_instance.app.public_ip}:8080/health"
}
