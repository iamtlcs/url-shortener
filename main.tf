variable "aws_access_key" {
  description = "AWS access key"
  type        = string
  default     = ""
}

variable "aws_secret_key" {
  description = "AWS secret key"
  type        = string
  default     = ""
}

locals {
  env_vars = { for line in split("\n", file(".env")) : 
    split("=", line)[0] => split("=", line)[1] if length(split("=", line)) == 2
  }

  credentials = tomap({
    access_key = var.aws_access_key != "" ? var.aws_access_key : local.env_vars["AWS_ACCESS_KEY_ID"]
    secret_key = var.aws_secret_key != "" ? var.aws_secret_key : local.env_vars["AWS_SECRET_ACCESS_KEY"]
  })
}

provider "aws" {
  region     = "ap-southeast-1"
  access_key = local.credentials["access_key"]
  secret_key = local.credentials["secret_key"]
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Create the HTML content from template
data "template_file" "index_html" {
  template = file("index.html.tftpl")
  vars = {
    api_endpoint = aws_api_gateway_stage.prod.invoke_url
  }
}

# Upload the rendered HTML
resource "aws_s3_object" "index" {
  bucket         = aws_s3_bucket.url_shortener_bucket.id
  key            = "index.html"
  content        = data.template_file.index_html.rendered
  content_type   = "text/html"
  storage_class  = "STANDARD"

  # Force update by including the API Gateway URL in the etag
  etag = md5(join("", [data.template_file.index_html.rendered, aws_api_gateway_stage.prod.invoke_url]))

  # Disable caching for the index.html
  cache_control = "no-cache, no-store, must-revalidate"
}

# S3 bucket for simple HTML page
resource "aws_s3_bucket" "url_shortener_bucket" {
  bucket_prefix = "url-shortener"
}

# Bucket ownership controls
resource "aws_s3_bucket_ownership_controls" "url_shortener_bucket_ownership" {
  bucket = aws_s3_bucket.url_shortener_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Bucket public access block
resource "aws_s3_bucket_public_access_block" "url_shortener_bucket_public_access" {
  bucket = aws_s3_bucket.url_shortener_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Bucket ACL
resource "aws_s3_bucket_acl" "url_shortener_bucket_acl" {
  depends_on = [
    aws_s3_bucket_ownership_controls.url_shortener_bucket_ownership,
    aws_s3_bucket_public_access_block.url_shortener_bucket_public_access,
  ]

  bucket = aws_s3_bucket.url_shortener_bucket.id
  acl    = "public-read"
}

# Enable static website hosting
resource "aws_s3_bucket_website_configuration" "url_shortener_website" {
  bucket = aws_s3_bucket.url_shortener_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# Add bucket policy to allow public read access
resource "aws_s3_bucket_policy" "allow_public_read" {
  bucket = aws_s3_bucket.url_shortener_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.url_shortener_bucket.arn}/*"
      },
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.url_shortener_bucket_public_access
  ]
}

# Lambda functions ZIP files
resource "aws_s3_object" "create_short_url_zip" {
  bucket = aws_s3_bucket.url_shortener_bucket.id
  key    = "create_short_url.zip"
  source = "create_short_url.zip"
}

resource "aws_s3_object" "redirect_url_zip" {
  bucket = aws_s3_bucket.url_shortener_bucket.id
  key    = "redirect_url.zip"
  source = "redirect_url.zip"
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
  s3_bucket        = aws_s3_bucket.url_shortener_bucket.id
  s3_key           = "create_short_url.zip"
  function_name    = "create_short_url"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  memory_size      = 128
  timeout          = 300

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.url_mappings.name
    }
  }
}

resource "aws_lambda_function" "redirect_url" {
  s3_bucket        = aws_s3_bucket.url_shortener_bucket.id
  s3_key           = "redirect_url.zip"
  function_name    = "redirect_url"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  memory_size      = 128
  timeout          = 300

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.url_mappings.name
    }
  }
}

# Lambda permissions for API Gateway to invoke the create function
resource "aws_lambda_permission" "create_api_gateway" {
  statement_id  = "AllowAPIGatewayInvokeCreate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_short_url.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.url_shortener.execution_arn}/*/${aws_api_gateway_method.create.http_method}${aws_api_gateway_resource.create.path}"
}

# Lambda permissions for API Gateway to invoke the redirect function
resource "aws_lambda_permission" "redirect_api_gateway" {
  statement_id  = "AllowAPIGatewayInvokeRedirect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.redirect_url.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.url_shortener.execution_arn}/*/${aws_api_gateway_method.redirect.http_method}${aws_api_gateway_resource.redirect.path}"
}

# API Gateway
resource "aws_api_gateway_rest_api" "url_shortener" {
  name = "url-shortener"
}

resource "aws_api_gateway_rest_api_policy" "api_policy" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = [
          aws_lambda_function.create_short_url.arn,
          aws_lambda_function.redirect_url.arn
        ],
        Principal = "*"
      },
      {
        Effect = "Allow"
        Principal = "*"
        Action = "execute-api:Invoke"
        Resource = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.url_shortener.id}/*/*/*"
      },
      # Uncomment the following block to restrict access to the API to a specific IP address
      # {
      #   "Effect": "Deny",
      #   "Principal": "*",
      #   "Action": "execute-api:Invoke",
      #   "Resource": "execute-api:/*/*/*",
      #   "Condition": {
      #     "NotIpAddress": {
      #       "aws:SourceIp": ["218.189.44.128/25"]
      #     }
      #   }
      # }
    ]
  })
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
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.create_short_url.invoke_arn
}

# Add OPTIONS method for CORS
resource "aws_api_gateway_method" "create_options" {
  rest_api_id   = aws_api_gateway_rest_api.url_shortener.id
  resource_id   = aws_api_gateway_resource.create.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "create_options" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener.id
  resource_id = aws_api_gateway_resource.create.id
  http_method = aws_api_gateway_method.create_options.http_method
  type        = "MOCK"
  
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "create_options" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener.id
  resource_id = aws_api_gateway_resource.create.id
  http_method = aws_api_gateway_method.create_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "create_options" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener.id
  resource_id = aws_api_gateway_resource.create.id
  http_method = aws_api_gateway_method.create_options.http_method
  status_code = aws_api_gateway_method_response.create_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_method_response" "create" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener.id
  resource_id = aws_api_gateway_resource.create.id
  http_method = aws_api_gateway_method.create.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

# GET method for redirecting
resource "aws_api_gateway_resource" "redirect" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener.id
  parent_id   = aws_api_gateway_rest_api.url_shortener.root_resource_id
  path_part   = "{shortUrl}"
}

resource "aws_api_gateway_integration" "redirect" {
  rest_api_id             = aws_api_gateway_rest_api.url_shortener.id
  resource_id             = aws_api_gateway_resource.redirect.id
  http_method             = "GET"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.redirect_url.invoke_arn

  request_parameters = {}

  depends_on = [
    aws_lambda_function.redirect_url,
    aws_api_gateway_method.redirect
  ]
}

resource "aws_api_gateway_method" "redirect" {
  rest_api_id   = aws_api_gateway_rest_api.url_shortener.id
  resource_id   = aws_api_gateway_resource.redirect.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.shortUrl" = true
  }
  depends_on = [
    aws_api_gateway_resource.redirect,
  ]
}

# Add OPTIONS method for redirect endpoint
resource "aws_api_gateway_method" "redirect_options" {
  rest_api_id   = aws_api_gateway_rest_api.url_shortener.id
  resource_id   = aws_api_gateway_resource.redirect.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "redirect_options" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener.id
  resource_id = aws_api_gateway_resource.redirect.id
  http_method = aws_api_gateway_method.redirect_options.http_method
  type        = "MOCK"
  
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "redirect_options" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener.id
  resource_id = aws_api_gateway_resource.redirect.id
  http_method = aws_api_gateway_method.redirect_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "redirect_options" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener.id
  resource_id = aws_api_gateway_resource.redirect.id
  http_method = aws_api_gateway_method.redirect_options.http_method
  status_code = aws_api_gateway_method_response.redirect_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Deployment
resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener.id
  
  depends_on = [
    aws_api_gateway_integration.create,
    aws_api_gateway_integration.redirect,
    aws_api_gateway_rest_api_policy.api_policy,
    aws_api_gateway_method.create,
    aws_api_gateway_method.redirect,
    aws_lambda_permission.create_api_gateway,
    aws_lambda_permission.redirect_api_gateway,
    aws_api_gateway_resource.create,
    aws_api_gateway_resource.redirect,
    aws_api_gateway_method.create_options,
    aws_api_gateway_integration.create_options,
    aws_api_gateway_method.redirect_options,
    aws_api_gateway_integration.redirect_options
  ]

  triggers = {
    redeployment = sha1(jsonencode([
      aws_iam_role.lambda_role.id,
      aws_api_gateway_resource.create.id,
      aws_api_gateway_method.create.id,
      aws_api_gateway_integration.create.id,
      aws_api_gateway_resource.redirect.id,
      aws_api_gateway_method.redirect.id,
      aws_api_gateway_integration.redirect.id,
      aws_api_gateway_method.create_options.id,
      aws_api_gateway_integration.create_options.id,
      aws_api_gateway_method.redirect_options.id,
      aws_api_gateway_integration.redirect_options.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.prod.id
  rest_api_id   = aws_api_gateway_rest_api.url_shortener.id
  stage_name    = "prod"
}

output "api_gateway_invoke_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "simple_html_page_url" {
    description = "url of the bucket"
    value = "http://${aws_s3_bucket.url_shortener_bucket.bucket}.s3-website-${data.aws_region.current.name}.amazonaws.com"
}

output "s3_bucket_name" {
    description = "name of the bucket"
    value = aws_s3_bucket.url_shortener_bucket.bucket
}