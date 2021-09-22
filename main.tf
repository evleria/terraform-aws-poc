terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.58.0"
    }
  }
}

provider "aws" {
  profile = "default"
  region  = "eu-central-1"
}

# Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "main_1a" {
  cidr_block = "10.0.1.0/24"
  vpc_id = aws_vpc.main.id
  availability_zone = "eu-central-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "main-public-1a-subnet"
  }
}

resource "aws_subnet" "main_1b" {
  cidr_block = "10.0.2.0/24"
  vpc_id = aws_vpc.main.id
  availability_zone = "eu-central-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "main-public-1b-subnet"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-internet-gateway"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route" "public_internet_gateway" {
  route_table_id = aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.main.id
}

# Main Security Group
resource "aws_security_group" "main" {
  name = "main_sg"
  vpc_id = aws_vpc.main.id
}

resource "aws_security_group_rule" "main_unrestricted_egress" {
  security_group_id = aws_security_group.main.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "main_http_ingress" {
  security_group_id = aws_security_group.main.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "main_ssh_ingress" {
  security_group_id = aws_security_group.main.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# ECR
resource "aws_ecs_cluster" "main" {
  name = "main_cluster"
}

resource "aws_ecr_repository" "main" {
  name = "hello_world_service"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Temp EC2
resource "aws_security_group" "internal" {
  name = "internal"
  vpc_id = aws_vpc.main.id
}

resource "aws_security_group_rule" "internal_unrestricted_egress" {
  security_group_id = aws_security_group.internal.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "internal_http_ingress" {
  security_group_id = aws_security_group.internal.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [aws_subnet.main_1a.cidr_block, aws_subnet.main_1b.cidr_block]
}

resource "aws_security_group_rule" "internal_ssh_ingress" {
  security_group_id = aws_security_group.internal.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_network_interface" "foo" {
  subnet_id   = aws_subnet.main_1a.id
  private_ips = ["10.0.1.10"]
  security_groups = [aws_security_group.internal.id]

  tags = {
    Name = "primary_network_interface"
  }
}

resource "aws_instance" "foo" {
  ami           = "ami-06e3e9f1bf6945099"
  instance_type = "t3.micro"
  key_name = "evleria"

  network_interface {
    network_interface_id = aws_network_interface.foo.id
    device_index         = 0
  }

  credit_specification {
    cpu_credits = "unlimited"
  }
}

# ELB
resource "aws_lb" "main" {
  name               = "main-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.main.id]
  subnets            = [aws_subnet.main_1a.id, aws_subnet.main_1b.id]

  tags = {
    Environment = "production"
  }
}

resource "aws_lb_target_group" "blue" {
  name     = "blue-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group_attachment" "test" {
  target_group_arn = aws_lb_target_group.blue.id
  target_id        = aws_instance.foo.id
  port             = 80
}

resource "aws_lb_listener" "blue" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}