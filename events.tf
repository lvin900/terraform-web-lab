# events.tf - event-driven tag compliance check.
#
# Flow: EC2 instance enters "running" -> EventBridge rule matches the event
#       -> Lambda function checks the instance's tags
#       -> if a required tag is missing, SNS emails an alert.

variable "alert_email" {
  description = "Email address that receives tag compliance alerts (set it in terraform.tfvars, which Git ignores)"
  type        = string
}

variable "required_tags" {
  description = "Tag keys every EC2 instance must have"
  type        = list(string)
  default     = ["Owner", "Project"]
}

# 1. Where alerts go: an SNS topic with an email subscriber.
resource "aws_sns_topic" "tag_alerts" {
  name = "tag-compliance-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.tag_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# 2. The Lambda's identity: a role only the Lambda service can assume,
#    with only the permissions the function needs (least privilege).
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "tag_checker" {
  name               = "tag-checker-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Lets the function write its logs to CloudWatch Logs.
resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.tag_checker.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "tag_checker" {
  statement {
    sid       = "ReadInstanceTags"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"] # DescribeInstances does not support resource-level restrictions
  }

  statement {
    sid       = "PublishAlerts"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.tag_alerts.arn] # only this one topic
  }
}

resource "aws_iam_role_policy" "tag_checker" {
  name   = "tag-checker-permissions"
  role   = aws_iam_role.tag_checker.id
  policy = data.aws_iam_policy_document.tag_checker.json
}

# 3. The function. Terraform zips the Python file and uploads it.
data "archive_file" "tag_checker" {
  type        = "zip"
  source_file = "${path.module}/lambda/check_tags.py"
  output_path = "${path.module}/build/check_tags.zip"
}

# Created explicitly so logs expire after 7 days instead of being kept forever.
resource "aws_cloudwatch_log_group" "tag_checker" {
  name              = "/aws/lambda/tag-checker"
  retention_in_days = 7
}

resource "aws_lambda_function" "tag_checker" {
  function_name    = "tag-checker"
  role             = aws_iam_role.tag_checker.arn
  runtime          = "python3.12"
  handler          = "check_tags.handler"
  filename         = data.archive_file.tag_checker.output_path
  source_code_hash = data.archive_file.tag_checker.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      REQUIRED_TAGS = join(",", var.required_tags)
      TOPIC_ARN     = aws_sns_topic.tag_alerts.arn
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.tag_checker,
    aws_iam_role_policy_attachment.logs,
  ]
}

# 4. The event: an EventBridge rule that matches any EC2 instance entering "running".
resource "aws_cloudwatch_event_rule" "instance_running" {
  name        = "ec2-instance-running"
  description = "Fires when any EC2 instance enters the running state"

  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
    detail        = { state = ["running"] }
  })
}

# Send matching events to the Lambda function.
resource "aws_cloudwatch_event_target" "tag_checker" {
  rule = aws_cloudwatch_event_rule.instance_running.name
  arn  = aws_lambda_function.tag_checker.arn
}

# Resource-based policy on the function: only this EventBridge rule may invoke it.
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.tag_checker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.instance_running.arn
}
