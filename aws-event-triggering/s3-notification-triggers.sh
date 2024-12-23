#!/bin/bash

set -e  # Exit on any command failure
set -x  # Enable debugging

# Ensure dependencies
command -v jq >/dev/null 2>&1 || { echo "jq is not installed. Exiting."; exit 1; }
command -v zip >/dev/null 2>&1 || { echo "zip is not installed. Exiting."; exit 1; }

# Variables
role_name="s3-lambda-sns"
bucket_name="abhishek-ultimate-bucket-$(date +%s)"
lambda_function_name="s3-lambda-function"
sns_topic_name="s3-event-notifications"
subscription_email="ig0gwpnrd0@wywnxa.com"  # Replace with actual email
zip_file="s3-lambda-function.zip"
region="us-east-1"

# Create or fetch IAM Role
if ! role_arn=$(aws iam get-role --role-name $role_name --query 'Role.Arn' --output text 2>/dev/null); then
  echo "Creating IAM role..."
  role_arn=$(aws iam create-role --role-name $role_name \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
    --query 'Role.Arn' --output text)
fi
echo "Role ARN: $role_arn"

# Attach policies
aws iam attach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess
aws iam attach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess
aws iam attach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# Create S3 bucket
if ! aws s3api head-bucket --bucket $bucket_name 2>/dev/null; then
  echo "Creating S3 bucket: $bucket_name"
  aws s3api create-bucket --bucket $bucket_name --region $region
else
  echo "Bucket $bucket_name already exists."
fi

# Create SNS Topic
sns_topic_arn=$(aws sns create-topic --name $sns_topic_name --query 'TopicArn' --output text)
echo "Created SNS Topic: $sns_topic_arn"

# Subscribe email to SNS Topic
aws sns subscribe --topic-arn $sns_topic_arn --protocol email --notification-endpoint $subscription_email
echo "Email subscription created. Please check your email ($subscription_email) and confirm the subscription."

# Add Bucket Permissions for SNS
sns_topic_policy='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "SNS:Publish",
      "Resource": "'"$sns_topic_arn"'",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:s3:::'"$bucket_name"'"
        }
      }
    }
  ]
}'
aws sns set-topic-attributes \
  --topic-arn "
