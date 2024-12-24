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
subscription_email="your-email@example.com"  # Replace with the desired email
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

# Corrected bucket policy with proper variable substitution
bucket_policy="{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {
      \"Effect\": \"Allow\",
      \"Principal\": \"*\",
      \"Action\": \"s3:PutObject\",
      \"Resource\": \"arn:aws:s3:::$bucket_name/*\"
    }
  ]
}"

# Apply the corrected bucket policy
aws s3api put-bucket-policy --bucket $bucket_name --policy "$bucket_policy"


# Apply bucket policy with the corrected action and resource
aws s3api put-bucket-policy --bucket $bucket_name --policy "$bucket_policy"

# Set S3 bucket notification for SNS
aws s3api put-bucket-notification-configuration --bucket $bucket_name --notification-configuration "{
  \"TopicConfigurations\": [{
    \"TopicArn\": \"$sns_topic_arn\",
    \"Events\": [\"s3:ObjectCreated:*\"]
  }]
}"

# Lambda function creation command with file upload (zip_file must be created earlier)
aws lambda create-function --region $region --function-name $lambda_function_name \
  --runtime python3.8 --handler lambda_function.lambda_handler \
  --role $role_arn --zip-file fileb://./$zip_file

# Upload test file to the bucket
echo "Sample file content" > example_file.txt
aws s3 cp example_file.txt s3://$bucket_name/example_file.txt

echo "Setup complete. Waiting for confirmation email for SNS subscription."
