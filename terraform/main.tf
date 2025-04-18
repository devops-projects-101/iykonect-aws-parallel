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
}
