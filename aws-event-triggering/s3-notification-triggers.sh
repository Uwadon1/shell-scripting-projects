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

# Upload test file
echo "Sample file content" > example_file.txt
aws s3 cp example_file.txt s3://$bucket_name/example_file.txt

# Create Lambda function zip
mkdir -p s3-lambda-function
echo "def lambda_handler(event, context): print(event)" > s3-lambda-function/lambda_function.py
zip -r $zip_file ./s3-lambda-function

# Create Lambda function
if ! aws lambda get-function --function-name $lambda_function_name 2>/dev/null; then
  echo "Creating Lambda function..."
  aws lambda create-function --region $region --function-name $lambda_function_name \
    --runtime python3.8 --handler lambda_function.lambda_handler \
    --role $role_arn --zip-file fileb://./$zip_file
fi

# Add bucket permissions for Lambda
aws lambda add-permission --function-name $lambda_function_name \
  --statement-id AllowS3Invoke --action lambda:InvokeFunction \
  --principal s3.amazonaws.com --source-arn "arn:aws:s3:::$bucket_name"

# Set S3 bucket notification
aws s3api put-bucket-notification-configuration --bucket $bucket_name --notification-configuration "{
  \"LambdaFunctionConfigurations\": [{
    \"LambdaFunctionArn\": \"arn:aws:lambda:$region:$(aws sts get-caller-identity --query Account --output text):function:$lambda_function_name\",
    \"Events\": [\"s3:ObjectCreated:*\"
    ]
  }]
}"
