terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}


resource "aws_instance" "demo" {
  ami           = var.ec2_ami
  instance_type = "t2.micro"
  tags = {
    name = var.ec2_instance_name
  }
}


