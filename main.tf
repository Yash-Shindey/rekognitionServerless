terraform {
 required_providers {
   aws = {
     source  = "hashicorp/aws"
     version = "~> 4.0"
   }
 }
 
 backend "s3" {
   bucket = "image-gallery-terraform-state"
   key    = "terraform.tfstate"
   region = "ap-south-1"
 }
}

provider "aws" {
 region = "ap-south-1"
}

# Random suffix for unique naming
resource "random_id" "suffix" {
 byte_length = 4
}

# S3 bucket for image storage
resource "aws_s3_bucket" "image_storage" {
 bucket = "image-gallery-storage-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_versioning" "image_storage" {
 bucket = aws_s3_bucket.image_storage.id
 versioning_configuration {
   status = "Enabled"
 }
}

# Remove the public access block
resource "aws_s3_bucket_public_access_block" "image_storage" {
  bucket = aws_s3_bucket.image_storage.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Add a public read bucket policy
resource "aws_s3_bucket_policy" "allow_public_read" {
  bucket = aws_s3_bucket.image_storage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.image_storage.arn}/*"
      },
    ]
  })
}


resource "aws_s3_bucket_cors_configuration" "image_storage" {
 bucket = aws_s3_bucket.image_storage.id

 cors_rule {
   allowed_headers = ["*"]
   allowed_methods = ["GET", "PUT", "POST"]
   allowed_origins = ["*"]  # TODO: Replace with your domain in production
   expose_headers  = ["ETag"]
   max_age_seconds = 3000
 }
}

# DynamoDB table for image metadata
resource "aws_dynamodb_table" "image_metadata" {
 name           = "ImageMetadata"
 billing_mode   = "PAY_PER_REQUEST"
 hash_key       = "imageId"
 range_key      = "uploadDate"

 attribute {
   name = "imageId"
   type = "S"
 }

 attribute {
   name = "uploadDate"
   type = "S"
 }

 attribute {
   name = "searchableTerms"
   type = "S"
 }

 global_secondary_index {
   name               = "SearchableTermsIndex"
   hash_key           = "searchableTerms"
   range_key         = "uploadDate"
   projection_type    = "ALL"
 }

 tags = {
   Environment = "dev"
   Project     = "image-gallery"
 }
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
 name = "image_processor_lambda_role"

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

# IAM policy for Lambda functions
resource "aws_iam_role_policy" "lambda_policy" {
 name = "image_processor_policy"
 role = aws_iam_role.lambda_role.id

 policy = jsonencode({
   Version = "2012-10-17"
   Statement = [
     {
       Effect = "Allow"
       Action = [
         "s3:GetObject",
         "s3:PutObject",
         "s3:ListBucket",
         "dynamodb:PutItem",
         "dynamodb:GetItem",
         "dynamodb:Query",
         "rekognition:DetectLabels",  # Add this
          "rekognition:DetectText",
         "dynamodb:UpdateItem"
       ]
       Resource = [
         aws_s3_bucket.image_storage.arn,
          "${aws_s3_bucket.image_storage.arn}/*",
          aws_dynamodb_table.image_metadata.arn,
          "arn:aws:logs:*:*:*",
          "*"  # For rekognition
       ]
     },
     {
       Effect = "Allow"
       Action = [
         "rekognition:DetectLabels",
         "rekognition:DetectText"
       ]
       Resource = "*"
     },
     {
       Effect = "Allow"
       Action = [
         "logs:CreateLogGroup",
         "logs:CreateLogStream",
         "logs:PutLogEvents"
       ]
       Resource = ["arn:aws:logs:*:*:*"]
     }
   ]
 })
}

# Lambda function for image processing
resource "aws_lambda_function" "image_processor" {
 filename         = "image-processor.zip"
 function_name    = "image-processor"
 role            = aws_iam_role.lambda_role.arn
 handler         = "index.handler"
 runtime         = "python3.9"
 timeout         = 30
 memory_size     = 256

 environment {
   variables = {
     DYNAMODB_TABLE = aws_dynamodb_table.image_metadata.name
   }
 }
}

# Add Rekognition full access to the Lambda role
resource "aws_iam_role_policy_attachment" "rekognition_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRekognitionFullAccess"
}

# Ensure S3 can invoke Lambda
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.image_storage.arn
}
# Ensure correct event notification setup
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.image_storage.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}
# API Handler Lambda Role
resource "aws_iam_role" "api_handler_lambda_role" {
  name = "api_handler_lambda_role"

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

resource "aws_iam_role_policy_attachment" "api_handler_basic" {
  role       = aws_iam_role.api_handler_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "api_handler_permissions" {
  name = "api_handler_permissions"
  role = aws_iam_role.api_handler_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          "${aws_s3_bucket.image_storage.arn}/*",
          aws_dynamodb_table.image_metadata.arn,
          "${aws_dynamodb_table.image_metadata.arn}/index/*"
        ]
      }
    ]
  })
}

# API Handler Lambda Function
data "archive_file" "api_handler" {
  type        = "zip"
  source_dir  = "${path.module}/src/functions/api-handler"
  output_path = "${path.module}/api_handler.zip"
}

resource "aws_lambda_function" "api_handler" {
  filename         = data.archive_file.api_handler.output_path
  function_name    = "image-gallery-api-handler"
  role            = aws_iam_role.api_handler_lambda_role.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 30
  memory_size     = 128

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.image_metadata.name
      S3_BUCKET     = aws_s3_bucket.image_storage.id
      REGION        = data.aws_region.current.name
    }
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "image_gallery" {
  name        = "image-gallery-api"
  description = "Image Gallery API"
}

# API Resources
resource "aws_api_gateway_resource" "images" {
  rest_api_id = aws_api_gateway_rest_api.image_gallery.id
  parent_id   = aws_api_gateway_rest_api.image_gallery.root_resource_id
  path_part   = "images"
}

resource "aws_api_gateway_resource" "image" {
  rest_api_id = aws_api_gateway_rest_api.image_gallery.id
  parent_id   = aws_api_gateway_resource.images.id
  path_part   = "{imageId}"
}

resource "aws_api_gateway_resource" "search" {
  rest_api_id = aws_api_gateway_rest_api.image_gallery.id
  parent_id   = aws_api_gateway_rest_api.image_gallery.root_resource_id
  path_part   = "search"
}

# Methods
resource "aws_api_gateway_method" "post_images" {
  rest_api_id   = aws_api_gateway_rest_api.image_gallery.id
  resource_id   = aws_api_gateway_resource.images.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "get_image" {
  rest_api_id   = aws_api_gateway_rest_api.image_gallery.id
  resource_id   = aws_api_gateway_resource.image.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "search_images" {
  rest_api_id   = aws_api_gateway_rest_api.image_gallery.id
  resource_id   = aws_api_gateway_resource.search.id
  http_method   = "GET"
  authorization = "NONE"
}

# Integrations
resource "aws_api_gateway_integration" "post_images" {
  rest_api_id             = aws_api_gateway_rest_api.image_gallery.id
  resource_id             = aws_api_gateway_resource.images.id
  http_method             = aws_api_gateway_method.post_images.http_method
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.api_handler.invoke_arn
}

resource "aws_api_gateway_integration" "get_image" {
  rest_api_id             = aws_api_gateway_rest_api.image_gallery.id
  resource_id             = aws_api_gateway_resource.image.id
  http_method             = aws_api_gateway_method.get_image.http_method
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.api_handler.invoke_arn
}

resource "aws_api_gateway_integration" "search_images" {
  rest_api_id             = aws_api_gateway_rest_api.image_gallery.id
  resource_id             = aws_api_gateway_resource.search.id
  http_method             = aws_api_gateway_method.search_images.http_method
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.api_handler.invoke_arn
}

# Lambda Permission
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.image_gallery.execution_arn}/*/*/*"
}

# Deployment
resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.image_gallery.id
  
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.images,
      aws_api_gateway_resource.image,
      aws_api_gateway_resource.search,
      aws_api_gateway_method.post_images,
      aws_api_gateway_method.get_image,
      aws_api_gateway_method.search_images,
      aws_api_gateway_integration.post_images,
      aws_api_gateway_integration.get_image,
      aws_api_gateway_integration.search_images,
      aws_api_gateway_integration.images_options,
      aws_api_gateway_integration_response.images_options
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.post_images,
    aws_api_gateway_method.get_image,
    aws_api_gateway_method.search_images,
    aws_api_gateway_integration.post_images,
    aws_api_gateway_integration.get_image,
    aws_api_gateway_integration.search_images,
    aws_api_gateway_integration.images_options,
    aws_api_gateway_integration_response.images_options,
    aws_api_gateway_integration.image_options,
    aws_api_gateway_integration_response.image_options,
    aws_api_gateway_integration.search_options,
    aws_api_gateway_integration_response.search_options
  ]
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.prod.id
  rest_api_id   = aws_api_gateway_rest_api.image_gallery.id
  stage_name    = "prod"

  depends_on = [aws_cloudwatch_log_group.api_gateway]
}

# Enable CORS for images endpoint
resource "aws_api_gateway_method" "images_options" {
  rest_api_id   = aws_api_gateway_rest_api.image_gallery.id
  resource_id   = aws_api_gateway_resource.images.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "images_options" {
  rest_api_id = aws_api_gateway_rest_api.image_gallery.id
  resource_id = aws_api_gateway_resource.images.id
  http_method = aws_api_gateway_method.images_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = <<EOF
{
  "statusCode": 200,
  "headers": {
    "Access-Control-Allow-Headers": "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "Access-Control-Allow-Methods": "'OPTIONS,POST,GET'",
    "Access-Control-Allow-Origin": "'*'"
  }
}
EOF
  }
}

resource "aws_api_gateway_method_response" "images_options_200" {
  rest_api_id = aws_api_gateway_rest_api.image_gallery.id
  resource_id = aws_api_gateway_resource.images.id
  http_method = aws_api_gateway_method.images_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "images_options" {
  rest_api_id = aws_api_gateway_rest_api.image_gallery.id
  resource_id = aws_api_gateway_resource.images.id
  http_method = aws_api_gateway_method.images_options.http_method
  status_code = aws_api_gateway_method_response.images_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST,GET'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [
    aws_api_gateway_method_response.images_options_200,
    aws_api_gateway_integration.images_options
  ]
}

# Enable CORS for single image endpoint
resource "aws_api_gateway_method" "image_options" {
  rest_api_id   = aws_api_gateway_rest_api.image_gallery.id
  resource_id   = aws_api_gateway_resource.image.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "image_options" {
  rest_api_id = aws_api_gateway_rest_api.image_gallery.id
  resource_id = aws_api_gateway_resource.image.id
  http_method = aws_api_gateway_method.image_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "image_options_200" {
  rest_api_id = aws_api_gateway_rest_api.image_gallery.id
  resource_id = aws_api_gateway_resource.image.id
  http_method = aws_api_gateway_method.image_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "image_options" {
  rest_api_id = aws_api_gateway_rest_api.image_gallery.id
  resource_id = aws_api_gateway_resource.image.id
  http_method = aws_api_gateway_method.image_options.http_method
  status_code = aws_api_gateway_method_response.image_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Enable CORS for search endpoint
resource "aws_api_gateway_method" "search_options" {
  rest_api_id   = aws_api_gateway_rest_api.image_gallery.id
  resource_id   = aws_api_gateway_resource.search.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "search_options" {
  rest_api_id = aws_api_gateway_rest_api.image_gallery.id
  resource_id = aws_api_gateway_resource.search.id
  http_method = aws_api_gateway_method.search_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "search_options_200" {
  rest_api_id = aws_api_gateway_rest_api.image_gallery.id
  resource_id = aws_api_gateway_resource.search.id
  http_method = aws_api_gateway_method.search_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "search_options" {
  rest_api_id = aws_api_gateway_rest_api.image_gallery.id
  resource_id = aws_api_gateway_resource.search.id
  http_method = aws_api_gateway_method.search_options.http_method
  status_code = aws_api_gateway_method_response.search_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Create CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/image-gallery-api"
  retention_in_days = 7
}

# CloudWatch Logs configuration
resource "aws_iam_role" "cloudwatch" {
  name = "api_gateway_cloudwatch_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

# Attach the CloudWatch policy
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# Set up API Gateway account settings
resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.cloudwatch.arn
  depends_on = [aws_iam_role_policy_attachment.cloudwatch]
}

# Enable logging for the stage
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.image_gallery.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  depends_on = [aws_api_gateway_account.main]

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}


# Add new output for API Gateway URL
output "api_gateway_url" {
  value = "${aws_api_gateway_stage.prod.invoke_url}"
  description = "API Gateway deployment URL"
}

# Current AWS region and account ID
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Outputs
output "s3_bucket_name" {
 value = aws_s3_bucket.image_storage.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.image_metadata.name
}

output "lambda_role_arn" {
 value = aws_iam_role.lambda_role.arn
}
