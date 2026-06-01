
# Lambda Functions using MUFGIS Lambda Module with Datadog Integration
module "skylight_lambdas" {
  source  = "gitlab.com/MUFGIS/aws/lambda"
  version = "1.1.1"

  for_each = toset(var.lambda_functions_names)

  name    = "${var.project_name}-${var.environment}-lambda-${each.key}"
  handler = var.lambda_handler
  runtime = var.lambda_runtime

  source_zip_path = "${path.module}/lambda_functions/${each.key}.zip"

  vpc_config = {
    security_group_ids = [aws_security_group.lambda_sg.id]
    subnet_ids         = data.aws_subnets.private.ids
  }

  # Datadog integration
  datadog_tracing_enabled = true

  environment_variables = merge({
    # Application environment variables
    STAGE                = var.environment,
    PROJECT              = var.project_name,
    RDS_ENDPOINT         = module.rds.db_endpoint,
    RDS_PORT             = "5432",
    RDS_SSL_CERT_S3_PATH = "s3://${module.ssl_cert_bucket.bucket_name}/${var.rds_ssl_cert_s3_key}",
    RDS_SSL_MODE         = "require",

    # Secrets Manager ARN - applications should read all secrets from this single source
    BACKEND_SECRET_ARN  = aws_secretsmanager_secret.app_backend_secrets.arn,
    FRONTEND_SECRET_ARN = aws_secretsmanager_secret.app_frontend_secrets.arn,

    # Datadog environment variables
    LOG_LEVEL                  = var.lambda_log_level,
    DD_ENHANCED_METRICS        = "true",
    DD_SERVICE                 = "skylight-${var.environment}-${each.key}",
    DD_SERVERLESS_LOGS_ENABLED = "true",
    DD_VERSION                 = var.DD_VERSION,
    DD_ENV                     = var.environment,
    DD_API_KEY_SECRET_ARN      = var.datadog_api_key_secret_arn,
    DD_TRACE_ENABLED           = "true",
    DD_LOGS_INJECTION          = "true"
  }, var.lambda_extra_env != null ? var.lambda_extra_env : {})

  tags = {
    Name        = "${var.project_name}-${var.environment}-lambda-${each.key}"
    Environment = var.environment
    Project     = var.project_name
    Service     = "skylight-${var.environment}-${each.key}"
  }

  # Function configuration
  timeout     = lookup(var.lambda_timeouts, each.key, 15)
  memory_size = lookup(var.lambda_memory_sizes, each.key, 512)

  # IAM policy statements for Lambda functions
  policy_statements = merge({
    # Datadog API key access
    datadog_api_key_statement = {
      sid    = "DatadogApiKeyAccess"
      effect = "Allow"
      resources = [
        var.datadog_api_key_secret_arn
      ]
      actions = ["secretsmanager:GetSecretValue"]
    }

    # Application secrets access
    app_secrets_statement = {
      sid    = "AppSecretsAccess"
      effect = "Allow"
      resources = [
        aws_secretsmanager_secret.app_backend_secrets.arn,
        aws_secretsmanager_secret.app_frontend_secrets.arn
      ]
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
    }

    # S3 access for SSL certificates
    s3_ssl_cert_statement = {
      sid    = "S3SslCertAccess"
      effect = "Allow"
      resources = [
        "arn:aws:s3:::${module.ssl_cert_bucket.bucket_name}",
        "arn:aws:s3:::${module.ssl_cert_bucket.bucket_name}/*"
      ]
      actions = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
    }
    },
    # Add CRM-only S3 access when this module instance is the crm lambda
    each.key == "crm" ? {
      crm_bucket_access = {
        sid    = "CrmS3Access"
        effect = "Allow"
        resources = [
          "arn:aws:s3:::${module.crm_upload_bucket.bucket_name}",
          "arn:aws:s3:::${module.crm_upload_bucket.bucket_name}/*"
        ]
        actions = [
          "s3:GetObject",
          "s3:PutObject"
        ]
      }
    } : {}
  )
}


# Security group for Lambda functions
resource "aws_security_group" "lambda_sg" {
  name        = "${var.project_name}-${var.environment}-lambda-sg"
  description = "Security group for Lambda functions in private subnets"
  vpc_id      = data.aws_vpc.this.id

  # Allow outbound HTTPS traffic to reach AWS services (Secrets Manager, etc.)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound for AWS services"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-lambda-sg"
  }
}


# Batch Job Lambda Functions - Separate functions for different handlers
module "deliverables_hourly" {
  source  = "gitlab.com/MUFGIS/aws/lambda"
  version = "1.1.1"

  name    = "${var.project_name}-${var.environment}-lambda-deliverables-hourly"
  handler = "src/lambda.batchJobOneHandler"
  runtime = var.lambda_runtime

  source_zip_path = "${path.module}/lambda_functions/deliverables.zip"

  vpc_config = {
    security_group_ids = [aws_security_group.lambda_sg.id]
    subnet_ids         = data.aws_subnets.private.ids
  }

  # Datadog integration
  datadog_tracing_enabled = true

  environment_variables = merge({
    # Application environment variables
    STAGE                = var.environment,
    PROJECT              = var.project_name,
    RDS_ENDPOINT         = module.rds.db_endpoint,
    RDS_PORT             = "5432",
    RDS_SSL_CERT_S3_PATH = "s3://${module.ssl_cert_bucket.bucket_name}/${var.rds_ssl_cert_s3_key}",
    RDS_SSL_MODE         = "require",

    # Secrets Manager ARN - applications should read all secrets from this single source
    BACKEND_SECRET_ARN  = aws_secretsmanager_secret.app_backend_secrets.arn,
    FRONTEND_SECRET_ARN = aws_secretsmanager_secret.app_frontend_secrets.arn,

    # Datadog environment variables
    LOG_LEVEL                  = var.lambda_log_level,
    DD_ENHANCED_METRICS        = "true",
    DD_SERVICE                 = "skylight-${var.environment}-deliverables-hourly",
    DD_SERVERLESS_LOGS_ENABLED = "true",
    DD_VERSION                 = var.DD_VERSION,
    DD_ENV                     = var.environment,
    DD_API_KEY_SECRET_ARN      = var.datadog_api_key_secret_arn,
    DD_TRACE_ENABLED           = "true",
    DD_LOGS_INJECTION          = "true"
  }, var.lambda_extra_env != null ? var.lambda_extra_env : {})

  tags = {
    Name        = "${var.project_name}-${var.environment}-lambda-deliverables-hourly"
    Environment = var.environment
    Project     = var.project_name
    Service     = "skylight-${var.environment}-deliverables-hourly"
  }

  # Function configuration
  timeout     = lookup(var.lambda_timeouts, "deliverables", 15)
  memory_size = lookup(var.lambda_memory_sizes, "deliverables", 512)

  # IAM policy statements for Lambda functions
  policy_statements = {
    # Datadog API key access
    datadog_api_key_statement = {
      sid    = "DatadogApiKeyAccess"
      effect = "Allow"
      resources = [
        var.datadog_api_key_secret_arn
      ]
      actions = ["secretsmanager:GetSecretValue"]
    }

    # Application secrets access
    app_secrets_statement = {
      sid    = "AppSecretsAccess"
      effect = "Allow"
      resources = [
        aws_secretsmanager_secret.app_backend_secrets.arn,
        aws_secretsmanager_secret.app_frontend_secrets.arn
      ]
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
    }

    # S3 access for SSL certificates
    s3_ssl_cert_statement = {
      sid    = "S3SslCertAccess"
      effect = "Allow"
      resources = [
        "arn:aws:s3:::${module.ssl_cert_bucket.bucket_name}",
        "arn:aws:s3:::${module.ssl_cert_bucket.bucket_name}/*"
      ]
      actions = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
    }
  }
}

module "deliverables_nightly" {
  source  = "gitlab.com/MUFGIS/aws/lambda"
  version = "1.1.1"

  name    = "${var.project_name}-${var.environment}-lambda-deliverables-nightly"
  handler = "src/lambda.batchJobTwoHandler"
  runtime = var.lambda_runtime

  source_zip_path = "${path.module}/lambda_functions/deliverables.zip"

  vpc_config = {
    security_group_ids = [aws_security_group.lambda_sg.id]
    subnet_ids         = data.aws_subnets.private.ids
  }

  # Datadog integration
  datadog_tracing_enabled = true

  environment_variables = merge({
    # Application environment variables
    STAGE                = var.environment,
    PROJECT              = var.project_name,
    RDS_ENDPOINT         = module.rds.db_endpoint,
    RDS_PORT             = "5432",
    RDS_SSL_CERT_S3_PATH = "s3://${module.ssl_cert_bucket.bucket_name}/${var.rds_ssl_cert_s3_key}",
    RDS_SSL_MODE         = "require",

    # Secrets Manager ARN - applications should read all secrets from this single source
    BACKEND_SECRET_ARN  = aws_secretsmanager_secret.app_backend_secrets.arn,
    FRONTEND_SECRET_ARN = aws_secretsmanager_secret.app_frontend_secrets.arn,

    # Datadog environment variables
    LOG_LEVEL                  = var.lambda_log_level,
    DD_ENHANCED_METRICS        = "true",
    DD_SERVICE                 = "skylight-${var.environment}-deliverables-nightly",
    DD_SERVERLESS_LOGS_ENABLED = "true",
    DD_VERSION                 = var.DD_VERSION,
    DD_ENV                     = var.environment,
    DD_API_KEY_SECRET_ARN      = var.datadog_api_key_secret_arn,
    DD_TRACE_ENABLED           = "true",
    DD_LOGS_INJECTION          = "true"
  }, var.lambda_extra_env != null ? var.lambda_extra_env : {})

  tags = {
    Name        = "${var.project_name}-${var.environment}-lambda-deliverables-nightly"
    Environment = var.environment
    Project     = var.project_name
    Service     = "skylight-${var.environment}-deliverables-nightly"
  }

  # Function configuration
  timeout     = lookup(var.lambda_timeouts, "deliverables", 15)
  memory_size = lookup(var.lambda_memory_sizes, "deliverables", 512)

  # IAM policy statements for Lambda functions
  policy_statements = {
    # Datadog API key access
    datadog_api_key_statement = {
      sid    = "DatadogApiKeyAccess"
      effect = "Allow"
      resources = [
        var.datadog_api_key_secret_arn
      ]
      actions = ["secretsmanager:GetSecretValue"]
    }

    # Application secrets access
    app_secrets_statement = {
      sid    = "AppSecretsAccess"
      effect = "Allow"
      resources = [
        aws_secretsmanager_secret.app_backend_secrets.arn,
        aws_secretsmanager_secret.app_frontend_secrets.arn
      ]
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
    }

    # S3 access for SSL certificates
    s3_ssl_cert_statement = {
      sid    = "S3SslCertAccess"
      effect = "Allow"
      resources = [
        "arn:aws:s3:::${module.ssl_cert_bucket.bucket_name}",
        "arn:aws:s3:::${module.ssl_cert_bucket.bucket_name}/*"
      ]
      actions = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
    }
  }
}


module "runCadenceBatchJob" {
  source  = "gitlab.com/MUFGIS/aws/lambda"
  version = "1.1.1"

  name    = "${var.project_name}-${var.environment}-lambda-runCadenceBatchJob"
  handler = "src/lambda.cadenceJobHandler"
  runtime = var.lambda_runtime

  source_zip_path = "${path.module}/lambda_functions/crm.zip"

  vpc_config = {
    security_group_ids = [aws_security_group.lambda_sg.id]
    subnet_ids         = data.aws_subnets.private.ids
  }

  # Datadog integration
  datadog_tracing_enabled = true

  environment_variables = merge({
    # Application environment variables
    STAGE                = var.environment,
    PROJECT              = var.project_name,
    RDS_ENDPOINT         = module.rds.db_endpoint,
    RDS_PORT             = "5432",
    RDS_SSL_CERT_S3_PATH = "s3://${module.ssl_cert_bucket.bucket_name}/${var.rds_ssl_cert_s3_key}",
    RDS_SSL_MODE         = "require",

    # Secrets Manager ARN - applications should read all secrets from this single source
    BACKEND_SECRET_ARN  = aws_secretsmanager_secret.app_backend_secrets.arn,
    FRONTEND_SECRET_ARN = aws_secretsmanager_secret.app_frontend_secrets.arn,

    # Datadog environment variables
    LOG_LEVEL                  = var.lambda_log_level,
    DD_ENHANCED_METRICS        = "true",
    DD_SERVICE                 = "${var.project_name}-${var.environment}-runCadenceBatchJob",
    DD_SERVERLESS_LOGS_ENABLED = "true",
    DD_VERSION                 = var.DD_VERSION,
    DD_ENV                     = var.environment,
    DD_API_KEY_SECRET_ARN      = var.datadog_api_key_secret_arn,
    DD_TRACE_ENABLED           = "true",
    DD_LOGS_INJECTION          = "true"
  }, var.lambda_extra_env != null ? var.lambda_extra_env : {})

  tags = {
    Name        = "${var.project_name}-${var.environment}-lambda-runCadenceBatchJob"
    Environment = var.environment
    Project     = var.project_name
    Service     = "${var.project_name}-${var.environment}-runCadenceBatchJob"
  }

  # Function configuration
  timeout     = lookup(var.lambda_timeouts, "crm_runCadenceBatchJob", 10)
  memory_size = lookup(var.lambda_memory_sizes, "crm_runCadenceBatchJob", 128)

  # IAM policy statements for Lambda functions
  policy_statements = {
    # Datadog API key access
    datadog_api_key_statement = {
      sid    = "DatadogApiKeyAccess"
      effect = "Allow"
      resources = [
        var.datadog_api_key_secret_arn
      ]
      actions = ["secretsmanager:GetSecretValue"]
    }

    # Application secrets access
    app_secrets_statement = {
      sid    = "AppSecretsAccess"
      effect = "Allow"
      resources = [
        aws_secretsmanager_secret.app_backend_secrets.arn,
        aws_secretsmanager_secret.app_frontend_secrets.arn
      ]
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
    }

    # S3 access for SSL certificates
    s3_ssl_cert_statement = {
      sid    = "S3SslCertAccess"
      effect = "Allow"
      resources = [
        "arn:aws:s3:::${module.ssl_cert_bucket.bucket_name}",
        "arn:aws:s3:::${module.ssl_cert_bucket.bucket_name}/*"
      ]
      actions = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
    }
  }
}


module "runNotificationBatchJob" {
  source  = "gitlab.com/MUFGIS/aws/lambda"
  version = "1.1.1"

  name    = "${var.project_name}-${var.environment}-lambda-runNotificationBatchJob"
  handler = "src/lambda.notificationJobHandler"
  runtime = var.lambda_runtime

  source_zip_path = "${path.module}/lambda_functions/crm.zip"

  vpc_config = {
    security_group_ids = [aws_security_group.lambda_sg.id]
    subnet_ids         = data.aws_subnets.private.ids
  }

  # Datadog integration
  datadog_tracing_enabled = true

  environment_variables = merge({
    # Application environment variables
    STAGE                = var.environment,
    PROJECT              = var.project_name,
    RDS_ENDPOINT         = module.rds.db_endpoint,
    RDS_PORT             = "5432",
    RDS_SSL_CERT_S3_PATH = "s3://${module.ssl_cert_bucket.bucket_name}/${var.rds_ssl_cert_s3_key}",
    RDS_SSL_MODE         = "require",

    # Secrets Manager ARN - applications should read all secrets from this single source
    BACKEND_SECRET_ARN  = aws_secretsmanager_secret.app_backend_secrets.arn,
    FRONTEND_SECRET_ARN = aws_secretsmanager_secret.app_frontend_secrets.arn,

    # Datadog environment variables
    LOG_LEVEL                  = var.lambda_log_level,
    DD_ENHANCED_METRICS        = "true",
    DD_SERVICE                 = "${var.project_name}-${var.environment}-runNotificationBatchJob",
    DD_SERVERLESS_LOGS_ENABLED = "true",
    DD_VERSION                 = var.DD_VERSION,
    DD_ENV                     = var.environment,
    DD_API_KEY_SECRET_ARN      = var.datadog_api_key_secret_arn,
    DD_TRACE_ENABLED           = "true",
    DD_LOGS_INJECTION          = "true"
  }, var.lambda_extra_env != null ? var.lambda_extra_env : {})

  tags = {
    Name        = "${var.project_name}-${var.environment}-lambda-runNotificationBatchJob"
    Environment = var.environment
    Project     = var.project_name
    Service     = "${var.project_name}-${var.environment}-runNotificationBatchJob"
  }

  # Function configuration
  timeout     = lookup(var.lambda_timeouts, "crm_runNotificationBatchJob", 10)
  memory_size = lookup(var.lambda_memory_sizes, "crm_runNotificationBatchJob", 128)

  # IAM policy statements for Lambda functions
  policy_statements = {
    # Datadog API key access
    datadog_api_key_statement = {
      sid    = "DatadogApiKeyAccess"
      effect = "Allow"
      resources = [
        var.datadog_api_key_secret_arn
      ]
      actions = ["secretsmanager:GetSecretValue"]
    }

    # Application secrets access
    app_secrets_statement = {
      sid    = "AppSecretsAccess"
      effect = "Allow"
      resources = [
        aws_secretsmanager_secret.app_backend_secrets.arn,
        aws_secretsmanager_secret.app_frontend_secrets.arn
      ]
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
    }

    # S3 access for SSL certificates
    s3_ssl_cert_statement = {
      sid    = "S3SslCertAccess"
      effect = "Allow"
      resources = [
        "arn:aws:s3:::${module.ssl_cert_bucket.bucket_name}",
        "arn:aws:s3:::${module.ssl_cert_bucket.bucket_name}/*"
      ]
      actions = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
    }
  }
}

module "syncActionLogStatuses" {
  source  = "gitlab.com/MUFGIS/aws/lambda"
  version = "1.1.1"

  name    = "${var.project_name}-${var.environment}-lambda-syncActionLogStatuses"
  handler = "src/lambda.actionLogStatusHandler"
  runtime = var.lambda_runtime

  source_zip_path = "${path.module}/lambda_functions/crm.zip"

  vpc_config = {
    security_group_ids = [aws_security_group.lambda_sg.id]
    subnet_ids         = data.aws_subnets.private.ids
  }

  # Datadog integration
  datadog_tracing_enabled = true

  environment_variables = merge({
    # Application environment variables
    STAGE                = var.environment,
    PROJECT              = var.project_name,
    RDS_ENDPOINT         = module.rds.db_endpoint,
    RDS_PORT             = "5432",
    RDS_SSL_CERT_S3_PATH = "s3://${module.ssl_cert_bucket.bucket_name}/${var.rds_ssl_cert_s3_key}",
    RDS_SSL_MODE         = "require",

    # Secrets Manager ARN - applications should read all secrets from this single source
    BACKEND_SECRET_ARN  = aws_secretsmanager_secret.app_backend_secrets.arn,
    FRONTEND_SECRET_ARN = aws_secretsmanager_secret.app_frontend_secrets.arn,

    # Datadog environment variables
    LOG_LEVEL                  = var.lambda_log_level,
    DD_ENHANCED_METRICS        = "true",
    DD_SERVICE                 = "${var.project_name}-${var.environment}-syncActionLogStatuses",
    DD_SERVERLESS_LOGS_ENABLED = "true",
    DD_VERSION                 = var.DD_VERSION,
    DD_ENV                     = var.environment,
    DD_API_KEY_SECRET_ARN      = var.datadog_api_key_secret_arn,
    DD_TRACE_ENABLED           = "true",
    DD_LOGS_INJECTION          = "true"
  }, var.lambda_extra_env != null ? var.lambda_extra_env : {})

  tags = {
    Name        = "${var.project_name}-${var.environment}-lambda-syncActionLogStatuses"
    Environment = var.environment
    Project     = var.project_name
    Service     = "${var.project_name}-${var.environment}-syncActionLogStatuses"
  }

  # Function configuration
  timeout     = lookup(var.lambda_timeouts, "crm_syncActionLogStatuses", 10)
  memory_size = lookup(var.lambda_memory_sizes, "crm_syncActionLogStatuses", 128)

  # IAM policy statements for Lambda functions
  policy_statements = {
    # Datadog API key access
    datadog_api_key_statement = {
      sid    = "DatadogApiKeyAccess"
      effect = "Allow"
      resources = [
        var.datadog_api_key_secret_arn
      ]
      actions = ["secretsmanager:GetSecretValue"]
    }

    # Application secrets access
    app_secrets_statement = {
      sid    = "AppSecretsAccess"
      effect = "Allow"
      resources = [
        aws_secretsmanager_secret.app_backend_secrets.arn,
        aws_secretsmanager_secret.app_frontend_secrets.arn
      ]
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
    }

    # S3 access for SSL certificates
    s3_ssl_cert_statement = {
      sid    = "S3SslCertAccess"
      effect = "Allow"
      resources = [
        "arn:aws:s3:::${module.ssl_cert_bucket.bucket_name}",
        "arn:aws:s3:::${module.ssl_cert_bucket.bucket_name}/*"
      ]
      actions = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
    }
  }
}

module "renewOutlookSubscriptions" {
  source  = "gitlab.com/MUFGIS/aws/lambda"
  version = "1.1.1"

  name    = "${var.project_name}-${var.environment}-lambda-renewOutlookSubscriptions"
  handler = "src/lambda.outlookRenewHandler"
  runtime = var.lambda_runtime

  source_zip_path = "${path.module}/lambda_functions/crm.zip"

  vpc_config = {
    security_group_ids = [aws_security_group.lambda_sg.id]
    subnet_ids         = data.aws_subnets.private.ids
  }

  # Datadog integration
  datadog_tracing_enabled = true

  environment_variables = merge({
    # Application environment variables
    STAGE                = var.environment,
    PROJECT              = var.project_name,
    RDS_ENDPOINT         = module.rds.db_endpoint,
    RDS_PORT             = "5432",
    RDS_SSL_CERT_S3_PATH = "s3://${module.ssl_cert_bucket.bucket_name}/${var.rds_ssl_cert_s3_key}",
    RDS_SSL_MODE         = "require",

    # Secrets Manager ARN - applications should read all secrets from this single source
    BACKEND_SECRET_ARN  = aws_secretsmanager_secret.app_backend_secrets.arn,
    FRONTEND_SECRET_ARN = aws_secretsmanager_secret.app_frontend_secrets.arn,

    # Datadog environment variables
    LOG_LEVEL                  = var.lambda_log_level,
    DD_ENHANCED_METRICS        = "true",
    DD_SERVICE                 = "${var.project_name}-${var.environment}-renewOutlookSubscriptions",
    DD_SERVERLESS_LOGS_ENABLED = "true",
    DD_VERSION                 = var.DD_VERSION,
    DD_ENV                     = var.environment,
    DD_API_KEY_SECRET_ARN      = var.datadog_api_key_secret_arn,
    DD_TRACE_ENABLED           = "true",
    DD_LOGS_INJECTION          = "true"
  }, var.lambda_extra_env != null ? var.lambda_extra_env : {})

  tags = {
    Name        = "${var.project_name}-${var.environment}-lambda-renewOutlookSubscriptions"
    Environment = var.environment
    Project     = var.project_name
    Service     = "${var.project_name}-${var.environment}-renewOutlookSubscriptions"
  }

  # Function configuration
  timeout     = lookup(var.lambda_timeouts, "crm_renewOutlookSubscriptions", 10)
  memory_size = lookup(var.lambda_memory_sizes, "crm_renewOutlookSubscriptions", 128)

  # IAM policy statements for Lambda functions
  policy_statements = {
    # Datadog API key access
    datadog_api_key_statement = {
      sid    = "DatadogApiKeyAccess"
      effect = "Allow"
      resources = [
        var.datadog_api_key_secret_arn
      ]
      actions = ["secretsmanager:GetSecretValue"]
    }

    # Application secrets access
    app_secrets_statement = {
      sid    = "AppSecretsAccess"
      effect = "Allow"
      resources = [
        aws_secretsmanager_secret.app_backend_secrets.arn,
        aws_secretsmanager_secret.app_frontend_secrets.arn
      ]
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
    }

    # S3 access for SSL certificates
    s3_ssl_cert_statement = {
      sid    = "S3SslCertAccess"
      effect = "Allow"
      resources = [
        "arn:aws:s3:::${module.ssl_cert_bucket.bucket_name}",
        "arn:aws:s3:::${module.ssl_cert_bucket.bucket_name}/*"
      ]
      actions = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
    }
  }
}

# EventBridge Rules for Deliverables Batch Jobs
resource "aws_cloudwatch_event_rule" "deliverables_hourly" {
  name                = "${var.project_name}-${var.environment}-deliverables-hourly"
  description         = "Triggers deliverables batch job one every hour (SLA updates)"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_rule" "deliverables_daily_midnight" {
  name                = "${var.project_name}-${var.environment}-deliverables-nightly"
  description         = "Triggers deliverables nightly job daily at midnight UTC (task creation)"
  schedule_expression = "cron(0 0 * * ? *)"
}

resource "aws_cloudwatch_event_rule" "CRM_runCadenceBatchJob_noon_midnight" {
  name                = "${var.project_name}-${var.environment}-runCadenceBatchJob"
  description         = "Triggers CRM cadence batch job at 00:00 and 12:00 daily"
  schedule_expression = "cron(0 0,12 * * ? *)"
}

resource "aws_cloudwatch_event_rule" "CRM_runNotificationBatchJob_noon_midnight" {
  name                = "${var.project_name}-${var.environment}-runNotificationBatchJob"
  description         = "Triggers CRM Notification batch job at 00:05 and 12:05 daily"
  schedule_expression = "cron(5 0,12 * * ? *)"
}

resource "aws_cloudwatch_event_rule" "CRM_syncActionLogStatuses_midnight" {
  name                = "${var.project_name}-${var.environment}-syncActionLogStatusesJob"
  description         = "Triggers CRM Sync Action Log statuses at 00:00 daily"
  schedule_expression = "cron(0 0 * * ? *)"
}

resource "aws_cloudwatch_event_rule" "CRM_renewOutlookSubscriptions_midnight" {
  name                = "${var.project_name}-${var.environment}-renewOutlookSubscriptions"
  description         = "Triggers CRM Renew Outlook Subscriptions at 00:30 daily"
  schedule_expression = "cron(30 0 * * ? *)"
}

# EventBridge Targets - Connect rules to specific batch job lambda functions
resource "aws_cloudwatch_event_target" "deliverables_hourly_target" {
  rule      = aws_cloudwatch_event_rule.deliverables_hourly.name
  target_id = "DeliverablesLambdaHourlyTarget"
  arn       = module.deliverables_hourly.arn
}

resource "aws_cloudwatch_event_target" "deliverables_daily_midnight_target" {
  rule      = aws_cloudwatch_event_rule.deliverables_daily_midnight.name
  target_id = "DeliverablesLambdaNightlyTarget"
  arn       = module.deliverables_nightly.arn
}

resource "aws_cloudwatch_event_target" "CRM_runCadenceBatchJob_noon_midnight_target" {
  rule      = aws_cloudwatch_event_rule.CRM_runCadenceBatchJob_noon_midnight.name
  target_id = "CRMCadenceNoonMidnightTarget"
  arn       = module.runCadenceBatchJob.arn
}

resource "aws_cloudwatch_event_target" "CRM_runNotificationBatchJob_noon_midnight_target" {
  rule      = aws_cloudwatch_event_rule.CRM_runNotificationBatchJob_noon_midnight.name
  target_id = "CRMNotificationNoonMidnightTarget"
  arn       = module.runNotificationBatchJob.arn
}

resource "aws_cloudwatch_event_target" "CRM_syncActionLogStatuses_midnight_target" {
  rule      = aws_cloudwatch_event_rule.CRM_syncActionLogStatuses_midnight.name
  target_id = "CRMActionLogStatusMidnightTarget"
  arn       = module.syncActionLogStatuses.arn
}

resource "aws_cloudwatch_event_target" "CRM_renewOutlookSubscriptions_midnight_target" {
  rule      = aws_cloudwatch_event_rule.CRM_renewOutlookSubscriptions_midnight.name
  target_id = "CRMOutlookLogStatusMidnightTarget"
  arn       = module.renewOutlookSubscriptions.arn
}

# Lambda permissions to allow EventBridge to invoke the batch job functions
resource "aws_lambda_permission" "allow_eventbridge_hourly" {
  statement_id  = "AllowExecutionFromEventBridgeHourly"
  action        = "lambda:InvokeFunction"
  function_name = module.deliverables_hourly.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.deliverables_hourly.arn
}

resource "aws_lambda_permission" "allow_eventbridge_nightly" {
  statement_id  = "AllowExecutionFromEventBridgeNightly"
  action        = "lambda:InvokeFunction"
  function_name = module.deliverables_nightly.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.deliverables_daily_midnight.arn
}

resource "aws_lambda_permission" "allow_eventbridge_runCadenceBatchJob" {
  statement_id  = "AllowExecutionFromEventBridgeRunCadenceBatchJob"
  action        = "lambda:InvokeFunction"
  function_name = module.runCadenceBatchJob.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.CRM_runCadenceBatchJob_noon_midnight.arn
}

resource "aws_lambda_permission" "allow_eventbridge_runNotificationBatchJob" {
  statement_id  = "AllowExecutionFromEventBridgeRunNotificationBatchJob"
  action        = "lambda:InvokeFunction"
  function_name = module.runNotificationBatchJob.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.CRM_runNotificationBatchJob_noon_midnight.arn
}

resource "aws_lambda_permission" "allow_eventbridge_syncActionLogStatuses" {
  statement_id  = "AllowExecutionFromEventBridgesyncActionLogStatuses"
  action        = "lambda:InvokeFunction"
  function_name = module.syncActionLogStatuses.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.CRM_syncActionLogStatuses_midnight.arn
}

resource "aws_lambda_permission" "allow_eventbridge_renewOutlookSubscriptions" {
  statement_id  = "AllowExecutionFromEventBridgerenewOutlookSubscriptions"
  action        = "lambda:InvokeFunction"
  function_name = module.renewOutlookSubscriptions.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.CRM_renewOutlookSubscriptions_midnight.arn
}