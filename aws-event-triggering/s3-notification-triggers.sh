#!/bin/bash

# Configuration variables
region="us-east-1"
sns_topic_name="s3-event-notifications"
bucket_name="abhishek-ultimate-bucket-$(date +%s)"
lambda_function_name="process-s3-upload"
zip_file="lambda.zip"
role_arn="arn:aws:iam::181667461225:role/lambda-execution-role"
email="your-email@example.com"

# Create SNS Topic and Get ARN
sns_arn=$(aws sns create-topic --name $sns_topic_name --query 'TopicArn' --output text --region $region)
echo "Created SNS Topic: $sns_arn"

# Create the S3 bucket and configure public access
aws s3api create-bucket --bucket $bucket_name --region $region --create-bucket-configuration LocationConstraint=$region
echo "Created S3 Bucket: $bucket_name"

# Enable public access on the S3 bucket
aws s3api put-bucket-public-access-block --bucket $bucket_name --public-access-block-configuration '{"BlockPublicAcls":false,"IgnorePublicAcls":false,"BlockPublicPolicy":false,"RestrictPublicBuckets":false}'
echo "Public access enabled on the bucket"

# Create the SNS policy for the bucket
bucket_policy="{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {
      \"Effect\": \"Allow\",
      \"Principal\": \"*\",
      \"Action\": \"sns:Publish\",
      \"Resource\": \"$sns_arn\"
    }
  ]
}"

# Set Bucket Policy to Allow SNS Publish
aws s3api put-bucket-policy --bucket $bucket_name --policy "$bucket_policy"
echo "Bucket policy applied."

# Zip the Lambda function code
zip -r $zip_file lambda_function.py
echo "Zipped Lambda function code."

# Create Lambda function
aws lambda create-function --region $region --function-name $lambda_function_name --runtime python3.8 --handler lambda_function.lambda_handler --role $role_arn --zip-file fileb://./$zip_file
echo "Lambda function created successfully."

# Subscribe email to SNS topic
aws sns subscribe --topic-arn $sns_arn --protocol email --notification-endpoint $email
echo "Email subscription created. Please check your inbox and confirm the subscription."

# Set the S3 Bucket notification to trigger Lambda on object upload
aws s3api put-bucket-notification-configuration --bucket $bucket_name --notification-configuration "{\"LambdaFunctionConfigurations\":[{\"LambdaFunctionArn\":\"arn:aws:lambda:$region:181667461225:function:$lambda_function_name\",\"Events\":[\"s3:ObjectCreated:*\"]}]}"
echo "Bucket notification configured to trigger Lambda."

# Final message
echo "Execution completed."
