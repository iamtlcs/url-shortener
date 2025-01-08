provider "aws" {
  region = "ap-southeast-1"
}

# DynamoDB table to store URL mappings
resource "aws_dynamodb_table" "url_mappings" {
  name           = "url-mappings"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "short_url"
  
  attribute {
    name = "short_url"
    type = "S"
  }

  ttl {
    attribute_name = "expiry"
    enabled        = true
  }
}

# Lambda role and policy
resource "aws_iam_role" "lambda_role" {
  name = "url_shortener_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "url_shortener_lambda_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.url_mappings.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda functions
resource "aws_lambda_function" "create_short_url" {
  filename         = "create_short_url.zip"
  function_name    = "create_short_url"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "python3.12"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.url_mappings.name
    }
  }
}

resource "aws_lambda_function" "redirect_url" {
  filename         = "redirect_url.zip"
  function_name    = "redirect_url"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "python3.12"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.url_mappings.name
    }
  }
}

# CloudWatch log groups
resource "aws_cloudwatch_log_group" "create_short_url" {
  name = "/aws/lambda/create_short_url"
}

resource "aws_cloudwatch_log_group" "redirect_url" {
  name = "/aws/lambda/redirect_url"
}

# API Gateway
resource "aws_api_gateway_rest_api" "url_shortener" {
  name = "url-shortener"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Principal = "*"
#         Action = "execute-api:Invoke"
#         Resource = "arn:aws:execute-api:*:*:*/*/*/*"
#         Condition = {
#           IpAddress = {
#             "aws:SourceIp": ["218.189.44.128/25"]  # /25 CIDR covers 218.189.44.128 - 218.189.44.255
#           }
#         }
#       },
#       {
#         Effect = "Deny"
#         Principal = "*"
#         Action = "execute-api:Invoke"
#         Resource = "arn:aws:execute-api:*:*:*/*/*/*"
#         Condition = {
#           NotIpAddress = {
#             "aws:SourceIp": ["218.189.44.128/25"]
#           }
#         }
#       }
#     ]
#   })
}

# POST method for creating short URLs
resource "aws_api_gateway_resource" "create" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener.id
  parent_id   = aws_api_gateway_rest_api.url_shortener.root_resource_id
  path_part   = "create"
}

resource "aws_api_gateway_method" "create" {
  rest_api_id   = aws_api_gateway_rest_api.url_shortener.id
  resource_id   = aws_api_gateway_resource.create.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "create" {
  rest_api_id             = aws_api_gateway_rest_api.url_shortener.id
  resource_id             = aws_api_gateway_resource.create.id
  http_method             = aws_api_gateway_method.create.http_method
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.create_short_url.invoke_arn
}

# GET method for redirecting
resource "aws_api_gateway_resource" "redirect" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener.id
  parent_id   = aws_api_gateway_rest_api.url_shortener.root_resource_id
  path_part   = "{shortUrl}"
}

resource "aws_api_gateway_method" "redirect" {
  rest_api_id   = aws_api_gateway_rest_api.url_shortener.id
  resource_id   = aws_api_gateway_resource.redirect.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "redirect" {
  rest_api_id             = aws_api_gateway_rest_api.url_shortener.id
  resource_id             = aws_api_gateway_resource.redirect.id
  http_method             = aws_api_gateway_method.redirect.http_method
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.redirect_url.invoke_arn
}

# Deployment
resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener.id
  
  depends_on = [
    aws_api_gateway_integration.create,
    aws_api_gateway_integration.redirect
  ]
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.prod.id
  rest_api_id   = aws_api_gateway_rest_api.url_shortener.id
  stage_name    = "prod"
}

output "api_gateway_invoke_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}