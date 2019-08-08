# Pin the `aws` provider
# https://www.terraform.io/docs/configuration/providers.html
# Any non-beta version >= 2.12.0 and < 2.13.0, e.g. 2.12.X
module "default_label" {
  source     = "git::https://github.com/cloudposse/terraform-terraform-label.git?ref=tags/0.2.1"
  name       = var.name
  namespace  = var.namespace
  stage      = var.stage
  attributes = var.attributes
}

module "ecr" {
  enabled    = var.codepipeline_enabled
  source     = "git::https://github.com/cloudposse/terraform-aws-ecr.git?ref=tags/0.7.0"
  name       = var.name
  namespace  = var.namespace
  stage      = var.stage
  attributes = compact(concat(var.attributes, ["ecr"]))
}

resource "aws_cloudwatch_log_group" "app" {
  name = module.default_label.id
  tags = module.default_label.tags
}

module "alb_ingress" {
  source            = "git::https://github.com/wesselvdv/terraform-aws-alb-ingress.git?ref=tags/0.7.0.1"
  name              = var.name
  namespace         = var.namespace
  stage             = var.stage
  attributes        = var.attributes
  vpc_id            = var.vpc_id
  port              = var.container_port
  health_check_path = var.alb_ingress_healthcheck_path

  authenticated_paths   = var.alb_ingress_authenticated_paths
  unauthenticated_paths = var.alb_ingress_unauthenticated_paths
  authenticated_hosts   = var.alb_ingress_authenticated_hosts
  unauthenticated_hosts = var.alb_ingress_unauthenticated_hosts

  authenticated_priority   = var.alb_ingress_listener_authenticated_priority
  unauthenticated_priority = var.alb_ingress_listener_unauthenticated_priority

  unauthenticated_listener_arns       = var.alb_ingress_unauthenticated_listener_arns
  unauthenticated_listener_arns_count = var.alb_ingress_unauthenticated_listener_arns_count
  authenticated_listener_arns         = var.alb_ingress_authenticated_listener_arns
  authenticated_listener_arns_count   = var.alb_ingress_authenticated_listener_arns_count

  authentication_type                        = var.authentication_type
  authentication_cognito_user_pool_arn       = var.authentication_cognito_user_pool_arn
  authentication_cognito_user_pool_client_id = var.authentication_cognito_user_pool_client_id
  authentication_cognito_user_pool_domain    = var.authentication_cognito_user_pool_domain
  authentication_oidc_client_id              = var.authentication_oidc_client_id
  authentication_oidc_client_secret          = var.authentication_oidc_client_secret
  authentication_oidc_issuer                 = var.authentication_oidc_issuer
  authentication_oidc_authorization_endpoint = var.authentication_oidc_authorization_endpoint
  authentication_oidc_token_endpoint         = var.authentication_oidc_token_endpoint
  authentication_oidc_user_info_endpoint     = var.authentication_oidc_user_info_endpoint
}

module "container_definition" {
  source                       = "git::https://github.com/cloudposse/terraform-aws-ecs-container-definition.git?ref=tags/0.9.1"
  container_name               = module.default_label.id
  container_image              = var.container_image
  container_memory             = var.container_memory
  container_memory_reservation = var.container_memory_reservation
  container_cpu                = var.container_cpu
  healthcheck                  = var.healthcheck
  environment                  = var.environment
  port_mappings                = var.port_mappings
  secrets                      = var.secrets

  log_options = {
    "awslogs-region"        = var.aws_logs_region
    "awslogs-group"         = aws_cloudwatch_log_group.app.name
    "awslogs-stream-prefix" = var.name
  }
}

module "ecs_alb_service_task" {
  source                            = "git::https://github.com/wesselvdv/terraform-aws-ecs-alb-service-task.git?ref=tags/0.13.1.1"
  name                              = var.name
  namespace                         = var.namespace
  stage                             = var.stage
  attributes                        = var.attributes
  alb_target_group_arn              = module.alb_ingress.target_group_arn
  container_definition_json         = module.container_definition.json
  container_name                    = module.default_label.id
  desired_count                     = var.desired_count
  health_check_grace_period_seconds = var.health_check_grace_period_seconds
  task_cpu                          = var.container_cpu
  task_memory                       = var.container_memory
  ecs_cluster_arn                   = var.ecs_cluster_arn
  launch_type                       = var.launch_type
  vpc_id                            = var.vpc_id
  security_group_ids                = var.ecs_security_group_ids
  subnet_ids                        = var.ecs_private_subnet_ids
  container_port                    = var.container_port
}

module "autoscaling" {
  enabled               = var.autoscaling_enabled
  source                = "git::https://github.com/cloudposse/terraform-aws-ecs-cloudwatch-autoscaling.git?ref=tags/0.1.0"
  name                  = var.name
  namespace             = var.namespace
  stage                 = var.stage
  attributes            = var.attributes
  service_name          = module.ecs_alb_service_task.service_name
  cluster_name          = var.ecs_cluster_name
  min_capacity          = var.autoscaling_min_capacity
  max_capacity          = var.autoscaling_max_capacity
  scale_down_adjustment = var.autoscaling_scale_down_adjustment
  scale_down_cooldown   = var.autoscaling_scale_down_cooldown
  scale_up_adjustment   = var.autoscaling_scale_up_adjustment
  scale_up_cooldown     = var.autoscaling_scale_up_cooldown
}

locals {
  cpu_utilization_high_alarm_actions    = var.autoscaling_enabled == "true" && var.autoscaling_dimension == "cpu" ? module.autoscaling.scale_up_policy_arn : ""
  cpu_utilization_low_alarm_actions     = var.autoscaling_enabled == "true" && var.autoscaling_dimension == "cpu" ? module.autoscaling.scale_down_policy_arn : ""
  memory_utilization_high_alarm_actions = var.autoscaling_enabled == "true" && var.autoscaling_dimension == "memory" ? module.autoscaling.scale_up_policy_arn : ""
  memory_utilization_low_alarm_actions  = var.autoscaling_enabled == "true" && var.autoscaling_dimension == "memory" ? module.autoscaling.scale_down_policy_arn : ""
}

