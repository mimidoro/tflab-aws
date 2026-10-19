output "github_role_arn" {
  value = aws_iam_role.github.arn
}

output "ecr_repositories" {
  value = { for k, r in aws_ecr_repository.app : k => r.repository_url }
}

output "ops_topic_arn" {
  value = aws_sns_topic.ops.arn
}
