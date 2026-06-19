terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "uploads" {
  bucket        = var.upload_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "upload_bucket_cors" {

  bucket = aws_s3_bucket.uploads.id

  cors_rule {

    allowed_headers = ["*"]

    allowed_methods = [
      "PUT",
      "GET",
      "HEAD"
    ]

    allowed_origins = [
      "*"
    ]

    expose_headers = ["ETag"]

    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket" "website" {
  bucket        = var.website_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "image_metadata" {
  name         = "ImageMetadata"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "userId"
  range_key = "imageId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "imageId"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  local_secondary_index {
    name            = "CreatedAtIndex"
    projection_type = "ALL"
    range_key       = "createdAt"
  }
}

resource "aws_sqs_queue" "image_processing_dlq" {
  name = "ImageProcessingDLQ"
}

resource "aws_sqs_queue" "image_processing_queue" {
  name = "ImageProcessingQueue"

  visibility_timeout_seconds = 360

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.image_processing_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sns_topic" "image_notifications" {
  name = "ImageProcessingNotifications"
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.image_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_iam_role" "api_lambda_role" {
  name = "api-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "lambda.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "lambda_logs" {
  name = "lambda-logs-policy"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]

      Resource = "*"
    }]
  })
}

resource "aws_iam_policy" "api_lambda_policy" {
  name = "api-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "s3:PutObject",
        "s3:GetObject"
      ]

      Resource = "${aws_s3_bucket.uploads.arn}/*"
      },
      {
        Effect = "Allow"

        Action = [
          "dynamodb:Query",
          "dynamodb:GetItem",
          "dynamodb:PutItem"
        ]

        Resource = [
          aws_dynamodb_table.image_metadata.arn,
          "${aws_dynamodb_table.image_metadata.arn}/index/*"
        ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_logs" {
  role       = aws_iam_role.api_lambda_role.name
  policy_arn = aws_iam_policy.lambda_logs.arn
}

resource "aws_iam_role_policy_attachment" "api_policy" {
  role       = aws_iam_role.api_lambda_role.name
  policy_arn = aws_iam_policy.api_lambda_policy.arn
}

resource "aws_iam_role" "processor_lambda_role" {
  name = "processor-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "lambda.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "processor_lambda_policy" {
  name = "processor-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "s3:GetObject"
      ]

      Resource = [
        "${aws_s3_bucket.uploads.arn}/*"
      ]
      },
      {
        Effect = "Allow"

        Action = [
          "s3:ListBucket"
        ]

        Resource = [
          aws_s3_bucket.uploads.arn
        ]
      },
      {
        Effect = "Allow"

        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]

        Resource = aws_dynamodb_table.image_metadata.arn
      },
      {
        Effect = "Allow"

        Action = [
          "sns:Publish"
        ]

        Resource = aws_sns_topic.image_notifications.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "processor_logs" {
  role       = aws_iam_role.processor_lambda_role.name
  policy_arn = aws_iam_policy.lambda_logs.arn
}

resource "aws_iam_role_policy_attachment" "processor_policy" {
  role       = aws_iam_role.processor_lambda_role.name
  policy_arn = aws_iam_policy.processor_lambda_policy.arn
}

resource "aws_iam_role_policy_attachment" "processor_sqs_policy" {
  role       = aws_iam_role.processor_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

resource "aws_iam_role" "pre_token_generation_lambda_role" {
  name = "pre-token-generation-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "lambda.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "pre_token_generation_logs_policy" {
  role       = aws_iam_role.pre_token_generation_lambda_role.name
  policy_arn = aws_iam_policy.lambda_logs.arn
}

resource "aws_lambda_function" "api" {
  function_name = "ImageAPI"
  role          = aws_iam_role.api_lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.13"
  timeout       = 30

  filename         = "../lambda/api/api.zip"
  source_code_hash = filebase64sha256("../lambda/api/api.zip")

  environment {
    variables = {
      UPLOAD_BUCKET = aws_s3_bucket.uploads.bucket
      TABLE_NAME    = aws_dynamodb_table.image_metadata.name
    }
  }
}

resource "aws_lambda_function" "processor" {
  function_name = "ImageProcessor"
  role          = aws_iam_role.processor_lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.13"
  timeout       = 60

  filename         = "../lambda/processor/processor.zip"
  source_code_hash = filebase64sha256("../lambda/processor/processor.zip")

  environment {
    variables = {
      UPLOAD_BUCKET = aws_s3_bucket.uploads.bucket
      TABLE_NAME    = aws_dynamodb_table.image_metadata.name
      SNS_TOPIC_ARN = aws_sns_topic.image_notifications.arn
    }
  }
}

resource "aws_lambda_function" "pre_token_generation" {
  function_name = "PreTokenGenerationTrigger"
  role          = aws_iam_role.pre_token_generation_lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.13"
  timeout       = 30

  filename         = "../lambda/pre_token_generation/pre_token_generation.zip"
  source_code_hash = filebase64sha256("../lambda/pre_token_generation/pre_token_generation.zip")
}

resource "aws_cognito_user_pool" "users" {
  name = "image-pipeline-users"

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  lambda_config {
    pre_token_generation = aws_lambda_function.pre_token_generation.arn

    pre_token_generation_config {
      lambda_arn     = aws_lambda_function.pre_token_generation.arn
      lambda_version = "V2_0"
    }
  }
}

resource "aws_lambda_permission" "allow_cognito_pre_token" {
  statement_id = "AllowExecutionFromCognito"
  action       = "lambda:InvokeFunction"

  function_name = aws_lambda_function.pre_token_generation.function_name

  principal = "cognito-idp.amazonaws.com"

  source_arn = aws_cognito_user_pool.users.arn
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "tring-image-api-auth"
  user_pool_id = aws_cognito_user_pool.users.id
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "image-api-client"
  user_pool_id = aws_cognito_user_pool.users.id

  generate_secret = false

  supported_identity_providers = [
    "COGNITO"
  ]

  allowed_oauth_flows_user_pool_client = true

  allowed_oauth_flows = [
    "code"
  ]

  allowed_oauth_scopes = [
    "email",
    "openid",
    "profile"
  ]

  callback_urls = [
    "https://${aws_cloudfront_distribution.website.domain_name}"
  ]

  logout_urls = [
    "https://${aws_cloudfront_distribution.website.domain_name}"
  ]
}

resource "aws_apigatewayv2_api" "image_api" {
  name          = "ImageAPI"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = [
      "*"
    ]

    allow_methods = [
      "GET",
      "POST",
      "OPTIONS"
    ]

    allow_headers = [
      "authorization",
      "content-type"
    ]
  }  
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id = aws_apigatewayv2_api.image_api.id

  authorizer_type = "JWT"
  name            = "jwt-authorizer"

  identity_sources = [
    "$request.header.Authorization"
  ]

  jwt_configuration {
    audience = [
      aws_cognito_user_pool_client.client.id
    ]

    issuer = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.users.id}"
  }
}

resource "aws_apigatewayv2_stage" "dev" {
  api_id      = aws_apigatewayv2_api.image_api.id
  name        = "dev"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "api_lambda" {
  api_id = aws_apigatewayv2_api.image_api.id

  integration_type = "AWS_PROXY"

  integration_uri = aws_lambda_function.api.invoke_arn

  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "upload_image" {
  api_id = aws_apigatewayv2_api.image_api.id

  route_key = "POST /images"

  target = "integrations/${aws_apigatewayv2_integration.api_lambda.id}"

  authorization_type = "JWT"

  authorizer_id = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "get_all_image" {
  api_id = aws_apigatewayv2_api.image_api.id

  route_key = "GET /images"

  target = "integrations/${aws_apigatewayv2_integration.api_lambda.id}"

  authorization_type = "JWT"

  authorizer_id = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "get_image" {
  api_id = aws_apigatewayv2_api.image_api.id

  route_key = "GET /images/{imageId}"

  target = "integrations/${aws_apigatewayv2_integration.api_lambda.id}"

  authorization_type = "JWT"

  authorizer_id = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_lambda_permission" "allow_apigateway" {
  statement_id = "AllowExecutionFromAPIGateway"
  action       = "lambda:InvokeFunction"

  function_name = aws_lambda_function.api.function_name

  principal = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.image_api.execution_arn}/*/*"
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.image_processing_queue.arn
  function_name    = aws_lambda_function.processor.function_name
  batch_size       = 1
}

resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.image_processing_queue.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "s3.amazonaws.com"
        }

        Action = "sqs:SendMessage"

        Resource = aws_sqs_queue.image_processing_queue.arn

        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.uploads.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  queue {
    queue_arn = aws_sqs_queue.image_processing_queue.arn

    events = [
      "s3:ObjectCreated:*"
    ]
  }

  depends_on = [
    aws_sqs_queue_policy.allow_s3
  ]
}

resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "website-oac"
  description                       = "OAC for website bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "website" {

  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "website-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  default_cache_behavior {

    target_origin_id = "website-origin"

    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = [
      "GET",
      "HEAD"
    ]

    cached_methods = [
      "GET",
      "HEAD"
    ]

    compress = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_s3_bucket_policy" "website" {

  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"

        Principal = {
          Service = "cloudfront.amazonaws.com"
        }

        Action = [
          "s3:GetObject"
        ]

        Resource = [
          "${aws_s3_bucket.website.arn}/*"
        ]

        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_object" "config_js" {
  bucket = aws_s3_bucket.website.id

  key = "config.js"

  content = templatefile(
    "../website/config.js.tpl",
    {
      api_url        = aws_apigatewayv2_api.image_api.api_endpoint
      user_pool_id   = aws_cognito_user_pool.users.id
      client_id      = aws_cognito_user_pool_client.client.id
      region         = var.aws_region
      cognito_domain = aws_cognito_user_pool_domain.domain.domain
    }
  )

  content_type = "application/javascript"
}

locals {
  website_files = [
    for file in fileset("../website", "*") :
    file
    if !contains(["config.js", "config.js.tpl"], file)
  ]
}

locals {
  content_types = {
    html = "text/html"
    css  = "text/css"
    js   = "application/javascript"
  }
}

resource "aws_s3_object" "website_files" {

  for_each = toset(local.website_files)

  bucket = aws_s3_bucket.website.id

  key = each.value

  source = "../website/${each.value}"

  etag = filemd5("../website/${each.value}")

  content_type = lookup(
    local.content_types,
    reverse(split(".", each.value))[0],
    "application/octet-stream"
  )
}