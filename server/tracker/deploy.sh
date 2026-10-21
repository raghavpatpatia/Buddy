#!/usr/bin/env bash
# Deploys Buddy's read-receipt tracker to your AWS account (free tier): DynamoDB table + Lambda + public function URL.
# Then writes the URL + a random read key to the phone (Download/buddy_tracker.txt), which Buddy imports and deletes.
set -euo pipefail
REGION="${REGION:-ap-south-1}"
NAME=buddy-mail-tracker
TABLE=buddy-mail-opens
cd "$(dirname "$0")"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo "Deploying to account $ACCOUNT in $REGION"

aws dynamodb describe-table --table-name $TABLE --region $REGION >/dev/null 2>&1 || {
  aws dynamodb create-table --region $REGION --table-name $TABLE \
    --attribute-definitions AttributeName=id,AttributeType=S --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
  aws dynamodb wait table-exists --region $REGION --table-name $TABLE
  aws dynamodb update-time-to-live --region $REGION --table-name $TABLE --time-to-live-specification Enabled=true,AttributeName=expires >/dev/null
}

ROLE_ARN=$(aws iam get-role --role-name $NAME-role --query Role.Arn --output text 2>/dev/null || true)
if [ -z "$ROLE_ARN" ]; then
  ROLE_ARN=$(aws iam create-role --role-name $NAME-role --query Role.Arn --output text \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}')
  sleep 10 # IAM propagation
fi
aws iam put-role-policy --role-name $NAME-role --policy-name table-and-logs --policy-document "{
  \"Version\":\"2012-10-17\",\"Statement\":[
   {\"Effect\":\"Allow\",\"Action\":[\"dynamodb:UpdateItem\",\"dynamodb:BatchGetItem\"],\"Resource\":\"arn:aws:dynamodb:$REGION:$ACCOUNT:table/$TABLE\"},
   {\"Effect\":\"Allow\",\"Action\":[\"logs:CreateLogGroup\",\"logs:CreateLogStream\",\"logs:PutLogEvents\"],\"Resource\":\"*\"}]}"

KEY=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40)
zip -q -j /tmp/$NAME.zip lambda_function.py
if aws lambda get-function --function-name $NAME --region $REGION >/dev/null 2>&1; then
  aws lambda update-function-code --function-name $NAME --region $REGION --zip-file fileb:///tmp/$NAME.zip >/dev/null
  aws lambda wait function-updated --function-name $NAME --region $REGION
  aws lambda update-function-configuration --function-name $NAME --region $REGION --environment "Variables={TABLE=$TABLE,KEY=$KEY}" >/dev/null
else
  for i in 1 2 3 4 5; do
    aws lambda create-function --function-name $NAME --region $REGION --runtime python3.13 --handler lambda_function.handler \
      --role "$ROLE_ARN" --zip-file fileb:///tmp/$NAME.zip --timeout 10 --memory-size 128 \
      --environment "Variables={TABLE=$TABLE,KEY=$KEY}" >/dev/null && break
    echo "waiting for IAM role…"; sleep 8
  done
fi
aws lambda wait function-updated --function-name $NAME --region $REGION

URL=$(aws lambda get-function-url-config --function-name $NAME --region $REGION --query FunctionUrl --output text 2>/dev/null || true)
if [ -z "$URL" ] || [ "$URL" = "None" ]; then
  URL=$(aws lambda create-function-url-config --function-name $NAME --region $REGION --auth-type NONE --query FunctionUrl --output text)
fi
aws lambda add-permission --function-name $NAME --region $REGION --statement-id public-url --action lambda:InvokeFunctionUrl \
  --principal '*' --function-url-auth-type NONE >/dev/null 2>&1 || true
aws lambda add-permission --function-name $NAME --region $REGION --statement-id public-invoke-via-url --action lambda:InvokeFunction \
  --principal '*' --invoked-via-function-url >/dev/null 2>&1 || true
URL=${URL%/}
echo "Tracker URL: $URL"
echo "$URL|$KEY" > /tmp/buddy_tracker.txt
echo "Setup file ready: /tmp/buddy_tracker.txt"
