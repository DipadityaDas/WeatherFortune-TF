terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region  = "ap-south-1"
  profile = "Dipaditya"
}

# Create a VPC in the same Availability Zone
resource "aws_vpc" "tfvpc" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
  tags = {
    Name = "Tf-vpc"
  }
}

# Creating Internet Gateway
resource "aws_internet_gateway" "tfgateway" {
  vpc_id = aws_vpc.tfvpc.id

  tags = {
    description = "Allows connection to VPC and EC2 instance."
  }

  depends_on = [
    aws_vpc.tfvpc
  ]
}

# Creating a Routing Table
resource "aws_route_table" "tfroute" {
  vpc_id = aws_vpc.tfvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tfgateway.id
  }

  tags = {
    description = "Route table for inbound traffic to vpc"
  }

  depends_on = [
    aws_internet_gateway.tfgateway
  ]
}

# Creating a subnet in vpc
resource "aws_subnet" "tfsubnet" {
  vpc_id                  = aws_vpc.tfvpc.id
  availability_zone       = "ap-south-1b"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "Tf-subnet"
  }

  depends_on = [
    aws_vpc.tfvpc
  ]
}

# Creating an association between subnet and route table
resource "aws_route_table_association" "tfrouset" {
  subnet_id      = aws_subnet.tfsubnet.id
  route_table_id = aws_route_table.tfroute.id

  depends_on = [
    aws_subnet.tfsubnet,
    aws_route_table.tfroute
  ]
}

# Creating a New Security Group
resource "aws_security_group" "tfsg" {
  name        = "Tf-security_group"
  description = "Allow HTTP, ssh for inbound traffic."
  vpc_id      = aws_vpc.tfvpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Tf-Firewall"
  }
  depends_on = [
    aws_route_table_association.tfrouset
  ]
}

# Generating a private_key
resource "tls_private_key" "tfkey" {
  algorithm = "RSA"
  rsa_bits  = 4096
  depends_on = [
    aws_security_group.tfsg
  ]
}

resource "local_file" "private-key" {
  content  = tls_private_key.tfkey.private_key_pem
  filename = "Tfkey.pem"
}

resource "aws_key_pair" "deployer" {
  key_name   = "Tfkey"
  public_key = tls_private_key.tfkey.public_key_openssh
  depends_on = [
    tls_private_key.tfkey
  ]
}

# Create an EC2 Instance
resource "aws_instance" "tfos" {
  ami                         = "ami-0bcf5425cdc1d8a85"
  instance_type               = "t2.xlarge"
  key_name                    = aws_key_pair.deployer.key_name
  vpc_security_group_ids      = ["${aws_security_group.tfsg.id}"]
  subnet_id                   = aws_subnet.tfsubnet.id
  associate_public_ip_address = true
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.tfkey.private_key_pem
    host        = aws_instance.tfos.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install python3 -y",
    ]
  }
  tags = {
    Name = "OpenShift-Cluster"
  }
}

resource "aws_eip" "tfeip"  {
	vpc       = true
  instance  = aws_instance.tfos.id

	tags = {
		Name = "Tf-eip"
	}
	depends_on = [
		aws_instance.tfos
	]
}

# Output public ip of EC2 Instance
output "Public_IP" {
  value = aws_eip.tfeip.public_ip
}

# Output Routing-Suffix for Oc Cluster
output "routing_suffix" {
  value = "${aws_eip.tfeip.public_ip}.nip.ip"
}

# Output public dns of EC2 Instance
output "Public_Hostname" {
  value = aws_eip.tfeip.public_dns
}

# Output Web Console of OpenShift Cluster
output "Web_Console" {
  value = "https://${aws_eip.tfeip.public_dns}:8443/console"
}