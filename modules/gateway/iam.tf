# Execution role — the ECS agent uses this to pull images, read the
# injected secrets, and write logs.
resource "aws_iam_role" "execution" {
  name = "${var.name_prefix}-gateway-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

locals {
  # The Tier 3 bundle tenant key is normally the vendor's own secret, read
  # cross-account (and possibly cross-region) by full ARN and encrypted
  # under the vendor's CMK. Decrypt then goes through Secrets Manager in the
  # SECRET's region, which need not be this deployment's region.
  bundle_key_kms_via_services = distinct([
    "secretsmanager.${data.aws_region.current.name}.amazonaws.com",
    "secretsmanager.${try(split(":", var.bundle_tenant_key_secret_arn)[3], data.aws_region.current.name)}.amazonaws.com",
  ])
}

# The managed policy does not include Secrets Manager; grant read on
# exactly the secrets injected as container secrets. The Tier 3 bundle
# tenant key is granted whenever supplied even though its container-secret
# entry rides with it — a distributor cutover is then a pure env change.
resource "aws_iam_role_policy" "execution_secrets" {
  name = "${var.name_prefix}-gateway-secrets-read"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = ["secretsmanager:GetSecretValue"]
          Resource = concat(
            [
              var.telemetry_tenant_key_secret_arn,
              aws_secretsmanager_secret.admin_token.arn,
            ],
            var.bundle_tenant_key_secret_arn != "" ? [var.bundle_tenant_key_secret_arn] : [],
            values(var.extra_secrets),
          )
        }
      ],
      # A customer-managed CMK (the vendor's, for the cross-account bundle
      # tenant key) needs an explicit identity-side decrypt grant; ECS can't
      # inject the secret without it. Module-owned secrets use the
      # AWS-managed key and need none.
      var.bundle_tenant_key_secret_arn != "" ? [
        {
          Effect   = "Allow"
          Action   = "kms:Decrypt"
          Resource = "*"
          Condition = {
            StringEquals = {
              "kms:ViaService" = local.bundle_key_kms_via_services
            }
          }
        }
      ] : [],
    )
  })
}

# Task role — used by the running gateway container.
resource "aws_iam_role" "task" {
  name = "${var.name_prefix}-gateway-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# Bedrock serving. The Bedrock adapter authenticates with the AWS
# credential chain rather than an API key, so this task role IS its
# credential. Scoped to the specific models the bundle routes to; entries
# may be bare on-demand foundation-model IDs or full ARNs (inference
# profiles, provisioned throughput).
resource "aws_iam_role_policy" "task_bedrock_invoke" {
  count = var.bedrock_enabled ? 1 : 0

  name = "${var.name_prefix}-gateway-bedrock-invoke"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
        ]
        Resource = [
          for model in var.bedrock_served_models :
          startswith(model, "arn:") ? model : "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${model}"
        ]
      }
    ]
  })
}
