# Get latest Ubuntu 20.04 AMI
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

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
    tags = merge({
      Name = "${var.prefix}-root-volume"
    }, var.tags)
  }

  vpc_security_group_ids = [aws_security_group.instance.id]
  user_data_base64       = base64gzip(file("${path.module}/user-data.sh"))
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  tags = merge({
    Name        = "${var.prefix}-instance"
    LastUpdated = formatdate("YYYY-MM-DD-hh-mm", timestamp())
  }, var.tags)

  lifecycle {
    create_before_destroy = true
  }
}
