### Variables
variable "vpc_id" { type = string }
variable "cluster_name" { type = string }
variable "subnet_ids" { type = list(string) }


### Datasources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_vpc_endpoint_service" "guardduty" {
  service_type = "Interface"
  filter {
    name   = "service-name"
    values = ["com.amazonaws.${data.aws_region.current.name}.guardduty-data"]
  }
}
data "aws_eks_cluster" "output" {
  name = var.cluster_name
}
data "aws_eks_addon_version" "latest" {
  addon_name         = "aws-guardduty-agent"
  kubernetes_version = data.aws_eks_cluster.output.version
  most_recent        = true
}


### VPC Endpoint with attached IAM Policy and SecurityGroup: 
### Allow agents to communicate with GuardDuty API privately
resource "aws_vpc_endpoint" "eks_vpc_guardduty" {
  vpc_id            = var.vpc_id

  service_name      = data.aws_vpc_endpoint_service.guardduty.service_name
  vpc_endpoint_type = "Interface"

  policy = data.aws_iam_policy_document.eks_vpc_guardduty.json

  security_group_ids  = [aws_security_group.eks_vpc_endpoint_guardduty.id]
  subnet_ids          = var.subnet_ids
  private_dns_enabled = true
}

resource "aws_security_group" "eks_vpc_endpoint_guardduty" {
  name_prefix = "${var.cluster_name}-vpc-endpoint-guardduty-sg-"
  description = "Security Group used by VPC Endpoints."
  vpc_id      =  var.vpc_id

  tags = {
    "Name"             = "${var.cluster_name}-vpc-endpoint-guardduty-sg-"
    "GuardDutyManaged" = "false"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "eks_vpc_guardduty_ingress" {
  security_group_id = aws_security_group.eks_vpc_endpoint_guardduty.id
  description       = "Ingress for port 443."

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  ip_protocol = "tcp"
  to_port     = 443
}

data "aws_iam_policy_document" "eks_vpc_guardduty" {
  statement {
    actions = ["*"]

    effect = "Allow"

    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }

  statement {
    actions = ["*"]

    effect = "Deny"

    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalAccount"

      values = [data.aws_caller_identity.current.account_id]
    }
  }
}


resource "aws_eks_addon" "guardduty" {

  cluster_name      = var.cluster_name
  addon_name        = "aws-guardduty-agent"
  addon_version     = data.aws_eks_addon_version.latest.version

  preserve = true

  tags = {
    "eks_addon" = "guardduty"
  }
}