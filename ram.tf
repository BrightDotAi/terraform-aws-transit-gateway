locals {
  ram_resource_share_enabled = module.this.enabled && var.ram_resource_share_enabled

  ram_principals_provided = var.ram_principal != null || length(var.ram_principals) > 0
  ram_principals = toset(local.ram_resource_share_enabled ? toset(
    local.ram_principals_provided ? concat(
      var.ram_principal == null ? [] : [var.ram_principal],
      var.ram_principals,
      ) : [
      data.aws_organizations_organization.default[0].arn
    ]
  ) : [])
}

# Resource Access Manager (RAM) share for the Transit Gateway
# https://docs.aws.amazon.com/ram/latest/userguide/what-is.html
resource "aws_ram_resource_share" "default" {
  count                     = local.ram_resource_share_enabled ? 1 : 0
  name                      = module.this.id
  allow_external_principals = var.allow_external_principals
  tags                      = module.this.tags

  dynamic "resource_share_configuration" {
    for_each = var.retain_sharing_on_account_leave_organization ? [1] : []
    content {
      retain_sharing_on_account_leave_organization = true
    }
  }

  lifecycle {
    create_before_destroy = true

    # check {} only warns; precondition fails plan/apply for invalid combos
    precondition {
      condition     = !var.retain_sharing_on_account_leave_organization || var.allow_external_principals
      error_message = "retain_sharing_on_account_leave_organization requires allow_external_principals = true."
    }
  }
}

# Share the Transit Gateway with the Organization if RAM principal was not provided
data "aws_organizations_organization" "default" {
  count = local.ram_resource_share_enabled && !local.ram_principals_provided ? 1 : 0
}

resource "aws_ram_resource_association" "default" {
  count              = local.ram_resource_share_enabled ? 1 : 0
  resource_arn       = try(aws_ec2_transit_gateway.default[0].arn, "")
  resource_share_arn = try(aws_ram_resource_share.default[0].id, "")
}

resource "aws_ram_principal_association" "default" {
  for_each           = local.ram_principals
  principal          = each.value
  resource_share_arn = try(aws_ram_resource_share.default[0].id, "")
}
