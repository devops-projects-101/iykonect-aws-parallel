resource "aws_efs_file_system" "main" {
  creation_token = "${var.prefix}-efs"
  encrypted      = true

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${var.prefix}-efs"
  }
}

resource "aws_efs_mount_target" "main" {
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.subnet_id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "${var.prefix}-efs-sg"
  description = "Security group for EFS mount targets"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = var.allowed_security_groups
  }
}
