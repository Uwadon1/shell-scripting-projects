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

# Prompt for SNS Topic ARN (This is your SNS ARN, you can skip the input if you've already created it)
read -p "Please enter your SNS Topic ARN (or press Enter to create a new SNS Topic): " sns_topic_arn

if [ -z "$sns_topic_arn" ]; then
  # Create SNS Topic if the ARN is not provided
  sns_topic_arn=$(aws sns create-topic --name $sns_topic_name --query 'TopicArn' --output text)
  echo "Created SNS Topic: $sns_topic_arn"
fi

# Subscribe email to SNS Topic
aws sns subscribe --topic-arn $sns_topic_arn --protocol email --notification-endpoint $subscription_email
echo "Email subscription created. Please check your email ($subscription_email) and confirm the subscription."

# Create or fetch IAM Role
if ! role_arn=$(aws iam get-role --role-name $role_name --query 'Role.Arn' --output text 2>/dev/null); then
  echo "Creating IAM role..."
  role_arn=$(aws iam create-role --role-name $role_name \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
    --query 'Role.Arn' --output text)
fi
echo "Role ARN: $role_arn"

# Attach policies to IAM Role
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

# Add Bucket Permissions for SNS
bucket_policy=$(cat <<EOM
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sns:Publish",
      "Resource": "$sns_topic_arn"
    }
  ]
}
EOM
)
aws s3api put-bucket-policy --bucket $bucket_name --policy "$bucket_policy"

# Set S3 bucket notification for SNS
aws s3api put-bucket-notification-configuration --bucket $bucket_name --notification-configuration "{
  \"TopicConfigurations\": [{
    \"TopicArn\": \"$sns_topic_arn\",
    \"Events\": [\"s3:ObjectCreated:*\"]
  }]
}"

# Lambda function creation (Make sure this is immediately before uploading to Lambda)
echo "Creating Lambda function..."

mkdir -p s3-lambda-function
cat <<EOM > s3-lambda-function/lambda_function.py
import boto3
import json

def lambda_handler(event, context):
    # Extract relevant information from the S3 event trigger
    bucket_name = event['Records'][0]['s3']['bucket']['name']
    object_key = event['Records'][0]['s3']['object']['key']

    # Perform desired operations with the uploaded file
    print(f"File '{object_key}' was uploaded to bucket '{bucket_name}'")

    # Example: Send a notification via SNS
    sns_client = boto3.client('sns')
    topic_arn = '$sns_topic_arn'  # SNS Topic ARN dynamically injected
    sns_client.publish(
       TopicArn=topic_arn,
       Subject='S3 Object Created',
       Message=f"File '{object_key}' was uploaded to bucket '{bucket_name}'"
    )

    return {
        'statusCode': 200,
        'body': json.dumps('Lambda function executed successfully')
    }
EOM

zip -r $zip_file ./s3-lambda-function

# Create Lambda function
lambda_creation_output=$(aws lambda create-function --region $region --function-name $lambda_function_name \
  --runtime python3.8 --handler lambda_function.lambda_handler --role $role_arn --zip-file fileb://./$zip_file 2>&1)

# Check if Lambda was successfully created
if echo "$lambda_creation_output" | grep -q 'FunctionArn'; then
  echo "Lambda function created successfully"
else
  echo "Lambda creation failed: $lambda_creation_output"
  exit 1
fi

# Add Lambda permission to trigger from S3
aws lambda add-permission --function-name $lambda_function_name \
  --statement-id AllowS3Invoke --action lambda:InvokeFunction \
  --principal s3.amazonaws.com --source-arn "arn:aws:s3:::$bucket_name"

# Final success message
echo "Setup complete. Lambda function is now ready for SNS-triggered execution."

# Upload test file
echo "Sample file content" > example_file.txt
aws s3 cp example_file.txt s3://$bucket_name/example_file.txt
