#!/usr/bin/env bash
# Deploys Buddy's read-receipt tracker (template.yaml) to your AWS account, then uploads src/ as the Lambda code.
# Writes "url|key" to /tmp/buddy_tracker.txt; push it to the phone's Download folder and Buddy imports and deletes it.
set -euo pipefail
REGION="${REGION:-ap-south-1}"
STACK=buddy-mail-tracker
cd "$(dirname "$0")"
python3 -m unittest discover -s tests -q
echo "Deploying to account $(aws sts get-caller-identity --query Account --output text) in $REGION"

KEY=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40 || true)
aws cloudformation deploy --region "$REGION" --stack-name $STACK --template-file template.yaml \
  --capabilities CAPABILITY_IAM --parameter-overrides ReadKey="$KEY" --no-fail-on-empty-changeset

ZIP=$(mktemp -d)/tracker.zip
(cd src && zip -q "$ZIP" ./*.py)
aws lambda update-function-code --region "$REGION" --function-name $STACK --zip-file "fileb://$ZIP" >/dev/null
aws lambda wait function-updated --region "$REGION" --function-name $STACK

URL=$(aws cloudformation describe-stacks --region "$REGION" --stack-name $STACK --query "Stacks[0].Outputs[?OutputKey=='Url'].OutputValue" --output text)
URL=${URL%/}
echo "Tracker URL: $URL"
echo "$URL|$KEY" > /tmp/buddy_tracker.txt
echo "Setup file ready: /tmp/buddy_tracker.txt (adb push /tmp/buddy_tracker.txt /sdcard/Download/)"
