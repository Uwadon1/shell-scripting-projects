#!/bin/bash

set -e  # Exit on any command failure
set -x  # Enable debugging

# Variables
role_name="s3-lambda-sns"
bucket_name="abhishek-ultimate-bucket-$(date +%s)" # Adjust bucket name dynamically if required
lambda_function_name="s3-lambda-function"
region="us-east-1"

# Delete Lambda Function
if aws lambda get-function --function-name $lambda_function_name >/dev/null 2>&1; then
  echo "Deleting Lambda function: $lambda_function_name"
  aws lambda delete-function --function-name $lambda_function_name
else
  echo "Lambda function $lambda_function_name does not exist."
fi

# Empty and delete S3 bucket
if aws s3api head-bucket --bucket $bucket_name 2>/dev/null; then
  echo "Emptying S3 bucket: $bucket_name"
  aws s3 rm s3://$bucket_name --recursive
  
  echo "Deleting S3 bucket: $bucket_name"
  aws s3api delete-bucket --bucket $bucket_name
else
  echo "S3 bucket $bucket_name does not exist."
fi

# Detach policies and delete IAM role
if aws iam get-role --role-name $role_name >/dev/null 2>&1; then
  echo "Detaching policies from IAM role: $role_name"
  aws iam detach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess
  aws iam detach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess
  aws iam detach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

  echo "Deleting IAM role: $role_name"
  aws iam delete-role --role-name $role_name
else
  echo "IAM role $role_name does not exist."
fi

# Clean up local files
echo "Cleaning up local files..."
rm -f example_file.txt $zip_file
rm -rf s3-lambda-function

echo "Clean-up complete."
