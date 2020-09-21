#!/bin/bash -ex

# Check parameter passed in
if [ -z $1 ]; then
    echo "Need to pass REPO_NAME as a parameter"
    exit 1
fi
REPO_NAME=$(echo "$1" | awk '{print tolower($0)}')

# Check parameter passed in
if [ -z $1 ]; then
    TAG_NAME="latest"
else
    TAG_NAME=$(echo "$2" | awk '{print tolower($0)}')
fi

echo "REPO_NAME is ${REPO_NAME} and TAG_NAME is ${TAG_NAME}"


INSTANCE_IDENTITY=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document)
AWS_REGION=$(echo ${INSTANCE_IDENTITY} | jq -r '.region')
AWS_ACCOUNT_ID=$(echo ${INSTANCE_IDENTITY} | jq -r '.accountId')

#Set the repository address
ECR_REPO_PREFIX="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
FULL_REPO_NAME="${ECR_REPO_PREFIX}/${REPO_NAME}:${TAG_NAME}"

#Build the containerexit
docker build -t ${FULL_REPO_NAME} .

# create an ECR repository if one doesn't exist
repoArn=$(aws ecr describe-repositories --region ${AWS_REGION} --output json | jq -r --arg x ${REPO_NAME} '.repositories[] | select(.repositoryName==$x) | .repositoryArn')
if [ -z "$repoArn" ]; then
    echo "Repository: ${REPO_NAME} not found. Creating new one in ECR region: ${AWS_REGION}..."
    aws ecr create-repository --repository-name ${REPO_NAME} --region ${AWS_REGION}
else
    echo "Found existing repository: $repoArn"
fi

docker push ${FULL_REPO_NAME}
