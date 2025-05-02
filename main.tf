provider "aws" {
  region = "us-east-1"
}

# Generate private key
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create key pair
resource "aws_key_pair" "id_rsa" {
  key_name   = "id_rsa"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

# Save private key to local file
resource "local_file" "private_key_file" {
  filename        = "${path.cwd}/id_rsa.pem"
  content         = tls_private_key.ec2_key.private_key_pem
  file_permission = "0600"
}

# Security group for auto-ec2-1 (SSH + Jenkins)
resource "aws_security_group" "ec2_1_group" {
  name        = "ec2-1-group"
  description = "Security group for EC2-1 (SSH + Jenkins)"

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group for auto-ec2-2 (SSH + Docker)
resource "aws_security_group" "ec2_2_group" {
  name        = "ec2-2-group"
  description = "Security group for EC2-2 (SSH + Docker)"

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow Docker"
    from_port   = 2376
    to_port     = 2376
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch EC2 instances
resource "aws_instance" "auto_ec2" {
  count                  = 2
  ami                    = "ami-084568db4383264d4"
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.id_rsa.key_name
  vpc_security_group_ids = [count.index == 0 ? aws_security_group.ec2_1_group.id : aws_security_group.ec2_2_group.id]

  tags = {
    Name = "auto-ec2-${count.index + 1}"
  }
}

# Outputs
output "ssh_key_path" {
  value = local_file.private_key_file.filename
}

output "jenkins_dns" {
  value = aws_instance.auto_ec2[0].public_dns
}

output "docker_dns" {
  value = aws_instance.auto_ec2[1].public_dns
}

# Ansible inventory file
resource "local_file" "ansible_inventory" {
  filename = "../ansible/inventory.ini"
  content  = <<-EOT
  [servers]
  jenkins-srv ansible_host=${aws_instance.auto_ec2[0].public_dns} ansible_user=ubuntu ansible_ssh_private_key_file=${local_file.private_key_file.filename} ansible_ssh_common_args='-o StrictHostKeyChecking=no'
  docker-srv ansible_host=${aws_instance.auto_ec2[1].public_dns} ansible_user=ubuntu ansible_ssh_private_key_file=${local_file.private_key_file.filename} ansible_ssh_common_args='-o StrictHostKeyChecking=no'
  EOT
}