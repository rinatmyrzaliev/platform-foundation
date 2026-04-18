# GitHub Actions OIDC provider. As of mid-2023, AWS no longer requires a
# thumbprint because GitHub's JWKS is trusted by IAM's native TLS validation,
# so we omit thumbprint_list (the aws provider accepts an empty list).
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = []

  tags = local.common_tags
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Any repo owned by ${var.github_username}, any branch/tag/environment.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_username}/platform-foundation:*",
        "repo:${var.github_username}/platform-golden-path:*",
        "repo:${var.github_username}/platform-observability:*",
        "repo:${var.github_username}/platform-delivery:*",
        "repo:${var.github_username}/platform-autoscaling:*",
        "repo:${var.github_username}/platform-alert-copilot:*",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "github-actions-platform"
  description        = "Assumed by GitHub Actions workflows in repos owned by ${var.github_username}."
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

data "aws_iam_policy_document" "github_actions_eks" {
  statement {
    effect    = "Allow"
    actions   = ["eks:DescribeCluster", "eks:ListClusters"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "github_actions_eks" {
  name        = "github-actions-platform-eks-describe"
  description = "Allow GitHub Actions to discover EKS clusters (needed for aws eks update-kubeconfig)."
  policy      = data.aws_iam_policy_document.github_actions_eks.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "github_actions_eks" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_eks.arn
}
