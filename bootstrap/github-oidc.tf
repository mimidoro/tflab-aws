# GitHub Actions -> AWS with OpenID Connect: short-lived credentials, no stored access keys.
# Trust is pinned to ONE repo and ONE GitHub environment ("lab"), which is itself restricted
# to the main branch (bootstrap.sh step B3).

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:environment:${var.github_environment}"]
    }
  }
}

resource "aws_iam_role" "github" {
  name                 = "tflab-github-actions"
  description          = "Deploy/destroy role for ${var.github_repo} (environment ${var.github_environment})"
  assume_role_policy   = data.aws_iam_policy_document.github_trust.json
  max_session_duration = 7200 # EKS + cross-region RDS replica can take ~35 min to create
}

# Broad service access WITHOUT IAM admin...
resource "aws_iam_role_policy_attachment" "github_poweruser" {
  role       = aws_iam_role.github.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# ...plus IAM limited to tflab-* names, with guard rails against privilege escalation.
data "aws_iam_policy_document" "github_iam" {
  statement {
    sid = "ManageLabIamOnly"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
      "iam:TagRole", "iam:UntagRole",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
      "iam:TagPolicy", "iam:UntagPolicy",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile", "iam:UntagInstanceProfile",
      "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/tflab-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/tflab-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/tflab-*",
    ]
  }

  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
  }

  # Guard rail 1: the role can never change itself, its permissions, or the cost kill switch.
  statement {
    sid    = "DenySelfAndGuardModification"
    effect = "Deny"
    # Writes only - reads stay allowed (aws_iam_session_context calls iam:GetRole on itself).
    actions = [
      "iam:Create*", "iam:Delete*", "iam:Update*", "iam:Put*",
      "iam:Attach*", "iam:Detach*", "iam:Tag*", "iam:Untag*",
      "iam:SetDefaultPolicyVersion", "iam:PassRole",
    ]
    resources = [
      aws_iam_role.github.arn,
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/tflab-budget-action",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/tflab-deny-create",
    ]
  }

  # Guard rail 2: no admin-equivalent managed policies on any lab role.
  statement {
    sid       = "DenyAdminPolicies"
    effect    = "Deny"
    actions   = ["iam:AttachRolePolicy"]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "iam:PolicyARN"
      values = [
        "arn:aws:iam::aws:policy/AdministratorAccess",
        "arn:aws:iam::aws:policy/IAMFullAccess",
        "arn:aws:iam::aws:policy/PowerUserAccess",
      ]
    }
  }
}

resource "aws_iam_role_policy" "github_iam" {
  name   = "tflab-scoped-iam"
  role   = aws_iam_role.github.id
  policy = data.aws_iam_policy_document.github_iam.json
}
