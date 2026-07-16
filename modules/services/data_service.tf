# --- data-service: single-writer SQLite store on EC2 + persistent EBS ---
#
# SQLite requires a single writer on a real block device, so this service runs
# EC2 launch type (Fargate EBS is task-lifecycle-bound; EFS is an
# SQLite-over-NFS anti-pattern) on its own dedicated one-instance cluster. The
# data volume is AZ-pinned to var.data_service_subnet_id and survives instance
# replacement via the user-data attach flow.

# --- Persistent data volume ---

resource "aws_ebs_volume" "data_service" {
  availability_zone = data.aws_subnet.data_service.availability_zone
  size              = var.data_service_data_volume_gib
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "${var.name_prefix}-data-service-data"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# --- Security groups ---

resource "aws_security_group" "data_service_task" {
  name_prefix = "${var.name_prefix}-data-service-task-"
  description = "TokenIQ data-service task"
  vpc_id      = var.vpc_id

  ingress {
    description = "data-service HTTPS from inside the VPC"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "data_service_instance" {
  name_prefix = "${var.name_prefix}-data-service-instance-"
  description = "TokenIQ data-service container instance (egress only; tasks use awsvpc ENIs)"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Instance role (ECS agent + volume attach) ---

resource "aws_iam_role" "data_service_instance" {
  name_prefix = "${var.name_prefix}-ds-instance-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "data_service_instance_ecs" {
  role       = aws_iam_role.data_service_instance.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "data_service_instance_ssm" {
  role       = aws_iam_role.data_service_instance.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "data_service_attach_volume" {
  name = "attach-data-volume"
  role = aws_iam_role.data_service_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ec2:DescribeVolumes"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "ec2:AttachVolume"
        Resource = [
          "arn:${local.partition}:ec2:${local.region}:${local.account_id}:volume/${aws_ebs_volume.data_service.id}",
          "arn:${local.partition}:ec2:${local.region}:${local.account_id}:instance/*",
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "data_service" {
  name_prefix = "${var.name_prefix}-ds-"
  role        = aws_iam_role.data_service_instance.name
}

# --- Execution + task roles ---

resource "aws_iam_role" "data_service_execution" {
  name_prefix = "${var.name_prefix}-ds-exec-"

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

resource "aws_iam_role_policy_attachment" "data_service_execution" {
  role       = aws_iam_role.data_service_execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "data_service_execution_secrets" {
  name = "secrets-read"
  role = aws_iam_role.data_service_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        Resource = [
          var.data_service_auth_token_secret_arn,
          var.data_service_tls_cert_secret_arn,
          var.data_service_tls_key_secret_arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${local.region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "data_service_task" {
  name_prefix = "${var.name_prefix}-ds-task-"

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

resource "aws_iam_role_policy" "data_service_store_apply" {
  name = "store-apply-consume"
  role = aws_iam_role.data_service_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
        Resource = var.store_apply_queue_arn
      }
    ]
  })
}

# --- Dedicated EC2 cluster + capacity ---

resource "aws_ecs_cluster" "data_service" {
  name = "${var.name_prefix}-data-service"
}

resource "aws_launch_template" "data_service" {
  name_prefix   = "${var.name_prefix}-data-service-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.data_service_instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.data_service.arn
  }

  vpc_security_group_ids = [aws_security_group.data_service_instance.id]

  metadata_options {
    http_tokens = "required"
  }

  user_data = base64encode(templatefile("${path.module}/data_service_user_data.sh.tpl", {
    cluster_name = aws_ecs_cluster.data_service.name
    region       = local.region
    volume_id    = aws_ebs_volume.data_service.id
    mount_dir    = local.data_service_mount_dir
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name_prefix}-data-service"
    }
  }
}

resource "aws_autoscaling_group" "data_service" {
  name_prefix = "${var.name_prefix}-data-service-"

  # LOAD-BEARING: exactly one instance, always. The SQLite data volume can
  # only attach to one host, and two hosts writing the same WAL corrupts it.
  # A deploy replaces the TASK on the same host (see the ECS service's
  # 100/200 deployment settings), not the instance.
  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  vpc_zone_identifier = [var.data_service_subnet_id]

  launch_template {
    id      = aws_launch_template.data_service.id
    version = aws_launch_template.data_service.latest_version
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-data-service"
    propagate_at_launch = true
  }
}

# --- Task definition + service ---

resource "aws_cloudwatch_log_group" "data_service" {
  name              = "/ecs/${var.name_prefix}-data-service"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_task_definition" "data_service" {
  family                   = "${var.name_prefix}-data-service"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.data_service_execution.arn
  task_role_arn            = aws_iam_role.data_service_task.arn

  volume {
    name      = "data-service-data"
    host_path = local.data_service_mount_dir
  }

  container_definitions = jsonencode([
    {
      name      = "data-service"
      image     = var.data_service_image
      essential = true
      memory    = var.data_service_container_memory_mib

      # The image is distroless: no shell, so the healthcheck execs the
      # binary's built-in probe directly.
      healthCheck = {
        command     = ["CMD", "/data-service", "-healthcheck"]
        interval    = 10
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "data-service-data"
          containerPath = local.data_service_mount_dir
        }
      ]

      environment = [
        { name = "TOKENIQ_TENANT_ID", value = var.tenant_id },
        { name = "TOKENIQ_STORE_APPLY_QUEUE", value = var.store_apply_queue_url },
        { name = "TOKENIQ_SQLITE_PATH", value = local.data_service_sqlite_path },
        { name = "TOKENIQ_DATA_SERVICE_ADDR", value = ":8080" },
        { name = "TOKENIQ_AUTH_ENABLED", value = "true" },
        { name = "TOKENIQ_TLS_ENABLED", value = "true" },
      ]

      secrets = [
        { name = "TOKENIQ_DATA_SERVICE_AUTH_TOKEN", valueFrom = var.data_service_auth_token_secret_arn },
        { name = "TOKENIQ_DATA_SERVICE_TLS_CERT_PEM", valueFrom = var.data_service_tls_cert_secret_arn },
        { name = "TOKENIQ_DATA_SERVICE_TLS_KEY_PEM", valueFrom = var.data_service_tls_key_secret_arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.data_service.name
          awslogs-region        = local.region
          awslogs-stream-prefix = "data-service"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "data_service" {
  name            = "${var.name_prefix}-data-service"
  cluster         = aws_ecs_cluster.data_service.id
  task_definition = aws_ecs_task_definition.data_service.arn
  desired_count   = 1
  launch_type     = "EC2"

  # Same-host overlap deploy: with one instance and min-healthy 100% /
  # max 200%, ECS starts the NEW task beside the old one on the same host
  # (the instance type must fit two tasks + two ENIs — see
  # var.data_service_instance_type), waits for its healthcheck, then stops
  # the old task. Never a window with zero healthy tasks, and never two
  # HOSTS touching the volume. Do not lower max to 100 (deploys would stop
  # the only task first) and do not raise the ASG above one instance.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets         = [var.data_service_subnet_id]
    security_groups = [aws_security_group.data_service_task.id]
  }

  service_registries {
    registry_arn = var.data_service_service_discovery_arn
  }

  depends_on = [aws_autoscaling_group.data_service]
}
