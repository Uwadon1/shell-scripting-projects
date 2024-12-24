#!/bin/bash

set -x

# Set AWS region and bucket name
aws_region="us-east-1"
bucket_name="abhishek-ultimate-bucket-$(date +%s)"  # Unique bucket name to avoid conflict
lambda_func_name="s3-lambda-function"
role_name="s3-lambda-sns"
email_address="zyz@gmail.com"

# Get the AWS account ID
aws_account_id=$(aws sts get-caller-identity --query 'Account' --output text)

# Create IAM Role for the project
role_response=$(aws iam create-role --role-name $role_name --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Action": "sts:AssumeRole",
    "Effect": "Allow",
    "Principal": {
      "Service": [
        "lambda.amazonaws.com",
        "s3.amazonaws.com",
        "sns.amazonaws.com"
      ]
    }
  }]
}')

# Extract the role ARN from the JSON response and store it in a variable
role_arn=$(echo "$role_response" | jq -r '.Role.Arn')

# Print the role ARN
echo "Role ARN: $role_arn"

# Wait for IAM role propagation
echo "Waiting for IAM role propagation..."
sleep 10

# Attach Permissions to the Role
aws iam attach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess
aws iam attach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess
aws iam attach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# Create the S3 bucket (no location constraint for us-east-1)
aws s3api create-bucket --bucket "$bucket_name" --region "$aws_region"
if [ $? -eq 0 ]; then
  echo "Bucket created successfully: $bucket_name"
else
  echo "Failed to create bucket. Exiting."
  exit 1
fi

# Enable public access on the bucket
aws s3api put-public-access-block --bucket "$bucket_name" --public-access-block-configuration '{"BlockPublicAcls":false,"IgnorePublicAcls":false,"BlockPublicPolicy":false,"RestrictPublicBuckets":false}'
echo "Public access enabled on the bucket."

# Upload a file to the bucket (ensure the file exists)
if [ -f ./example_file.txt ]; then
  aws s3 cp ./example_file.txt s3://"$bucket_name"/example_file.txt
  echo "File uploaded to S3 bucket."
else
  echo "File 'example_file.txt' does not exist. Please make sure the file is in the current directory."
  exit 1
fi

# Validate the Lambda ZIP file
if [ ! -f ./s3-lambda-function.zip ]; then
  echo "Lambda ZIP file not found. Exiting."
  exit 1
fi

# Create a Zip file to upload Lambda Function
zip -r s3-lambda-function.zip ./s3-lambda-function

sleep 5

# Create the Lambda function
lambda_create_response=$(aws lambda create-function \
  --region "$aws_region" \
  --function-name $lambda_func_name \
  --runtime "python3.8" \
  --handler "s3-lambda-function/s3-lambda-function.lambda_handler" \
  --memory-size 128 \
  --timeout 30 \
  --role "arn:aws:iam::$aws_account_id:role/$role_name" \
  --zip-file "fileb://./s3-lambda-function.zip" 2>&1)

# Check if Lambda creation succeeded
if echo "$lambda_create_response" | grep -q "FunctionName"; then
  echo "Lambda function creation initiated."
else
  echo "Failed to create Lambda function: $lambda_create_response"
  exit 1
fi

# Wait for the Lambda function to become active
lambda_status=""
while [ "$lambda_status" != "Active" ]; do
  echo "Waiting for Lambda function to become active..."
  sleep 10
  lambda_status=$(aws lambda get-function --function-name $lambda_func_name --region "$aws_region" --query 'Configuration.State' --output text 2>/dev/null)
done
echo "Lambda function is now active."

# Add Permissions to S3 Bucket to invoke Lambda
aws lambda add-permission \
  --function-name "$lambda_func_name" \
  --statement-id "s3-lambda-sns" \
  --action "lambda:InvokeFunction" \
  --principal s3.amazonaws.com \
  --source-arn "arn:aws:s3:::$bucket_name"
echo "Permissions added to S3 bucket to invoke Lambda."

# Create an S3 event trigger for the Lambda function
LambdaFunctionArn="arn:aws:lambda:$aws_region:$aws_account_id:function:$lambda_func_name"
aws s3api put-bucket-notification-configuration \
  --region "$aws_region" \
  --bucket "$bucket_name" \
  --notification-configuration "{
    \"LambdaFunctionConfigurations\": [{
        \"LambdaFunctionArn\": \"$LambdaFunctionArn\",
        \"Events\": [\"s3:ObjectCreated:*\"] 
    }]
}"
echo "S3 event notification configured to trigger Lambda."

# Create an SNS topic and save the topic ARN to a variable
topic_arn=$(aws sns create-topic --name s3-lambda-sns --output json | jq -r '.TopicArn')
echo "SNS Topic ARN: $topic_arn"

# Subscribe email to SNS Topic
aws sns subscribe \
  --topic-arn "$topic_arn" \
  --protocol email \
  --notification-endpoint "$email_address"
echo "Email subscription created. Please check your inbox and confirm the subscription."

# Test subscription status
sns_sub_status=$(aws sns list-subscriptions --output json | jq '.Subscriptions[] | select(.Endpoint=="'"$email_address"'")')
echo "SNS Subscription Status: $sns_sub_status"

# Publish a message to SNS
aws sns publish \
  --topic-arn "$topic_arn" \
  --subject "A new object created in s3 bucket" \
  --message "Hello from Abhishek.Veeramalla YouTube channel, Learn DevOps Zero to Hero for Free"
echo "Message published to SNS."

# Script execution complete
echo "Execution completed."
