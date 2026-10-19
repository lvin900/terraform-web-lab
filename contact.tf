# contact.tf - serverless contact form.
#
# Flow: browser form -> API Gateway (HTTP API) -> Lambda -> SNS -> your email.
# Reuses var.alert_email and the Lambda trust policy defined in events.tf.

# 1. Where messages go: a separate SNS topic, so contact messages and
#    compliance alerts can be routed or muted independently.
resource "aws_sns_topic" "contact" {
  name = "website-contact-messages"
}

resource "aws_sns_topic_subscription" "contact_email" {
  topic_arn = aws_sns_topic.contact.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# 2. The function's identity: can only write logs and publish to this one topic.
resource "aws_iam_role" "contact" {
  name               = "contact-form-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "contact_logs" {
  role       = aws_iam_role.contact.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "contact" {
  statement {
    sid       = "PublishContactMessages"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.contact.arn]
  }
}

resource "aws_iam_role_policy" "contact" {
  name   = "contact-form-permissions"
  role   = aws_iam_role.contact.id
  policy = data.aws_iam_policy_document.contact.json
}

# 3. The function.
data "archive_file" "contact" {
  type        = "zip"
  source_file = "${path.module}/lambda/contact.py"
  output_path = "${path.module}/build/contact.zip"
}

resource "aws_cloudwatch_log_group" "contact" {
  name              = "/aws/lambda/contact-form"
  retention_in_days = 7
}

resource "aws_lambda_function" "contact" {
  function_name    = "contact-form"
  role             = aws_iam_role.contact.arn
  runtime          = "python3.12"
  handler          = "contact.handler"
  filename         = data.archive_file.contact.output_path
  source_code_hash = data.archive_file.contact.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TOPIC_ARN = aws_sns_topic.contact.arn
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.contact,
    aws_iam_role_policy_attachment.contact_logs,
  ]
}

# 4. The public HTTPS endpoint the web page calls.
resource "aws_apigatewayv2_api" "contact" {
  name          = "contact-form-api"
  protocol_type = "HTTP"

  # CORS: lets a browser on another origin (your web server) call this API.
  # "*" because the server's IP changes on replacement; with a domain name you would list it here.
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST"]
    allow_headers = ["content-type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "contact" {
  api_id                 = aws_apigatewayv2_api.contact.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.contact.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "contact" {
  api_id    = aws_apigatewayv2_api.contact.id
  route_key = "POST /contact"
  target    = "integrations/${aws_apigatewayv2_integration.contact.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.contact.id
  name        = "$default"
  auto_deploy = true

  # Throttling: at most 1 request per second on average, bursts of 5.
  # Stops a bot from flooding your inbox or running up costs.
  default_route_settings {
    throttling_burst_limit = 5
    throttling_rate_limit  = 1
  }
}

# Resource-based policy: only this API may invoke the function.
resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contact.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.contact.execution_arn}/*/*"
}

output "contact_api_url" {
  description = "The API endpoint the contact form posts to"
  value       = "${aws_apigatewayv2_api.contact.api_endpoint}/contact"
}
