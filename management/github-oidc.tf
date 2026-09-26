resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]
}

data "aws_iam_policy_document" "github_actions_ecr_trust" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:jelicki-jovan/Incode-conduit-realworld-example-app:ref:refs/heads/main"
      ]
    }
  }
}

data "aws_iam_policy_document" "github_actions_ecr_push" {
  statement {
    sid = "EcrLogin"

    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = [
      "*" # GetAuthorizationToken doesn't support resource-level permissions
    ]
  }

  statement {
    sid = "EcrPushPull"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeImages",
    ]
    resources = [for repo in module.ecr_prod : repo.repository_arn]
  }
}

resource "aws_iam_role" "github_actions_ecr" {
  name               = "hw-github-actions-ecr"
  description        = "GitHub Actions (app repo, main branch) pushes images to ECR"
  assume_role_policy = data.aws_iam_policy_document.github_actions_ecr_trust.json

  max_session_duration = 3600
}

resource "aws_iam_role_policy" "github_actions_ecr_push" {
  name   = "hw-github-actions-ecr-push"
  role   = aws_iam_role.github_actions_ecr.id
  policy = data.aws_iam_policy_document.github_actions_ecr_push.json
}
