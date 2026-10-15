variable "repos" { type = list(string) }

resource "aws_ecr_repository" "r" {
  for_each             = toset(var.repos)
  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_lifecycle_policy" "keep" {
  for_each   = aws_ecr_repository.r
  repository = each.value.name
  policy     = jsonencode({ rules = [{ rulePriority = 1, description = "keep last 20", selection = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }, action = { type = "expire" } }] })
}

output "urls" { value = { for k, v in aws_ecr_repository.r : k => v.repository_url } }
