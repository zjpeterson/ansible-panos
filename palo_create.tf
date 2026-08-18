terraform {
  backend "s3" {
    bucket  = "palo-tfstate-asdf-us-east-2-an"
    key     = "palo.tfstate"
    region  = "us-east-2"
    encrypt = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    aap = {
      source  = "ansible/aap"
      version = "~> 1.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    time = {
      source = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}

variable aap_host {
  type    = string
  default = "https://aap-aap.apps.cluster-asdf.dyn.redhatworkshops.io"
}

variable "aap_workflow_id" {
  type        = number
  default     = 39 
}

variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "aws_ami" {
  type        = string
  default     = "ami-asdf"
}

variable "subnet_id" {
  type        = string
  default     = "subnet-asdf"
}

variable "sg_id" {
  type        = string
  default     = ["sg-asdf"]
}

variable "fw_name" {
  type        = string
  default     = "panos-new"
}

provider "aws" {
  region = var.aws_region
}

provider "aap" {
  host = var.aap_host
  insecure_skip_verify = true
  # cli: export AAP_TOKEN="your_access_token"
}

resource "time_static" "fw_launch_time" {
  triggers = {
    instance_id = aws_instance.palo_fw.id
  }
}

resource "tls_private_key" "palo_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "palo_keypair" {
  key_name   = "palo-key-new"
  public_key = tls_private_key.palo_key.public_key_openssh
}

resource "aws_instance" "palo_fw" {
  ami           = var.aws_ami
  instance_type = "c5n.xlarge"
  key_name      = aws_key_pair.palo_keypair.key_name
  ebs_optimized = true
  subnet_id     = var.subnet_id
  associate_public_ip_address = true
  vpc_security_group_ids = var.sg_id
  tags = {
    Name       = var.fw_name
  }
}

resource "aap_workflow_job" "firewall_config" {
  workflow_job_template_id = var.aap_workflow_id
  extra_vars = jsonencode({
    firewall_name = var.fw_name
    firewall_ec2_id = aws_instance.palo_fw.id
    firewall_ssh_private_key  = tls_private_key.palo_key.private_key_pem
    firewall_launch_unix     = time_static.fw_launch_time.unix
    run_time         = timestamp()
  })
  wait_for_completion = false 
}
