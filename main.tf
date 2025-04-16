terraform {
  backend "s3" {
    bucket         = "terraform-codepipline-prod-aws-bucket"
    key            = "terraform.tfstate"
    region         = "ca-central-1"
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_canonical_user_id" "current" {}
data "aws_cloudfront_log_delivery_canonical_user_id" "cloudfront" {}

data "aws_iam_policy_document" "cloudfront_s3_policy" {
  statement {
    sid    = "AllowCloudFrontServicePrincipal"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = ["s3:GetObject"]

    resources = ["arn:aws:s3:::app-prod-trillium-cdn/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = ["arn:aws:cloudfront::402893944840:distribution/E32WYBAFCL4S3L"]
    }
  }
}


provider "aws" {
  region = var.aws_region
}

locals {
  current_identity = data.aws_caller_identity.current.arn
  tags = {
    ProjectName    = "TrilliumInnovationCareInc"
    Github = "https://github.com/TrilliumInnovationCareInc/AWS_IAC_Terraform_Prod.git"
    Environment  = "Prod"
    Prod = "Terraform Code"
  }
  igw_tags = {
    ProjectName    = "TrilliumInnovationCareInc"
    Github = "https://github.com/TrilliumInnovationCareInc/AWS_IAC_Terraform_Prod.git"
    Environment  = "Prod"
    Prod = "Terraform Code"
  }
  nat_gateway_tags = {
    ProjectName    = "TrilliumInnovationCareInc"
    Github = "https://github.com/TrilliumInnovationCareInc/AWS_IAC_Terraform_Prod.git"
    Environment  = "Prod"
    Prod = "Terraform Code"
    }
  default_route_table_tags ={
    ProjectName    = "TrilliumInnovationCareInc"
    Github = "https://github.com/TrilliumInnovationCareInc/AWS_IAC_Terraform_Prod.git"
    Environment  = "Prod"
    Prod = "Terraform Code"
  }
}

################  Prod ##################
################  VPC ##################

module "prod_vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name = "TrilliumInnovationCare-Prod"
  cidr = var.vpc_cidr
  azs                 = var.azs
  private_subnets     = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 8, k)]
  public_subnets      = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 8, k + 4)]
  database_subnets    = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 8, k + 8)]
  private_subnet_names = ["Private-Subnet-1a", "Private-Subnet-1b"]
  public_subnet_names = ["Public-Subnet-1a", "Public-Subnet-1b"]
  database_subnet_names    = ["DB-Subnet-1a", "DB-Subnet-1b"]
  database_dedicated_network_acl = true
  private_dedicated_network_acl = true
  public_dedicated_network_acl = true
  create_database_subnet_group  = true
  manage_default_network_acl    = false
  manage_default_route_table    = false
  manage_default_security_group = false
  enable_dns_hostnames = true
  enable_dns_support   = true
  enable_nat_gateway = true
  single_nat_gateway = true
  enable_vpn_gateway = false
  create_egress_only_igw = false
  create_igw = true
  enable_dhcp_options              = false

  # VPC Flow Logs (Cloudwatch log group and IAM role will be created)
  vpc_flow_log_iam_role_name            = "vpc-complete-trilliumInnovationCare-role"
  vpc_flow_log_iam_role_use_name_prefix = false
  enable_flow_log                       = true
  create_flow_log_cloudwatch_log_group  = true
  create_flow_log_cloudwatch_iam_role   = true
  flow_log_max_aggregation_interval     = 60
  tags = local.tags
}

################  KMS Key ##################

module "prod_kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "3.1.1"
  deletion_window_in_days = 7
  description             = "TrilliumInnovationCare Infra. will use this key"
  enable_key_rotation     = false
  is_enabled              = true
  key_usage               = "ENCRYPT_DECRYPT"
  multi_region            = false

  # Policy
  enable_default_policy                  = true
  key_owners                             = [local.current_identity]
  key_administrators                     = [local.current_identity]
  key_users                              = [local.current_identity]
  key_service_users                      = [local.current_identity]
  key_symmetric_encryption_users         = [local.current_identity]
  key_hmac_users                         = [local.current_identity]
  key_asymmetric_public_encryption_users = [local.current_identity]
  key_asymmetric_sign_verify_users       = [local.current_identity]
  key_statements = [
    {
      sid = "CloudWatchLogs"
      actions = [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*"
      ]
      resources = ["*"]

      principals = [
        {
          type        = "Service"
          identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
        }
      ]

      conditions = [
        {
          test     = "ArnLike"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values = [
            "arn:aws:logs:ca-central-1:${data.aws_caller_identity.current.account_id}:log-group:*",
          ]
        }
      ]
    }
  ]

  # Aliases
  aliases = ["one", "foo/bar"]
  aliases_use_name_prefix = true

  tags = local.tags
}

################  EC2 App Server ##################
module "prod_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"
  name        = "Prod-App-Security-group"
  description = "Security group for App usage with EC2 instance"
  vpc_id      = module.prod_vpc.vpc_id
  egress_rules        = ["all-all"]
  ingress_with_source_security_group_id = [
    {
      from_port                = 22
      to_port                  = 22
      protocol                 = "tcp"
      description              = "Jump server"
      source_security_group_id = module.jump_security_group.security_group_id
    },
    {
      from_port                = 8082
      to_port                  = 8082
      protocol                 = "tcp"
      description              = "alb sg"
      source_security_group_id = "sg-0ef39a4bb9b31ebe8"
    },
    {
      from_port                = 8086
      to_port                  = 8086
      protocol                 = "tcp"
      description              = "alb sg"
      source_security_group_id = "sg-0ef39a4bb9b31ebe8"
    },
    {
      from_port                = 8083
      to_port                  = 8083
      protocol                 = "tcp"
      description              = "alb sg"
      source_security_group_id = "sg-0ef39a4bb9b31ebe8"
    },
    {
      from_port                = 3306
      to_port                  = 3306
      protocol                 = "tcp"
      description              = "rds sg"
      source_security_group_id = module.prod_db_security_group.security_group_id
    },
  ]
  tags = local.tags
}

module "prod_app_ec2-instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "5.7.1"
  name = "prod-app-trillium"
  ami                    = "ami-0a590ca28046d073e"
  instance_type          = "t3.medium" # used to set core count below
  key_name = "Trillium"
  availability_zone      = element(module.prod_vpc.azs, 0)
  subnet_id              = element(module.prod_vpc.private_subnets, 0)
  vpc_security_group_ids = [module.prod_security_group.security_group_id]
  create_eip             = false
  disable_api_stop       = false
  disable_api_termination = true
  create_iam_instance_profile = true
  iam_role_description        = "IAM role for EC2 instance"
  iam_role_policies = {
    AdministratorAccess = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
    CloudWatchFullAccess =  "arn:aws:iam::aws:policy/CloudWatchFullAccess"
    SecretsManagerReadWrite =  "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  }

  # only one of these can be enabled at a time
  hibernation = true
  associate_public_ip_address = false
  instance_initiated_shutdown_behavior = "stop"
  cpu_credits = "unlimited"
  monitoring = true
  metadata_options = {
    http_tokens = "required"
  }
  user_data_replace_on_change = false
  enable_volume_tags = false
  root_block_device = [
    {
      encrypted   = true
      # kms_key_id  = module.prod_kms.arn 
      kms_key_id  = module.prod_kms.key_arn
      volume_type = "gp3"
      throughput  = 200
      volume_size = 50
      tags = local.tags
    },
  ]

  ebs_block_device = [
    {
      device_name = "/dev/sdf"
      volume_type = "gp3"
      volume_size = 50
      throughput  = 200
      encrypted   = true
      kms_key_id  = module.prod_kms.key_arn
      tags = local.tags
    }
  ]
  tags = local.tags
}
#######################New Portal and Admin ########################
module "prod_portal_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"
  name        = "prod-portal-Security-group"
  description = "Security group for App portal usage with EC2 instance"
  vpc_id      = module.prod_vpc.vpc_id
  egress_rules        = ["all-all"]
  ingress_with_source_security_group_id = [
    {
      from_port                = 22
      to_port                  = 22
      protocol                 = "tcp"
      description              = "Jump server"
      source_security_group_id = module.jump_security_group.security_group_id
    },
    {
      from_port                = 8081
      to_port                  = 8081
      protocol                 = "tcp"
      description              = "alb sg"
      source_security_group_id = "sg-0ef39a4bb9b31ebe8"
    },
    {
      from_port                = 8080
      to_port                  = 8080
      protocol                 = "tcp"
      description              = "alb sg"
      source_security_group_id = "sg-0ef39a4bb9b31ebe8"
    },
    {
      from_port                = 8084
      to_port                  = 8084
      protocol                 = "tcp"
      description              = "alb sg"
      source_security_group_id = "sg-0ef39a4bb9b31ebe8"
    },
    {
      from_port                = 8085
      to_port                  = 8085
      protocol                 = "tcp"
      description              = "alb sg"
      source_security_group_id = "sg-0ef39a4bb9b31ebe8"
    },
    {
      from_port                = 3306
      to_port                  = 3306
      protocol                 = "tcp"
      description              = "rds sg"
      source_security_group_id = module.prod_db_security_group.security_group_id
    },
  ]
  tags = local.tags
}

module "prod_portal_ec2-instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "5.7.1"
  name = "prod-portal-trillium"
  ami                    = "ami-0a590ca28046d073e"
  instance_type          = "t3.medium" # used to set core count below
  key_name = "Trillium"
  availability_zone      = element(module.prod_vpc.azs, 0)
  subnet_id              = element(module.prod_vpc.private_subnets, 0)
  vpc_security_group_ids = [module.prod_portal_security_group.security_group_id]
  create_eip             = false
  disable_api_stop       = false
  create_iam_instance_profile = true
  metadata_options = {
    http_tokens = "required"
  }
  iam_role_description        = "IAM role for EC2 instance"
  iam_role_policies = {
    AdministratorAccess = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
    CloudWatchFullAccess =  "arn:aws:iam::aws:policy/CloudWatchFullAccess"
    SecretsManagerReadWrite =  "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  }

  # only one of these can be enabled at a time
  hibernation = true
  associate_public_ip_address = false
  instance_initiated_shutdown_behavior = "stop"
  cpu_credits = "unlimited"
  monitoring = true
  user_data_replace_on_change = false
  disable_api_termination = true
  enable_volume_tags = false
  root_block_device = [
    {
      encrypted   = true
      kms_key_id  = module.prod_kms.key_arn
      volume_type = "gp3"
      throughput  = 200
      volume_size = 50
      tags = local.tags
    },
  ]

  ebs_block_device = [
    {
      device_name = "/dev/sdf"
      volume_type = "gp3"
      volume_size = 50
      throughput  = 200
      encrypted   = true
      kms_key_id  = module.prod_kms.key_arn
      tags = local.tags
    }
  ]
  tags = local.tags
}


###########################################
############### Window Jump #############
module "jump_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"
  name        = "prod-jump-Security-group"
  description = "Security group for App usage with EC2 instance"
  vpc_id      = module.prod_vpc.vpc_id
  egress_rules        = ["all-all"]
  ingress_with_cidr_blocks = [
    {
      from_port   = 3389
      to_port     = 3389
      protocol    = "tcp"
      description = "User-ISP IPs"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
  tags = local.tags
}

module "prod_jump_ec2-instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "5.7.1"
  name = "prod-jump-trillium"
  ami                    = "ami-0e495ad14fa8f74b5"
  instance_type          = "t3.medium" # used to set core count below
  key_name = "Trillium"
  availability_zone      = element(module.prod_vpc.azs, 0)
  subnet_id              = element(module.prod_vpc.public_subnets, 0)
  vpc_security_group_ids = [module.jump_security_group.security_group_id]
  create_eip             = true
  metadata_options = {
    http_tokens = "required"
  }
  disable_api_stop       = false
  create_iam_instance_profile = true
  disable_api_termination = true
  iam_role_description        = "IAM role for EC2 instance"
  iam_role_policies = {
    AdministratorAccess = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
    CloudWatchFullAccess =  "arn:aws:iam::aws:policy/CloudWatchFullAccess"
    SecretsManagerReadWrite =  "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  } 

  # only one of these can be enabled at a time
  hibernation = true
  user_data_replace_on_change = false
  enable_volume_tags = false
  root_block_device = [
    {
      encrypted   = true
      kms_key_id  = module.prod_kms.key_arn
      tags = local.tags
    },
  ]
  tags = local.tags
}


################  RDS App Server ##################
module "prod_db_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"
  name        = "prod-db-app"
  description = "MySQL app security group"
  vpc_id      = module.prod_vpc.vpc_id
  egress_rules        = ["all-all"]
  # ingress_with_cidr_blocks = [
  #   {
  #     from_port   = 3306
  #     to_port     = 3306
  #     protocol    = "tcp"
  #     description = "Access from VPC"
  #     cidr_blocks = "10.0.0.0/16"
  #   },
  # ]
  ingress_with_source_security_group_id = [
    {
      from_port                = 3306
      to_port                  = 3306
      protocol                 = "tcp"
      description              = "jump sg"
      source_security_group_id = module.jump_security_group.security_group_id
    },
    {
      from_port                = 3306
      to_port                  = 3306
      protocol                 = "tcp"
      description              = "portal sg"
      source_security_group_id = module.prod_portal_security_group.security_group_id
    },
    {
      from_port                = 3306
      to_port                  = 3306
      protocol                 = "tcp"
      description              = "api sg"
      source_security_group_id = module.prod_security_group.security_group_id
    },
  ]
  tags = local.tags
}

module "prod_rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.10.0"
  identifier = "app-prod-db-trillium"
  engine               = "mysql"
  engine_version       = "8.0"
  family               = "mysql8.0" # DB parameter group
  major_engine_version = "8.0"      # DB option group
  instance_class       = "db.t4g.medium"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type = "gp2"
  deletion_protection = true

  db_name  = "appproddb"
  username = "admin"
  port     = 3306
  kms_key_id = module.prod_kms.key_arn

  multi_az               = false
  db_subnet_group_name   = module.prod_vpc.database_subnet_group
  vpc_security_group_ids = [module.prod_db_security_group.security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["general"]
  create_cloudwatch_log_group     = true

  skip_final_snapshot = true
  performance_insights_enabled          = false
  create_monitoring_role                = true
  monitoring_interval                   = 60

  parameters = [
    {
      name  = "character_set_client"
      value = "utf8mb4"
    },
    {
      name  = "character_set_server"
      value = "utf8mb4"
    }
  ]

  tags = local.tags
  db_instance_tags = {
    "Sensitive" = "high"
  }
  db_option_group_tags = {
    "Sensitive" = "low"
  }
  db_parameter_group_tags = {
    "Sensitive" = "low"
  }
  db_subnet_group_tags = {
    "Sensitive" = "high"
  }
  cloudwatch_log_group_tags = {
    "Sensitive" = "high"
  }
}

module "alb_log_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket_prefix = "app-prod-alb-logs-trillium"
  acl           = "log-delivery-write"

  # For example only
  force_destroy = true

  control_object_ownership = true
  object_ownership         = "ObjectWriter"

  attach_elb_log_delivery_policy = true # Required for ALB logs
  attach_lb_log_delivery_policy  = true # Required for ALB/NLB logs
  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true
  tags = local.tags
}

module "files_bucket_prod_app" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"
  bucket = "app-prod-trillium-files"
  control_object_ownership = true
  object_ownership         = "ObjectWriter"

  grant = [{
    type       = "CanonicalUser"
    permission = "FULL_CONTROL"
    id         = data.aws_canonical_user_id.current.id
    }, {
    type       = "CanonicalUser"
    permission = "FULL_CONTROL"
    id         = data.aws_cloudfront_log_delivery_canonical_user_id.cloudfront.id
  }]
  force_destroy = true
}

 ####################################################
 ####################### AWS ALB ##################

module "prod_alb" {
  source  = "terraform-aws-modules/alb/aws"
  # version = "2.4.0"
  name    = "app-prod-alb-trillium"
  vpc_id  = module.prod_vpc.vpc_id
  subnets = module.prod_vpc.public_subnets

  enable_deletion_protection = true

  # Security Group
  security_group_ingress_rules = {
    all_https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      description = "HTTPS web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  access_logs = {
    bucket = module.alb_log_bucket.s3_bucket_id
    prefix = "access-logs-prod"
  }

  connection_logs = {
    bucket  = module.alb_log_bucket.s3_bucket_id
    enabled = true
    prefix  = "connection-logs-prod"
  }

  listeners = {
    ex-https = {
      port                        = 443
      protocol                    = "HTTPS"
      ssl_policy                  = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
      certificate_arn             = "arn:aws:acm:ca-central-1:710271920634:certificate/feba2469-50ba-4db3-904c-821a5c34009d"

      forward = {
        target_group_key = "prod-app-tg"
      }

      rules = {
        forward-host-portal-app = {
          priority = 110
          actions = [{
            type               = "forward"
            target_group_key   = "prod-portal-app-tg"
          }]
          conditions = [{
            host_header = {
              values = ["portal.trilliuminnovation.com"]
            },
          }]
        }
        forward-host-header-admin-portal = {
          priority = 150
          actions = [{
            type               = "forward"
            target_group_key   = "prod-admin-app-tg"

          }]
          conditions = [{
            host_header = {
              values = ["admin.trilliuminnovation.com"]
            },
          }]
        }

        forward-host-header-api-portal = {
          priority = 250
          actions = [{
            type               = "forward"
            target_group_key   = "prod-app-tg"

          }]
          conditions = [{
            host_header = {
              values = ["api.trilliuminnovation.com"]
            },
          }]
        }
	
        forward-host-header-api-admin-portal = {
          priority = 120
          actions = [{
            type               = "forward"
            target_group_key   = "prod-admin-api-app-tg"
          }]
          conditions = [{
            host_header = {
              values = ["api-admin.trilliuminnovation.com"]
            },
          }]
        }
        
        forward-host-header-patient-portal = {
          priority = 130
          actions = [{
            type               = "forward"
            target_group_key   = "prod-patient-portal-app-tg"

          }]
          conditions = [{
            host_header = {
              values = ["portal.trilliuminnovation.com"]
            },
          }]
        }

        forward-host-header-mcedt-portal = {
          priority = 190
          actions = [{
            type               = "forward"
            target_group_key   = "prod-mcedt-app-tg"

          }]
          conditions = [{
            host_header = {
              values = ["mcedt.trilliuminnovation.com"]
            },
          }]
        }

        forward-host-header-ris-portal = {
          priority = 290
          actions = [{
            type               = "forward"
            target_group_key   = "prod-ris-portal-app-tg"

          }]
          conditions = [{
            host_header = {
              values = ["ris.trilliuminnovation.com"]
            },
          }]
        }

        forward-host-header-support-portal = {
          priority = 140
          actions = [{
            type               = "forward"
            target_group_key   = "prod-support-portal-app-tg"

          }]
          conditions = [{
            host_header = {
              values = ["support.trilliuminnovation.com"]
            },
          }]
        }

        # ex-redirect = {
        #   priority = 200
        #   actions = [{
        #     type        = "redirect"
        #     status_code = "HTTP_301"
        #     path        = "/public/index.html/api/v1/login"
        #     protocol    = "HTTPS"
        #     port        = "443"
        #   }]
        #   conditions = [{
        #     host_header = {
        #       values = ["ti-api.trilliuminnovation.com"]
        #     },
        #     path_pattern = {
        #       values = ["/"]
        #     }
        #   }]
        # }
      }
    }
  }

  target_groups = {
    prod-app-tg = {
      name = "app-prod-tg"
      protocol                          = "HTTP"
      port                              = 8082
      target_type                       = "instance"
      deregistration_delay              = 10
      load_balancing_algorithm_type     = "round_robin"
      load_balancing_cross_zone_enabled = true

      target_group_health = {
        dns_failover = {
          minimum_healthy_targets_count = 2
        }
        unhealthy_state_routing = {
          minimum_healthy_targets_percentage = 50
        }
      }

      health_check = {
        enabled             = true
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 5
        protocol            = "HTTP"
        matcher             = "404"
      }

      protocol_version = "HTTP1"
      target_id        = module.prod_app_ec2-instance.id
      port             = 8082
      tags = local.tags
    },
    prod-portal-app-tg = {
      name = "portal-app1-prod-tg"
      protocol                          = "HTTP"
      port                              = 8084
      target_type                       = "instance"
      deregistration_delay              = 10
      load_balancing_algorithm_type     = "round_robin"
      load_balancing_cross_zone_enabled = true

      target_group_health = {
        dns_failover = {
          minimum_healthy_targets_count = 2
        }
        unhealthy_state_routing = {
          minimum_healthy_targets_percentage = 50
        }
      }

      health_check = {
        enabled             = true
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 5
        protocol            = "HTTP"
        matcher             = "200"
      }

      protocol_version = "HTTP1"
      target_id        = module.prod_portal_ec2-instance.id
      port             = 8084
      tags = local.tags
    },
    prod-admin-app-tg = {
      name = "admin-app-prod-tg"
      protocol                          = "HTTP"
      port                              = 8080
      target_type                       = "instance"
      deregistration_delay              = 10
      load_balancing_algorithm_type     = "round_robin"
      load_balancing_cross_zone_enabled = true

      target_group_health = {
        dns_failover = {
          minimum_healthy_targets_count = 2
        }
        unhealthy_state_routing = {
          minimum_healthy_targets_percentage = 50
        }
      }

      health_check = {
        enabled             = true
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 5
        protocol            = "HTTP"
        matcher             = "200"
      }

      protocol_version = "HTTP1"
      target_id        = module.prod_portal_ec2-instance.id
      port             = 8080
      tags = local.tags
    },
    prod-admin-api-app-tg = {
      name = "admin-api-prod-tg"
      protocol                          = "HTTP"
      port                              = 8083
      target_type                       = "instance"
      deregistration_delay              = 10
      load_balancing_algorithm_type     = "round_robin"
      load_balancing_cross_zone_enabled = true

      target_group_health = {
        dns_failover = {
          minimum_healthy_targets_count = 2
        }
        unhealthy_state_routing = {
          minimum_healthy_targets_percentage = 50
        }
      }

      health_check = {
        enabled             = true
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 5
        protocol            = "HTTP"
        matcher             = "200"
      }

      protocol_version = "HTTP1"
      target_id        = module.prod_app_ec2-instance.id
      port             = 8083
      tags = local.tags
    },
    prod-patient-portal-app-tg = {
      name = "patient-portal-app-prod-tg"
      protocol                          = "HTTP"
      port                              = 8084
      target_type                       = "instance"
      deregistration_delay              = 10
      load_balancing_algorithm_type     = "round_robin"
      load_balancing_cross_zone_enabled = true

      target_group_health = {
        dns_failover = {
          minimum_healthy_targets_count = 2
        }
        unhealthy_state_routing = {
          minimum_healthy_targets_percentage = 50
        }
      }

      health_check = {
        enabled             = true
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 5
        protocol            = "HTTP"
        matcher             = "200"
      }

      protocol_version = "HTTP1"
      target_id        = module.prod_portal_ec2-instance.id
      port             = 8084
      tags = local.tags
    },
    prod-support-portal-app-tg = {
      name = "prod-support-portal-app"
      protocol                          = "HTTP"
      port                              = 8085
      target_type                       = "instance"
      deregistration_delay              = 10
      load_balancing_algorithm_type     = "round_robin"
      load_balancing_cross_zone_enabled = true

      target_group_health = {
        dns_failover = {
          minimum_healthy_targets_count = 2
        }
        unhealthy_state_routing = {
          minimum_healthy_targets_percentage = 50
        }
      }

      health_check = {
        enabled             = true
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 5
        protocol            = "HTTP"
        matcher             = "200"
      }

      protocol_version = "HTTP1"
      target_id        = module.prod_portal_ec2-instance.id
      port             = 8085
      tags = local.tags
    },
    prod-mcedt-app-tg = {
      name = "prod-mcedt1-app"
      protocol                          = "HTTP"
      port                              = 8086
      target_type                       = "instance"
      deregistration_delay              = 10
      load_balancing_algorithm_type     = "round_robin"
      load_balancing_cross_zone_enabled = true

      target_group_health = {
        dns_failover = {
          minimum_healthy_targets_count = 2
        }
        unhealthy_state_routing = {
          minimum_healthy_targets_percentage = 50
        }
      }

      health_check = {
        enabled             = true
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 5
        protocol            = "HTTP"
        matcher             = "200"
      }

      protocol_version = "HTTP1"
      target_id        = module.prod_app_ec2-instance.id
      port             = 8086
      tags = local.tags
    },

    prod-ris-portal-app-tg = {
      name = "prod-ris-app"
      protocol                          = "HTTP"
      port                              = 8081
      target_type                       = "instance"
      deregistration_delay              = 10
      load_balancing_algorithm_type     = "round_robin"
      load_balancing_cross_zone_enabled = true

      target_group_health = {
        dns_failover = {
          minimum_healthy_targets_count = 2
        }
        unhealthy_state_routing = {
          minimum_healthy_targets_percentage = 50
        }
      }

      health_check = {
        enabled             = true
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 5
        protocol            = "HTTP"
        matcher             = "200"
      }

      protocol_version = "HTTP1"
      target_id        = module.prod_portal_ec2-instance.id
      port             = 8081
      tags = local.tags
    },
  }

  additional_target_group_attachments = {
    prod-app-alb-other = {
      target_group_key = "prod-app-tg"
      target_type      = "instance"
      target_id        = module.prod_app_ec2-instance.id
      port             = "8082"
    },
    prod-portal-app-alb-other = {
      target_group_key = "prod-portal-app-tg"
      target_type      = "instance"
      target_id        = module.prod_portal_ec2-instance.id
      port             = "8084"
    },
    prod-admin-app-alb-other = {
      target_group_key = "prod-admin-app-tg"
      target_type      = "instance"
      target_id        = module.prod_portal_ec2-instance.id
      port             = "8080"
    },
    prod-app-mcedt-alb-other = {
      target_group_key = "prod-mcedt-app-tg"
      target_type      = "instance"
      target_id        = module.prod_app_ec2-instance.id
      port             = "8086"
    },
    prod-admin-app-alb-other = {
      target_group_key = "prod-admin-api-app-tg"
      target_type      = "instance"
      target_id        = module.prod_app_ec2-instance.id
      port             = "8083"
    },
    prod-admin-app-alb-other = {
      target_group_key = "prod-patient-portal-app-tg"
      target_type      = "instance"
      target_id        = module.prod_portal_ec2-instance.id
      port             = "8084"
    },
    prod-portal-ris-alb-other = {
      target_group_key = "prod-ris-portal-app-tg"
      target_type      = "instance"
      target_id        = module.prod_portal_ec2-instance.id
      port             = "8081"
    },
    prod-admin-app-alb-other = {
      target_group_key = "prod-support-portal-app-tg"
      target_type      = "instance"
      target_id        = module.prod_portal_ec2-instance.id
      port             = "8085"
    },
  }
  tags = local.tags
}