data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  common_tags = {
    Project     = "platform-sandbox"
    ManagedBy   = "terraform"
    Environment = var.environment_tag
    Owner       = "rinatmyrzaliev"
  }
}
