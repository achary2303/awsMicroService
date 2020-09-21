#!/bin/bash -ex

LAB_NAME="lab-2-pipeline"
AWS_REGION=$(aws configure get region)

if [ -z "$1" ]; then
  echo "No microservice name provided"
  exit 1
else
  MICROSERVICE_NAME="$1"
  REPO_NAME=$(echo "${MICROSERVICE_NAME}" | awk '{print tolower($0)}')
fi

if [ -z "$2" ]; then
  echo "No port number provided"
  exit 1
elif ! [[ "$2" =~ ^[0-9]+$ ]]; then
  echo "Port number invalid"
  exit 1
else
  MICROSERVICE_PORT="$2"
fi

echo "MICROSERVICE_NAME=${MICROSERVICE_NAME}"
echo "REPO_NAME=${REPO_NAME}"
echo "MICROSERVICE_PORT=${MICROSERVICE_PORT}"
echo "LAB_NAME=${LAB_NAME}"
echo "REGION=${AWS_REGION}"

cd /home/ec2-user/${LAB_NAME}
echo "Creating the Microservice pipeline"
aws cloudformation create-stack --stack-name "${MICROSERVICE_NAME}Pipeline" --parameters ParameterKey=MicroserviceName,ParameterValue=${MICROSERVICE_NAME} ParameterKey=RepoName,ParameterValue=${REPO_NAME} ParameterKey=PortNumber,ParameterValue=${MICROSERVICE_PORT} --template-body file://scripts/microservice-pipeline.yaml
echo "Waiting for CFN stack to be created....."
aws cloudformation wait stack-create-complete --stack-name "${MICROSERVICE_NAME}Pipeline"
echo "Stack created!!"

echo "Cloning git repo"
git clone https://git-codecommit.${AWS_REGION}.amazonaws.com/v1/repos/${MICROSERVICE_NAME} /home/ec2-user/repos/${MICROSERVICE_NAME}
mv /home/ec2-user/${LAB_NAME}/src/MustacheMe/${MICROSERVICE_NAME}/* /home/ec2-user/repos/${MICROSERVICE_NAME}/
cd  /home/ec2-user/repos/${MICROSERVICE_NAME}
git add -A
git commit -m "Initial commit"
git push -u origin master
