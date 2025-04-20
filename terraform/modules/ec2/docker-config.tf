locals {
  ecr_registry = "571664317480.dkr.ecr.${var.aws_region}.amazonaws.com"
  
  docker_images = {
    redis = {
      image = "${local.ecr_registry}/iykonect-images:redis"
      ports = ["6379:6379"]
      env   = ["REDIS_PASSWORD=IYKONECTpassword"]
      cmd   = "redis-server --requirepass IYKONECTpassword --bind 0.0.0.0"
    }
    api = {
      image = "${local.ecr_registry}/iykonect-images:api"
      ports = ["8080:80"]  # Updated to match docker-compose
    }
    prometheus = {
      image = "${local.ecr_registry}/iykonect-images:prometheus"
      ports = ["9090:9090"]
    }
    grafana = {
      image = "${local.ecr_registry}/iykonect-images:grafana"
      ports = ["3000:3000"]  # Updated to match docker-compose
      user  = "root"
    }
    sonarqube = {
      image = "sonarqube:community"
      ports = ["9000:9000"]
    }
    redis_exporter = {
      image = "oliver006/redis_exporter"
      ports = ["9121:9121"]
      env = [
        "REDIS_ADDR=redis:6379",
        "REDIS_PASSWORD=IYKONECTpassword"
      ]
    }
    renderer = {
      image = "grafana/grafana-image-renderer:latest"
      ports = ["8081:8081"]
    }
  }
}