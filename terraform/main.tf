module "vpc" {
  source = "./modules/vpc"
  prefix = var.prefix
}

module "ec2" {
  source                = "./modules/ec2"
  prefix                = var.prefix
  vpc_id                = module.vpc.vpc_id
  subnet_id             = module.vpc.public_subnet_id
  docker_compose_content = file("${path.root}/../docker/docker-compose.yml")
  docker_username       = var.docker_username
  docker_password       = var.docker_password
  aws_access_key        = var.aws_access_key
  aws_secret_key        = var.aws_secret_key
  aws_region            = var.aws_region
  efs_dns_name          = module.efs.dns_name
  depends_on            = [null_resource.credentials_upload]
}

module "efs" {
  source                  = "./modules/efs"
  prefix                  = var.prefix
  vpc_id                  = module.vpc.vpc_id
  subnet_id               = module.vpc.public_subnet_id
  allowed_security_groups = [module.ec2.security_group_id]
}

resource "null_resource" "efs_cleanup" {
  triggers = {
    efs_id = module.efs.id
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      aws efs describe-mount-targets --file-system-id ${self.triggers.efs_id} --query 'MountTargets[*].MountTargetId' --output text | xargs -I {} aws efs delete-mount-target --mount-target-id {}
      echo "Waiting for mount targets to be deleted..."
      sleep 30
    EOT
  }
}

resource "null_resource" "credentials_upload" {
  triggers = {
    aws_access_key = var.aws_access_key
    aws_secret_key = var.aws_secret_key
    aws_region = var.aws_region
    efs_dns_name = module.efs.dns_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      cat > credentials.sh << 'EOF'
      #!/bin/bash
      export AWS_ACCESS_KEY_ID='${var.aws_access_key}'
      export AWS_SECRET_ACCESS_KEY='${var.aws_secret_key}'
      export AWS_REGION='${var.aws_region}'
      export EFS_DNS_NAME='${module.efs.dns_name}'
      EOF
      aws s3 cp credentials.sh s3://iykonect-aws-parallel/credentials.sh
      rm credentials.sh
    EOT
  }
}
