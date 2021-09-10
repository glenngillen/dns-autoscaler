terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  alias  = "dns-us-east-1"
  region = "us-east-1"
}


data "aws_route53_zone" "this" {
  name         = var.zone_name
}

resource "aws_cloudwatch_log_group" "scale-logs" {
  provider = aws.dns-us-east-1
  name              = "/aws/route53/${data.aws_route53_zone.this.name}"
  retention_in_days = 1
}

data "aws_iam_policy_document" "route53-query-logging-policy" {
  provider = aws.dns-us-east-1
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["arn:aws:logs:*:*:log-group:/aws/route53/*"]

    principals {
      identifiers = ["route53.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "route53-query-logging-policy" {
  provider = aws.dns-us-east-1

  policy_document = data.aws_iam_policy_document.route53-query-logging-policy.json
  policy_name     = "route53-query-logging-policy"
}

resource "aws_route53_query_log" "this" {
  provider = aws.dns-us-east-1
  depends_on = [aws_cloudwatch_log_resource_policy.route53-query-logging-policy]

  cloudwatch_log_group_arn = aws_cloudwatch_log_group.scale-logs.arn
  zone_id                  = data.aws_route53_zone.this.zone_id
}

resource "aws_cloudwatch_log_subscription_filter" "autoscaler-filter" {
  provider = aws.dns-us-east-1
  depends_on = [
    aws_cloudwatch_log_group.scale-logs
  ]
  name            = "filter-${var.domain_name}"
  log_group_name  = aws_cloudwatch_log_group.scale-logs.name
  filter_pattern  = var.domain_name
  destination_arn = aws_lambda_function.dns-autoscaler.arn
}

data "archive_file" "dns-autoscaler" {
    type = "zip"
    output_path = "${path.root}/.terraform/tmp/dns-autoscaler.zip"
    source {
        content  = <<EOF
import os
import boto3

ASG = os.environ.get('ASG_NAME')
CAPACITY = int(os.environ.get('CAPACITY'))
REGION = os.environ.get('ASG_REGION')

def lambda_handler(event, context):
    """Updates the desired count for a service."""

    asg = boto3.client('autoscaling', region_name=REGION)
    response = asg.describe_auto_scaling_groups(
        AutoScalingGroupNames=[ASG]
    )

    desired = response["AutoScalingGroups"][0]["DesiredCapacity"]

    if desired < CAPACITY:
        response = asg.set_desired_capacity(
    		AutoScalingGroupName=ASG,
    		DesiredCapacity=CAPACITY
	)
        print("Updated desired capacity to " + str(CAPACITY))
    else:
        print("Desired capacity already >= " + str(CAPACITY))
EOF
    filename = "handler.py"
  }
}

resource "random_id" "id" {
  byte_length = 8
}
data "aws_autoscaling_group" "this" {
  name = var.autoscaling_group_name
}
resource "aws_iam_role" "lambda" {
  provider = aws.dns-us-east-1
  name = "lambda-${random_id.id.hex}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}
resource "aws_iam_role_policy" "lambda" {
  provider = aws.dns-us-east-1
  name = "lambda-${random_id.id.hex}"
  role = aws_iam_role.lambda.id
  policy = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
   {
      "Effect": "Allow",
      "Action": [        
          "autoscaling:UpdateAutoScalingGroup"
      ],
      "Resource": "${data.aws_autoscaling_group.this.arn}"
   },
   {
      "Effect": "Allow",
      "Action": [
          "autoscaling:DescribeAutoScalingGroups"
      ],
      "Resource": "*"
   }]
}
EOF
}



resource "aws_lambda_permission" "allow-cloudwatch" {
  provider = aws.dns-us-east-1
  statement_id  = "dns-autoscaler-allow-cloudwatch-${replace(var.domain_name, ".", "-")}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dns-autoscaler.function_name
  principal     = format("logs.%v.amazonaws.com", "us-east-1")
  source_arn    = "${aws_cloudwatch_log_group.scale-logs.arn}:*"
}

resource "aws_lambda_function" "dns-autoscaler" {
  provider = aws.dns-us-east-1
  function_name = "dns-autoscaler-${random_id.id.hex}"
  role = aws_iam_role.lambda.arn
  handler = "handler.lambda_handler"
  runtime = "python3.8"
  timeout = 15
  environment {
    variables = {
      "ASG_REGION" = var.asg_region,
      "CAPACITY"   = var.scale_to,
      "ASG_NAME"   = var.autoscaling_group_name
    }
    
  }

  filename         = "${data.archive_file.dns-autoscaler.output_path}"
  source_code_hash = "${data.archive_file.dns-autoscaler.output_base64sha256}"
}