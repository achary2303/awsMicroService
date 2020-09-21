# Lab 2: Continuous Integration/Delivery Pipelines for Container based microservices

**Overview**   

Lab 2 builds on the concepts and techniques you used during Lab 1. In Lab 2 you will take the 3 microservices from Lab 1 and build a continuous integration pipeline for each one automating the build, deployment and test of each microservice.

- **Front End:** The MustacheMe web application

- **Metadata:** The MustacheMe Info microservice

- **Image Processing:** The MustacheMe Processor service

The lab will include steps to automate the building and deployment of these individual microservices. You will start by building a Jenkins Docker image and turning it into an Amazon ECS service. All of the services will be built from sources that reside in Amazon CodeCommit using Amazon CodePipeline. The resulting images will be stored in Amazon ECR, then deployed onto Amazon ECS. All network traffic will flow through an Amazon ALB and will use different ports on the host ECS instance for each microservice. Finally, you will add tests using a 3rd party tool ([Postman](https://app.getpostman.com/)) that will allow you to validate each of the microservices you deploy.

In summary:

1.  Create a Jenkins Docker image using the supplied Dockerfile

2.  Create an Amazon ECR repository to store the Docker images

3.  Create a Jenkins ECS service

4.  Write a script to build and deploy three microservices.

5.  Add a test suite to Code Pipeline to validate the microservice
    builds

**Duration**

This lab should take you between **45 minutes and an hour**.

## Connect to Your EC2 CLI Instance

**Overview**

Similar to Lab 1, you will need to connect to an EC2 instance to run the commands. Lab 2 creates its own CLI instance as part of the initial setup and deployment for Lab 2. You will not use the same CLI instance as Lab 1.

---

## Task 1: Retrieve the CLI instance DNS name

**Overview**

The CLI instance you are going to connect to is part of a CloudFormation stack. Let’s find its name.

1.  From the qwikLABS lab page, click **Open Console** and login using the credentials provided for *awsstudent*. On the top menu bar, click **Services** > **CloudFormation**.

2.  In the table you see a list of Stacks. These detail the infrastructure defined by YAML-formatted CloudFormation templates. Click on the line that has “CliInstanceStack” in its name.

3.  In the lower pane, click on the Outputs tab.

4.  The instance’s DNS is the **Value** for which **Key** is “PublicDnsName”

5.  Copy this somewhere (your clipboard/buffer for example)

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture1.png)

## Task 2:  Connect to the instance

6. [6]Change directory to where your .pem file is located.

**Note:** This is a separate .pem file from Lab1. Each lab will have its own credentials.

7. [7]SSH into the instance.

```
ssh -i <yourkey.pem> ec2-user@<your ec2 instance public dns name>
```      

## Building and Running Jenkins as an AWS ECS Service

**Overview**

In this exercise, you will be using scripts to build a Jenkins Docker container and push it into ECR. Jenkins will then be provisioned from ECR to ECS as a service. Let’s start by taking a look at the scripts to
do this.

**Scenario**

You can add flexibility to your architecture by breaking your monolith into separate microservices. However, this flexibility comes at the cost of increasing complexity. In order to keep this complexity manageable, you will want to automate as much of the process as possible. This automation also accelerates the time to deployment making your business more agile.

To build a full-fledged CI/CD process you will first need a build server. You will use Jenkins for this and while you could run it on an Amazon EC2 instance, this is a bootcamp about containers and microservices so let’s run it as a service in Amazon ECR!

The next thing you will need to do is to integrate the Jenkins service into automation. You will use CloudFormation to create a set of Amazon CodePipelines to automate each microservice build and their subsequent deployment. You will script this to make it easier to repeat for each microservice.

## Task 3: Build the Jenkins Docker image and push it to Amazon ECR

8. [8]Navigate to the source directory on the Lab2 CLI instance.

`cd /home/ec2-user/lab-2-pipeline/src/jenkins`

9. [9]In this directory there is a Dockerfile to build the Jenkins container.

This file uses the main bootcamp Jenkins Docker image as its base and then simply adds in some plugins and scripts. Take a quick look at the Dockerfile to see if you understand what it is doing.

`cat Dockerfile`

10. [10] Before you can run the Docker commands you will need to create an Elastic Container Repository (ECR). The following AWS CLI command will create an ECR repository named “jenkins”

`aws ecr create-repository --repository-name jenkins`

11. [11]You are almost ready to build a Jenkins Docker image. Before doing this you need to get the URL for the repository you just created. You will need this value as input parameter for the Docker build and push commands. An easy way to get the URL is to simply query ECR using the AWS CLI. Let’s write the value into an environment variable on the instance so you can continue to use it in subsequent commands:

```
export JENKINS_REPO_URI=$(aws ecr describe-repositories \
--repository-names jenkins \
--query 'repositories[].repositoryUri' --output text)
```

12. [12]Next verify that these environment variables are set correctly by running the command:

`env | grep JENKINS`

You should see an output similar to this, where JENKINS\_REPO\_URI is set:

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture2.png)

**Note: if your ssh session becomes disconnected or you open another connection, you will need to re-export this environment variable.**

13. [13]Now that your environment is setup you can run the docker build command. The “-t” adds a tag of the ECR repository.

`docker build -t ${JENKINS_REPO_URI}:lab-2-pipeline /home/ec2-user/lab-2-pipeline/src/jenkins`

14. [14]Run docker images to list the images and show the repository they are tagged with:

`docker images`

You should see your jenkins image and your ECR repository.

15. [15]Next you can use docker push to copy the jenkins docker image from your local instance into the AWS ECR repository:

`docker push ${JENKINS_REPO_URI}:lab-2-pipeline`

16. [16]When that completes you can view the image in ECR via the AWS Management Console or by running given command:

`aws ecr list-images --repository-name jenkins`

Now that you have built and deployed the Jenkins image to Elastic Container Registry you can move onto the next section, where you will turn Jenkins into an ECS service and use automation to build and deploy the other components of your MustacheMe application as a set of individual containerized microservices.

## Task 4: Turn your Jenkins Docker image into an AWS ECS Service

17. [17]Running Jenkins as a service inside of Amazon ECS means that ECS will automatically restart the Jenkins Docker container should it become unresponsive. You could deploy this image as a service using the AWS Management console, but in the spirit of automation you have created a YAML file that you can use with AWS Cloudformation. This provides a programmatic way to deploy and update your infrastructure. Many people find the YAML format easier to read and write than JSON. Let’s review the YAML file:

`cat /home/ec2-user/lab-2-pipeline/scripts/jenkins-ecs-service.yaml`

Do you understand the contents of this file? You will have more complex YAML files later on in the lab. Please ask for assistance if you are unclear of the purpose of any of the lines in the YAML file.

18. [18]Now let’s run the command to deploy Jenkins as a service using the above YAML file as a template:

```
aws cloudformation create-stack --stack-name JenkinsService \
--template-body file:///home/ec2-user/lab-2-pipeline/scripts/jenkins-ecs-service.yaml
```

This deployment will take a few minutes to complete or return a status. You can see the stack events in the AWS Management Console on the CloudFormation page.

There is a refresh button on the page to refresh the status.

Did the stack create successfully? What events happened? What order did they happen in? Do the events and status match what you saw in the YAML file?

## Task 5: Use CloudFormation and CodePipeline to create a CI/CD process for your microservices

Here are the next steps you will need to do per microservice:

- Create a CodeCommit repo for your Microservices

- Create a Jenkins build job for the Microservice

- Create a CodePipeline for the Microservice

- Create an Application Load Balancer Listener and Target group for the Microservice

- Clone a Git repo and commit a version to Amazon CodeCommit rep

The first 4 steps have been coded into a YAML CloudFormationtemplate for you to deploy.

19. [19]Let’s first take a look at this YAML file:

`less /home/ec2-user/lab-2-pipeline/scripts/microservice-pipeline.yaml`


Note all of the input parameters required. This is because the template will be reused for each of your three microservices as well as the last part of the lab where you are writing tests.

Key parts of the CloudFormation include the following:

- Custom CloudFormation resource called “*JenkinsBuildJobResource*” used to create the Jenkins job which is implemented as a Lambda function. It takes a Jenkins job config XML template file and replaces the provided parameters in the file and uploads it to the Jenkins server to create a new build project.

- CodeCommit repository resource to create the CodeCommit respository with the same name as the name of the microservice

- Application Load Balancer listener resource to forward traffic sent to a specific port on the Application Load Balancer to the microservice.

- Application Load Balancer Target Group that will be used by ECS to attach the ECS services for this microservice.

- CodePipeline resource containing the CodeCommit repository as the source triggered on new git push commands, Jenkins as the build resource and an AWS Lambda function that will create the microserivce ECS Task Definition and deploy the ECS service for the microservice.

20. [20]Now you will use CloudFormation to launch this stack using the AWS CLI. You are using the CLI because further on in the lab you will automate this step:

```
cd /home/ec2-user/lab-2-pipeline

aws cloudformation create-stack \
--stack-name MustacheMeWebServerPipeline \
--parameters \
ParameterKey=MicroserviceName,ParameterValue=MustacheMeWebServer \
ParameterKey=RepoName,ParameterValue=mustachemewebserver \
ParameterKey=PortNumber,ParameterValue=8000 \
--template-body file://scripts/microservice-pipeline.yaml
```

21. [21]You can watch the status of the CloudFormation stack on the command line with the following command:

```
aws cloudformation wait stack-create-complete \
--stack-name MustacheMeWebServerPipeline
```

22. [22]When the stack has completed successfully, you can use git to clone the MustacheMe web server code into your own CodeCommit repo. Before running any git command you need to set another environment variable for the region. Then you can use git to clone the repository.

```
export AWS_REGION=$(aws configure get region)

git clone \
https://git-codecommit.${AWS_REGION}.amazonaws.com/v1/repos/MustacheMeWebServer \
/home/ec2-user/repos/MustacheMeWebServer
```

It is an empty repository that you are cloning, hence you can discard the relevant warning.

23. [23]After cloning the repository, copy the code to your local repository directory. Then you use git to add all the files, add a commit message and perform the initial commit:


```
mv /home/ec2-user/lab-2-pipeline/src/MustacheMe/MustacheMeWebServer/* \
/home/ec2-user/repos/MustacheMeWebServer/

cd  /home/ec2-user/repos/MustacheMeWebServer

git add -A

git commit -m "Initial commit"

git push -u origin master
```

 24. [24]After you push the changes to AWS CodeCommit, observe that they will be picked up by Code Pipeline and it will process them. This is because the CodePipeline is configured to watch for commits on the CodeCommit repository. You can see this visually using the AWS Management Console:

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture3.png)

Congratulations! You have automated the deployment and deployed your first microservice! Just to recap, youhave done the following steps to deploy your microserivce:


- Run a CloudFormation script to create the following resources for your microservice:
- CodeCommit repository for the microservice
- Jenkins job via a Lambda function and custom CloudFormation resource that uploads a new Jenkins job using the Jenkins API.
- CodePipeline for the microservice linking the CodeCommit repository where the source code resides to the Jenkins build job to build and deploy the Docker image for the microservice to ECR and finally connecting to the AWS Lambda function that deploys the microservice via a CloudFormation template.

- Committed the source code of the microservice to the local git repository for the microservice and pushed the code to the CodeCommit repository triggering a deployment of the microservice via the CodePipeline service.

- You will need to run the same five steps for the remaining Microservices:

- Create a CodeCommit repo for the Jenkins Microservice

- Create a Jenkins build job for the Microservice

- Create a CodePipeline for the Microservice

- Create an Application Load Balancer Listener and Target group for the Microservice

- Clone a Git repo and commit a version to Amazon CodeCommit rep

You could run them by hand, but let’s use a script to run them. It’s less error-prone and will be faster. The script is a grouping of the commands you have already used.

25. [25]We have created a version of this script for you.

`cat /home/ec2-user/lab-2-pipeline/scripts/deploy-microservice.sh`

Take a look at it to see how it is running the commands you just ran by hand.

26. [26]The script requires two inputs: the name of the service and the port it will run on:

`deploy-microservice.sh <MICROSESRVICE_NAME> <PORT>`

27. [27]Run the following commands to build the pipeline for the other remaining two microservices:

```
cd /home/ec2-user/lab-2-pipeline/scripts/

./deploy-microservice.sh MustacheMeProcessor 8082

./deploy-microservice.sh MustacheMeInfo 8092
```

28. [28]Now you should see three separate Pipelines in the CodePipeline Management console display:

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture4.png)

Note that each CodePipeline will be in a failed state as they will attempt to run when created however the CodeCommit
repository per microservice will be empty. As soon as the code is committed and pushed to the CodeCommit repository a new release will be triggered which should complete successfully.

29. [29]When all three microservices are deployed through each pipeline you should be able to view them by browsing to the URL of the ALB. Wait **until all three** of the microservice CloudFormation stacks names: “*MustacheMeInfoStack*”, “*MustacheMeProcessorStack*” and “*MustachMeWebServerStack”* are deployed and in the state “***CREATE\_COMPLETE***”. You will find this in the output tab of the base CloudFormation stack:

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture5.png)

Take a break and add a mustache to an image to see your microservices in action! Remember the MustacheMe web application is running on port 8000 so you will need the above URL to access it. If the image processing section is not working it will be because the MustacheMeProcessor microservice is not yet deployed and working, Wait until the CloudFormation stack name: *MustacheMeProcessorStack* is in the state: *CREATE\_COMPLETE*. If the Session Info and Connection Info are not returning any data then the MustacheMeInfo microservice is not yet up and running so wait until the CloudFormation stack name *MustacheMeInfoStack* is in the state *CREATE\_COMPLETE*.


## Task 6: Add a Test phase to each microservice deployment pipeline (Optional)

30. [30]Now that you have all 3 microservices working you can add a test action to each microservice to ensure each one is working as expected. You will be using the [Postman](https://www.getpostman.com/) testing framework to do this integrated with Jenkins. As part of your continuous integration process Jenkins will be invoked to run the postman test script and output the results. If any of the tests fail, the Jenkins build will fail.

View the postman test script for the MustacheMeWebServer microservice by running the following command:

`cat /home/ec2-user/repos/MustacheMeWebServer/postman-collection.json`

You will notice that the contents of the file run a couple of tests against the microservices endpoint:

- We have configured a Postman “collection” for the bootcamp but customized to the specific URL of your MustacheMe microservice

- Test if the endpoint returns an HTTP response code of 200 (OK)

- Test if the returned html contains the text “Simple Mustache Service”

31. [31]You can use the update command in CloudFormation to update the microservice pipeline CloudFormation template. This will add an extra step after the deploy stage to the build pipeline to test the endpoint for your microservice. Change the CloudFormation parameter called “*ExtendedFlag*” so that you create a pipeline with the added “Test” action and also deploy a Test project for the microservice to Jenkins.

First, take a look at the Cloudformation template that will be updated and notice the resource named “ExtendedCodePipeline” will be created instead of the resource “SimpleCodePipeline” and it will also create the resource “JenkinsTestJobResource” which is a Jenkins job to test each microservice end point.

`less /home/ec2-user/lab-2-pipeline/scripts/microservice-pipeline.yaml`

32. [32]To modify the CodePipeline open the CloudFormation service in the AWS Management Console. Select the CloudFormation stack name “MustacheMeWebServerPipeline” and click the “Update Stack” option like shown in the screenshot below.

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture6.png)

33. [33]Select the “Use current template” option and click Next. Select the Parameter named “ExtendedFlag” and select the “true” option shown in the screenshot below and then click Next.

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture7.png)

34. [34]On the Options page, accept the defaults and click Next.

35. On the Review page you should now see the Change Sets that CloudFormation has calculated based on what is currently
deployed and the changes that need to be made. You should be able to see that one CodePipeline will be removed and another added, and a Jenkins Test Resource added like shown in the screenshot below. Click the Update button to implement the changes.

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture8.png)

36. [36]Click the CodePipeline service in the AWS Management Console. Select the Pipeline with the name “MustacheMeWebServerPipelineExt”. Notice how there is now an extra stage called “Test” with an action called “TestAction” like shown in the screenshot below.

Please note that it will take several minutes for the pipeline to complete to the “Succeeded” state as it needs to pass through all of the stages.

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture9.png)

37. [37]You can validate the test results by clicking on the Jenkins provider link in the test action. This will open a page similar to the following. The password for Jenkins’ **Admin** user can be found as the **JenkinsPassword** output value of the **JenkinsStack** CloudFormation stack.

38. [38]Click on the successful build number **\#2.** Click on **Test Result** page.

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture10.png)

39. [39]Click on the link “**(root)**” in the **All Tests** section of the page. Then click the link “**MustacheMeWebServer**” in the **All Tests** section of the page. This should bring up a page like the following showing the successful execution of 2 tests from the postman collection file.

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture11.png)

40. [40]Now repeat the step for the other two microservices (MustacheMeProcessorPipeline and MustacheMeInfoPipeline) by running the following CLI commands:

```
aws cloudformation update-stack --stack-name MustacheMeProcessorPipeline --use-previous-template --parameters ParameterKey=MicroserviceName,UsePreviousValue=true ParameterKey=RepoName,UsePreviousValue=true ParameterKey=PortNumber,UsePreviousValue=true ParameterKey=ExtendedFlag,ParameterValue=true

aws cloudformation update-stack --stack-name MustacheMeInfoPipeline --use-previous-template --parameters ParameterKey=MicroserviceName,UsePreviousValue=true ParameterKey=RepoName,UsePreviousValue=true ParameterKey=PortNumber,UsePreviousValue=true ParameterKey=ExtendedFlag,ParameterValue=true
```

You now have a fully automated CI/CD process for building, testing and updating your application.

**That is the end of lab 2. We hope you enjoyed it.**
