variable "name_prefix" {
  description = "Prefix for the intake queue, EventBridge rule, and (cross-account) event bus names."
  type        = string
}

variable "codecommit_repos" {
  description = "CodeCommit repository names whose branch pushes feed the intake. Scoped by name in the event pattern (an ARN list overflows EventBridge's 2048-byte pattern cap past ~25 repos)."
  type        = list(string)

  validation {
    condition     = length(var.codecommit_repos) > 0
    error_message = "The CodeCommit intake requires at least one repository in codecommit_repos."
  }
}

variable "codecommit_account_id" {
  description = "AWS account that owns the CodeCommit repos, when different from this account. Cross-account requires that account to forward its CodeCommit events onto the custom bus this module creates (an EventBridge rule in the repo account targeting the bus ARN). Empty = same-account: the rule listens on the local default bus."
  type        = string
  default     = ""
}
