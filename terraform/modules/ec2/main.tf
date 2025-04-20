data "aws_region" "current" {}

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
    tags = {
      Name = "${var.prefix}-root-volume"
    }
  }

  vpc_security_group_ids = [aws_security_group.instance.id]
  user_data = templatefile("${path.module}/user-data.sh", {
    docker_registry    = local.ecr_registry
    redis_image       = local.docker_images.redis.image
    redis_port        = local.docker_images.redis.ports[0]
    api_image         = local.docker_images.api.image
    api_port          = local.docker_images.api.ports[0]
    prometheus_image  = local.docker_images.prometheus.image
    prometheus_port   = local.docker_images.prometheus.ports[0]
    grafana_image     = local.docker_images.grafana.image
    grafana_port      = local.docker_images.grafana.ports[0]
    react_image       = local.docker_images.react.image
    react_port        = local.docker_images.react.ports[0]
    renderer_image    = local.docker_images.renderer.image
    renderer_port     = local.docker_images.renderer.ports[0]
    AWS_REGION        = data.aws_region.current.name
  })
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  tags = {
    Name        = "${var.prefix}-instance"
    ManagedBy   = "terraform"
    Project     = "parallel"
    LastUpdated = formatdate("YYYY-MM-DD-hh-mm", timestamp())
  }

  lifecycle {
    create_before_destroy = true
  }
}
