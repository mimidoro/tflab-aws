# Images live in the bootstrap layer (cents per month) so teardown doesn't force rebuilds.
# Pushed to Sydney, replicated to Melbourne so each cluster pulls from its own region.

resource "aws_ecr_repository" "app" {
  for_each             = toset(["tflab/web", "tflab/api"])
  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 10 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_replication_configuration" "to_melbourne" {
  replication_configuration {
    rule {
      destination {
        region      = var.replica_region
        registry_id = data.aws_caller_identity.current.account_id
      }
      repository_filter {
        filter      = "tflab/"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}
