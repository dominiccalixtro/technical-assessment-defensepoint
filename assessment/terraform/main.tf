##############################
# Data Sources
##############################

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

##############################
# Locals
##############################

locals {
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
}

##############################
# VPC
##############################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
}

##############################
# Subnets
##############################

resource "aws_subnet" "public_subnet" {
  count = length(var.public_subnets_cidr)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnets_cidr[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_subnet" {
  count = length(var.private_subnets_cidr)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnets_cidr[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = false
}

##############################
# Internet Gateway
##############################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

##############################
# NAT Gateway
##############################

resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet[0].id

  depends_on = [aws_internet_gateway.this]
}

##############################
# Route Tables
##############################

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

# Private Route Table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_rt_association" {
  count          = length(aws_subnet.public_subnet)
  route_table_id = aws_route_table.public_rt.id
  subnet_id      = aws_subnet.public_subnet[count.index].id
}

resource "aws_route_table_association" "private_rt_association" {
  count          = length(aws_subnet.private_subnet)
  route_table_id = aws_route_table.private_rt.id
  subnet_id      = aws_subnet.private_subnet[count.index].id
}

##############################
# IAM Role and Instance Profile
##############################

resource "aws_iam_role" "this" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.role_name}-instance-profile"
  role = aws_iam_role.this.name
}

##############################
# Security Group
##############################

resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  description = "Security group for private EC2 (Wazuh)"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = []
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

##############################
# EC2 Instance
##############################

resource "aws_instance" "this" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.instance_type
  iam_instance_profile        = aws_iam_instance_profile.this.name
  subnet_id                   = aws_subnet.private_subnet[0].id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = false

  user_data = file("${path.module}/../scripts/setup.sh")
}