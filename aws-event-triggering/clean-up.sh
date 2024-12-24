#!/bin/bash

set -x

# Set AWS region and bucket name
aws_region="us-east-1"
bucket_name="abhishek-ultimate-bucket-$(date +%s)"  # Use the actual bucket name created earlier
lambda_func_name="s3-lambda-function"
role_name="s3-lambda-sns"
email_address="zyz@gmail.com"

# Get the AWS account ID
aws_account_id=$(aws sts get-caller-identity --query 'Account' --output text)

# Detach policies from IAM role
aws iam detach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess
aws iam detach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess
aws iam detach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# Delete Lambda function
aws lambda delete-function --function-name $lambda_func_name
echo "Lambda function $lambda_func_name deleted."

# Delete the S3 bucket notification
aws s3api put-bucket-notification-configuration --bucket "$bucket_name" --notification-configuration '{}'
echo "S3 bucket notification removed."

# Delete the SNS subscription
aws sns unsubscribe --subscription-arn "$(aws sns list-subscriptions-by-topic --topic-arn "$topic_arn" --query 'Subscriptions[0].SubscriptionArn' --output text)"
echo "SNS subscription deleted."

# Delete SNS topic
aws sns delete-topic --topic-arn "$topic_arn"
echo "SNS topic $topic_arn deleted."

# Delete the S3 bucket
aws s3 rm s3://"$bucket_name" --recursive
aws s3api delete-bucket --bucket "$bucket_name" --region "$aws_region"
echo "S3 bucket $bucket_name deleted."

# Delete IAM Role
aws iam delete-role --role-name $role_name
echo "IAM role $role_name deleted."

# Done with cleanup
echo "Cleanup completed."
