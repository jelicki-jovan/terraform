{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Remove Untagged images older than 1 day",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 1
      },
      "action": {
        "type": "expire"
      }
    }%{ if only_untagged == false },
    {
      "action": {
        "type": "expire"
      },
      "selection": {
        "countType": "imageCountMoreThan",
        "countNumber": ${keep_amount_v},
        "tagStatus": "tagged",
        "tagPrefixList": [
          "v"
        ]
      },
      "description": "Keep only last ${keep_amount_v} release images ('v' - prefix)",
      "rulePriority": 2
    },
    {
      "action": {
        "type": "expire"
      },
      "selection": {
        "countType": "imageCountMoreThan",
        "countNumber": ${keep_amount},
        "tagStatus": "any"
      },
      "description": "Keep only last ${keep_amount} images tagged with git SHA",
      "rulePriority": 3
    }%{ endif }
  ]
}
