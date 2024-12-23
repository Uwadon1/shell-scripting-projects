#!/bin/bash

set -e  # Exit on any command failure
set -x  # Enable debugging

# Variables (use the same names and conventions from the setup script)
role_name="s3-lambda-sns"
bucket_name="abhishek-ultimate-bucket-*"
lambda_function_name="s3-lambda-function"
sns_topic_name="s3-event-notifications"
region="us-east-1"

# Delete the Lambda function
if aws lambda get-function --function-name $lambda_function_name >/dev/null 2>&1; then
  echo "Deleting Lambda function: $lambda_function_name"
  aws lambda delete-function --function-name $lambda_function_name
else
  echo "Lambda function $lambda_function_name does not exist."
fi

# Delete S3 bucket and objects
if buckets=$(aws s3api list-buckets --query "Buckets[?contains(Name, \`abhishek-ultimate-bucket-\`) == \`true\`].Name" --output text); then
  for bucket in $buckets; do
    echo "Deleting all objects from S3 bucket: $bucket"
    aws s3 rm s3://$bucket --recursive
    echo "Deleting S3 bucket: $bucket"
    aws s3api delete-bucket --bucket $bucket
  done
else
  echo "No matching S3 buckets found."
fi

# Delete SNS topic
if sns_topic_arn=$(aws sns list-topics --query "Topics[?ends_with(TopicArn, \`:$sns_topic_name\`)].TopicArn" --output text); then
  echo "Deleting SNS topic: $sns_topic_name"
  aws sns delete-topic --topic-arn $sns_topic_arn
else
  echo "SNS topic $sns_topic_name does not exist."
fi

# Detach and delete IAM role
if aws iam get-role --role-name $role_name >/dev/null 2>&1; then
  echo "Detaching policies from IAM role: $role_name"
  attached_policies=$(aws iam list-attached-role-policies --role-name $role_name --query "AttachedPolicies[].PolicyArn" --output text)
  for policy in $attached_policies; do
    aws iam detach-role-policy --role-name $role_name --policy-arn $policy
  done

  echo "Deleting IAM role: $role_name"
  aws iam delete-role --role-name $role_name
else
  echo "IAM role $role_name does not exist."
fi

# Cleanup temporary files
if [ -f example_file.txt ]; then
  echo "Removing temporary files."
  rm -f example_file.txt
fi

if [ -f s3-lambda-function.zip ]; then
  rm -f s3-lambda-function.zip
fi

if [ -d s3-lambda-function ]; then
  rm -rf s3-lambda-function
fi

echo "All resources cleaned up successfully."
