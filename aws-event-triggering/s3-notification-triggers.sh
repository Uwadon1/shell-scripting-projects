#!/bin/bash

set -x

# Store the AWS account ID in a variable
aws_account_id=$(aws sts get-caller-identity --query 'Account' --output text)

# Print the AWS account ID from the variable
echo "AWS Account ID: $aws_account_id"

# Set AWS region and bucket name
aws_region="us-east-1"
bucket_name="abhishek-ultimate-bucket-$(date +%s)"  # Unique bucket name to avoid conflict
lambda_func_name="s3-lambda-function"
role_name="s3-lambda-sns"
email_address="zyz@gmail.com"

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

# Attach Permissions to the Role
aws iam attach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess
aws iam attach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess
aws iam attach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# Create the S3 bucket
aws s3api create-bucket --bucket "$bucket_name" --region "$aws_region" --create-bucket-configuration LocationConstraint="$aws_region"
echo "Bucket created successfully: $bucket_name"

# Enable public access on the bucket
aws s3api put-public-access-block --bucket $bucket_name --public-access-block-configuration '{"BlockPublicAcls":false,"IgnorePublicAcls":false,"BlockPublicPolicy":false,"RestrictPublicBuckets":false}'
echo "Public access enabled on the bucket."

# Upload a file to the bucket (make sure the file exists in the same directory or update path)
aws s3 cp ./example_file.txt s3://"$bucket_name"/example_file.txt
echo "File uploaded to S3 bucket."

# Zip the Lambda function
if [ -f s3-lambda-function/lambda_function.py ]; then
  zip -r s3-lambda-function.zip ./s3-lambda-function
  echo "Lambda function code zipped successfully."
else
  echo "Lambda function code (lambda_function.py) not found. Exiting."
  exit 1
fi

sleep 5

# Create the Lambda function
aws lambda create-function \
  --region "$aws_region" \
  --function-name $lambda_func_name \
  --runtime "python3.8" \
  --handler "lambda_function.lambda_handler" \
  --memory-size 128 \
  --timeout 30 \
  --role "$role_arn" \
  --zip-file "fileb://./s3-lambda-function.zip"
echo "Lambda function created successfully."

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

# Publish a message to SNS
aws sns publish \
  --topic-arn "$topic_arn" \
  --subject "A new object created in s3 bucket" \
  --message "Hello from my sample project, Learn learning how to trigger events on S2 using event notification"
echo "Message published to SNS."

# Script execution complete
echo "Execution completed."
