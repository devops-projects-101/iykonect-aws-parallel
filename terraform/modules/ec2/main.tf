resource "aws_security_group" "instance" {
  name        = "${var.prefix}-sg"
  description = "Security group for EC2 instance"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}-sg"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

resource "aws_instance" "main" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [aws_security_group.instance.id]
  user_data = templatefile("${path.module}/user-data.sh", {
    aws_access_key = var.aws_access_key
    aws_secret_key = var.aws_secret_key
    aws_region     = var.aws_region
    efs_dns_name   = var.efs_dns_name
  })

  tags = {
    Name = "${var.prefix}-instance"
  }
}

resource "aws_ebs_volume" "docker_volume" {
  availability_zone = aws_instance.main.availability_zone
  size             = 50
  type             = "gp3"

  tags = {
    Name = "${var.prefix}-docker-volume"
  }
}

resource "aws_volume_attachment" "docker_volume_att" {
  device_name = "/dev/sdf"  # Will show up as /dev/nvme1n1 on nitro instances
  volume_id   = aws_ebs_volume.docker_volume.id
  instance_id = aws_instance.main.id
}
