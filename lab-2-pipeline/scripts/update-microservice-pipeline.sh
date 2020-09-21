#!/bin/bash -ex

if [ -z "$1" ]; then
  echo "No microservice name provided"
  exit 1
else
  MICROSERVICE_NAME="$1"
fi

cd /home/ec2-user/lab-2-pipeline
echo "Updating the Microservice:${MICROSERVICE_NAME} pipeline"
aws cloudformation update-stack --stack-name "${MICROSERVICE_NAME}Pipeline" --use-previous-template --parameters ParameterKey=MicroserviceName,UsePreviousValue=true ParameterKey=RepoName,UsePreviousValue=true ParameterKey=PortNumber,UsePreviousValue=true ParameterKey=ExtendedFlag,ParameterValue=true
echo "Waiting for CFN stack to be updated....."
aws cloudformation wait stack-update-complete --stack-name "${MICROSERVICE_NAME}Pipeline"
echo "Stack updated!!"
