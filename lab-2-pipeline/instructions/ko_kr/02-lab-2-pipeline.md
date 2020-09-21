컨테이너 기반 마이크로 서비스를 위한 지속적 통합/전달 파이프라인

**개요**   

실습 2는 실습 1에서 사용한 개념 및 기법을 바탕으로 진행됩니다. 실습 2에서는 실습 1의 마이크로 서비스 3개를 가져와 각 서비스에 대해 지속적 통합 파이프라인을 구축함으로써 각 마이크로 서비스의 빌드, 배포 및 테스트를 자동화합니다.

- **프런트 엔드:** MustacheMe 웹 애플리케이션

- **메타데이터**: MustacheMe Info 마이크로 서비스

- **이미지 처리**: MustacheMe Processor 서비스

이 실습에는 이러한 개별 마이크로 서비스의 빌드 및 배포를 자동화하는 절차가 포함되어 있습니다. 먼저 Jenkins Docker 이미지를 빌드하여 이를 Amazon ECS 서비스로 변환하는 작업부터 시작합니다. 모든 서비스는 Amazon CodePipeline을 사용하여 Amazon CodeCommit에 위치한 소스로부터 빌드합니다. 결과물로 얻은 이미지는 Amazon ECR에 저장한 다음, Amazon ECS에 배포합니다. 모든 네트워크 트래픽은 Amazon ALB를 통과하고 각 마이크로 서비스의 호스트 ECS 인스턴스에 있는 서로 다른 포트를 사용합니다. 마지막으로, 배포하는 각 마이크로 서비스의 유효성을 확인할 수 있게 해주는 타사 도구([Postman](https://app.getpostman.com/))를 사용한 테스트를 추가합니다.

요약하면 다음과 같습니다.

1.  제공된 Dockerfile을 사용하여 Jenkins Docker 이미지 생성

2.  Docker 이미지를 저장할 Amazon ECR 리포지토리 생성

3.  Jenkins ECS 서비스 생성

4.  스크립트를 작성하여 마이크로 서비스 3개를 구축 및 배포

5.  CodePipeline에 테스트 재품군을 추가하여 마이크 서비스 유효성 확인

**소요 시간**

본 실습은 **45분에서 1시간** 정도 소요됩니다.

## 실습 2: 컨테이너 기반 마이크로 서비스를 위한 지속적 통합/전달 파이프라인

**개요**

실습 1과 마찬가지로 명령을 실행하기 위해 EC2 인스턴스에 연결해야 합니다. 실습 2에서는 실습 2를 위한 초기 설정 및 배포 과정의 일부로 자체 CLI 인스턴스를 생성합니다. 실습 1과 동일한 CLI 인스턴스를 사용하지는 않습니다.

---

## 작업 1: CLI 인스턴스 DNS 이름 검색

**개요**

연결할 CLI 인스턴스는 CloudFormation 스택의 일부입니다. 그 이름을 찾아보겠습니다.

1.  qwikLABS 랩에서 **Open Console**을 클릭하고,*awsstudent*에게 주어진 권한을 사용하여 콘솔에 로그인합니다. 맨 위 메뉴 바에서 **Services** > **CloudFormation**을 클릭합니다.

2.  표에 스택이 나열되어 있습니다. 스택은 YAML 형식의 CloudFormation 템플릿이 정의하는 인프라를 자세히 보여줍니다. 이름에 “CliInstanceStack”이 있는 행을 클릭합니다.

3.  하단 창에서 Outputs 탭을 클릭합니다.

4.  인스턴스의 DNS는, “PublicDnsName”이라는 **키**의 **값**입니다.

5.  이것을 어딘가(예: 클립보드/버퍼)에 복사합니다.

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture1.png)

## 작업 2: 인스턴스에 연결

6. [6]디렉토리를 .pem 파일이 있는 위치로 변경합니다.

**참고**: 이것은 실습 1의.pem 파일과는 별도입니다. 실습마다 자체 권한이 있습니다.

7. [7]SSH로 인스턴스에 접속합니다.

```
ssh -i <yourkey.pem> ec2-user@<your ec2 instance public dns name>
```      

## 작업 3: Jenkins를 AWS ECS 서비스로 구축 및 실행

**개요**

이 실습에서는 스크립트를 사용하여 Jenkins Docker 컨테이너를 구축한 후 이를 ECR로 푸시합니다. 그 다음에 Jenkins를 서비스로서 ECR에서 ECS로 프로비저닝합니다. 이를 위해 스크립트부터 살펴보겠습니다.

**시나리오**

모놀리스를 분리된 마이크로 서비스로 나누어 아키텍처의 유연성을 높일 수 있습니다. 그러나 이러한 유연성과 함께 복잡성도 높아집니다. 관리 가능한 수준으로 복잡성을 유지하려면 해당 프로세스를 최대한 자동화해야 합니다. 이러한 자동화를 통해 배포 시간이 단축되어 비즈니스의 민첩성이 향상됩니다.

완비된 CI/CD 프로세스를 구축하려면 먼저 빌드 서버를 구축해야 합니다. Amazon EC2 인스턴스에서 Jenkins를 실행하여 사용할 수도 있지만, 이 실습은 컨테이너 및 마이크로 서비스에 관한 교육 과정이므로 Amazon ECR에서 서비스로 실행하겠습니다!

그 다음 작업은 Jenkins 서비스를 자동화에 통합하는 것입니다. CloudFormation을 사용하여 Amazon CodePipeline 집합을 생성함으로써 각 마이크로 서비스 빌드 및 후속 배포를 자동화할 수 있습니다. 이를 스크립팅하면 각 마이크로 서비스에 대해 반복하여 작업하기가 수월해집니다.

Jenkins Docker 이미지를 빌드하고 이를 Amazon ECR로 푸시

8. [8]실습 2의 CLI 인스턴스의 소스 디렉터리로 이동합니다.

`cd /home/ec2-user/lab-2-pipeline/src/jenkins`

9. [9]이 디렉토리에는 Jenkins 컨테이너를 빌드하기 위한 Dockerfile이 있습니다.

이 파일에서는 주요 교육 과정 Jenkins Docker 이미지를 기본 이미지로 사용한 후, 일부 플러그인과 스크립트에 추가합니다. Dockerfile의 역할이 무엇인지 알아보기 위해 Dockerfile을 빠르게 훑어보겠습니다.

'cat Dockerfile'

10. [10] Docker 명령을 실행하기 전에 EC2 Container Repository(ECR)를 생성해야 합니다. 다음 AWS CLI 명령은 “jenkins”라는 ECR 리포지토리를 생성합니다.

`aws ecr create-repository --repository-name jenkins`

11. [11]이제 Jenkins Docker 이미지를 빌드할 준비가 거의 다 되었습니다. 그 전에 방금 생성한 리포지토리에 대한 URL을 얻어야 합니다. 이 값은 Docker 빌드 및 푸시 명령에 대한 입력 파라미터로 필요합니다. URL을 얻는 손쉬운 방법은 AWS CLI를 사용하여 ECR을 질의하는 것입니다. 다음과 같이 인스턴스의 환경 변수에 값을 입력하면 후속 명령에서 계속 사용할 수 있습니다.

```
export JENKINS_REPO_URI=$(aws ecr describe-repositories \
--repository-names jenkins \
--query 'repositories[].repositoryUri' --output text)
```

12. [12]그 다음에는 아래 명령을 실행하여 이 환경 변수가 올바르게 설정되어 있는지 확인합니다.

`env | grep JENKINS`

아래 화면처럼 JENKINS\_REPO\_URI가 설정된 상태로 출력되어야 합니다.

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture2.png)

**참고: SSH 세션이 끊어졌거나 새로 연결하는 경우, 이 환경 변수를 다시 내보내야 합니다.**

13. [13]이제 환경이 설정되었으므로 docker build 명령을 실행할 수 있습니다. “-t”는 ECR 리포지토리의 태그를 추가합니다.

`docker build -t ${JENKINS_REPO_URI}:lab-2-pipeline /home/ec2-user/lab-2-pipeline/src/jenkins`

14. [14]다음 명령을 실행하여 이미지 목록을 나열하고 태그가 지정된 리포지토리를 표시합니다.

`docker images`

Jenkins 이미지와 해당 ECR 리포지토리가 나타나야 합니다.

15. [15]그 다음에는 docker push를 사용하여 로컬 인스턴스에서 AWS ECR 리포지토리로 Jenkins Docker 이미지를 복사할 수 있습니다.

`docker push ${JENKINS_REPO_URI}:lab-2-pipeline`

16. [16]이 작업이 완료되면 AWS Management Console을 통하거나 특정 명령을 수행하여 ECR에서 이미지를 볼 수 있습니다.

`aws ecr list-images --repository-name jenkins`

이제 Jenkins 이미지를 빌드하여 Elastic Container Registry에 배포하였으므로 다음 섹션으로 이동할 수 있습니다. 다음 섹션에서는 Jenkins를 ECS 서비스로 변환하고 자동화를 사용하여 개별 컨테이너 마이크로 서비스의 집합으로 MustacheMe 애플리케이션의 다른 구성 요소를 빌드 및 배포합니다.

## 작업 4: Jenkins Docker 이미지를 AWS ECS 서비스로 변환

17. [17]Jenkins를 Amazon ECS 내에서 서비스로 실행한다는 것은 Jenkins Docker 컨테이너가 응답하지 않을 경우 ECS가 이를 자동으로 다시 시작함을 뜻합니다. AWS Management console을 사용하여 이 이미지를 서비스로 배포할 수도 있지만, 이 실습에서는 자동화 취지에 맞게 AWS Cloudformation에서 사용할 수 있는 YAML 파일을 생성하였습니다. 이를 통하여 인프라를 배포 및 업데이트할 수 있는 프로그래밍이 가능해집니다. YAML 형식이 JSON보다 읽고 쓰기 쉽다고 생각하는 사람이 많습니다. YAML 파일에 대해 살펴보겠습니다.

`cat /home/ec2-user/lab-2-pipeline/scripts/jenkins-ecs-service.yaml`

이 파일의 내용을 이해하시겠습니까? 이 실습 후반부에서는 더 복잡한 YAML 파일이 나옵니다. YAML 파일에 나열된 행의 의도가 분명히 이해되지 않을 경우 도움을 요청하시기 바랍니다.

18. [18]이제 위의 YAML 파일을 템플릿으로 사용하여 Jenkins를 서비스로 배포하는 명령을 다음과 같이 실행하겠습니다.

```
aws cloudformation create-stack --stack-name JenkinsService \
--template-body file:///home/ec2-user/lab-2-pipeline/scripts/jenkins-ecs-service.yaml
```

이 배포 작업은 완료 또는 상태 반환에 몇 분이 걸립니다. CloudFormation 페이지에서 AWS Management Console을 통해 스택 이벤트를 볼 수 있습니다.

이 페이지에는 상태를 새로 고칠 수 있는 새로 고침 버튼이 있습니다.

스택이 성공적으로 생성되었습니까? 어떤 이벤트가 발생했습니까? 어떤 순서로 발생했습니까? 이벤트와 상태가 YAML 파일에서 본 것과 일치합니까?

## 작업 5: CloudFormation 및 CodePipeline을 사용하여 마이크로 서비스에 대한 CI/CD 프로세스 생성

다음은 각 마이크로 서비스에 대해 수행해야 할 다음 단계 작업입니다.

- 마이크로 서비스용 CodeCommit 리포지토리 생성

- 마이크로 서비스용 Jenkins 빌드 작업 생성

- 마이크로 서비스용 CodePipeline 생성

- 마이크로 서비스용 Application Load Balancer의 리스너 및 타겟 그룹 생성

- Git 리포지토리를 복제하고 Amazon CodeCommit 리포지토리에 버전을 복제

1~4단계는 여러분이 배포할 수 있도록 YAML CloudFormation 템플릿으로 코딩되었습니다.

19. [19]먼저 이 YAML 파일을 살펴보겠습니다.

`less /home/ec2-user/lab-2-pipeline/scripts/microservice-pipeline.yaml`


필요한 입력 파라미터를 모두 적어두어야 합니다. 마이크로 서비스 3개 각각에 대해서뿐만 아니라 테스트를 작성할 이 실습의 마지막 부분에서도 이 템플릿을 다시 사용할 것이기 때문입니다.

CloudFormation의 핵심 부분에는 다음 항목이 포함됩니다.

- Lambda 함수로 내장된 Jenkins 작업을 생성용 “*JenkinsBuildJobResource*”라는 사용자 정의 CloudFormation 리소스. 이 리소스는 Jenkins 작업 구성 XML 템플릿 파일을 가져와 파일에 제공된 파라미터를 교체한 후 이를 Jenkins 서버에 업로드하여 새로운 빌드 프로젝트를 생성합니다.

- 마이크로 서비스와 그 이름이 같은 CodeCommit 리포지토리를 생성하기 위한 CodeCommit 리포지토리 리소스

- Application Load Balancer의 특정 포트에 전송된 트래픽을 마이크로 서비스로 전달하기 위한 Application Load Balancer 리스너 리소스

- 이 마이크로 서비스에 ECS 서비스를 연결하기 위해 ECS가 사용할 Application Load Balancer 타겟 그룹

- CodeCommit 리포지토리를 새로운 git push 명령에서 트리거되는 소스로 포함하고, Jenkins를 빌드 리소스로 포함하며, 마이크로 서비스 ECS 작업 정의를 생성하고 마이크로 서비스를 위한 ECS 서비스를 배포할 AWS Lambda 함수를 포함하는 CodePipeline 리소스

20. [20]이제 AWS CLI로 이 스택을 시작하기 위해 CloudFormation을 사용하겠습니다. CLI를 사용하는 이유는 이 실습에서 나중에 이 단계를 자동화할 것이기 때문입니다.

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

21. [21]다음 명령을 사용하면 명령줄에서 CloudFormation 스택의 상태를 볼 수 있습니다.

```
aws cloudformation wait stack-create-complete \
--stack-name MustacheMeWebServerPipeline
```

22. [22]스택이 성공적으로 완료되면 git을 사용하여 MustacheMe 웹 서버 코드를 자신의 CodeCommit 리포지토리에 복제할 수 있습니다. git 명령을 실행하기 전에 해당 리전에 다른 환경 변수를 설정해야 합니다. 그 다음에 git을 사용하여 리포지토리를 복제할 수 있습니다.

```
export AWS_REGION=$(aws configure get region)

git clone \
https://git-codecommit.${AWS_REGION}.amazonaws.com/v1/repos/MustacheMeWebServer \
/home/ec2-user/repos/MustacheMeWebServer
```

여러분이 복제하는 리포지토리는 비어 있는 상태이므로 관련 경고는 무시해도 됩니다.

23. [23]리포지토리를 복제한 후 해당 코드를 로컬 리포지토리 디렉터리로 복사합니다. 그 다음에 다음과 같이 git을 사용하여 모든 파일을 추가하고 커밋 메시지를 추가한 다음, 초기 커밋을 수행합니다.


```
mv /home/ec2-user/lab-2-pipeline/src/MustacheMe/MustacheMeWebServer/* \
/home/ec2-user/repos/MustacheMeWebServer/

cd  /home/ec2-user/repos/MustacheMeWebServer

git add -A

git commit -m "Initial commit"

git push -u origin master
```

 24. [24]변경 사항을 AWS CodeCommit으로 푸시한 후 CodePipeline이 변경 사항을 픽업하여 이를 처리하는지 관찰합니다. CodePipeline은 CodeCommit 리포지토리의 커밋을 감시하도록 구성되어 있기 때문입니다. 다음과 같이 AWS Management Console을 사용하여 이를 시각적으로 확인할 수 있습니다.

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture3.png)

축하합니다! 배포를 자동화하고 첫 번째 마이크로 서비스를 배포하였습니다! 다음은 마이크로 서비스를 배포하기 위해 수행한 절차를 요약한 것입니다.


CloudFormation 스크립트를 실행하여 다음과 같은 마이크로 서비스용 리소스 생성:
- 마이크로 서비스에 대한 CodeCommit 리포지토리
- Lambda 함수를 통한 Jenkins 작업과 Jenkins API를 사용하여 새로운 Jenkins 작업을 업로드하는 사용자 정의 CloudFormation 리소스
- 마이크로 서비스용 Docker 이미지를 빌드하여 ECR에 배포하기 위해 소스 코드가 상주하는 CodeCommit 리포지토리를 Jenkins 빌드 작업에 연결하고, CloudFormation 템플릿을 통해 마이크로 서비스를 배포하는 AWS Lambda 함수에 최종적으로 연결하는 마이크로 서비스용 CodePipeline.

마이크로 서비스의 소스 코드를 마이크로 서비스를 위한 로컬 git 리포지토리에 커밋하고 CodePipeline 서비스를 통해 마이크로 서비스의 배포를 트리거하는CodeCommit 리포지토리에 코드를 푸시

나머지 마이크로 서비스에 대해서도 이 다섯 단계를 동일하게 실행해야 합니다.

- Jenkins 마이크로 서비스용 CodeCommit 리포지토리 생성

- 마이크로 서비스용 Jenkins 빌드 작업 생성

- 마이크로 서비스용 CodePipeline 생성

- 마이크로 서비스용 Application Load Balancer의 리스너 및 타겟 그룹 생성

- Git 리포지토리를 복제하고 Amazon CodeCommit 리포지토리에 버전을 복제

수동으로 실행할 수도 있지만 스크립트를 사용하여 실행해보겠습니다. 이 방식이 오류가 덜 발생하고 속도도 더 빠릅니다. 스크립트는 이미 사용한 명령을 묶은 것입니다.

25. [25]여러분을 위해 스크립트 버전 하나를 생성하였습니다.

`cat /home/ec2-user/lab-2-pipeline/scripts/deploy-microservice.sh`

여러분이 방금 수동으로 실행한 명령을 이 스크립트가 어떻게 실행하는지 보시기 바랍니다.

26. [26]이 스크립트를 실행하려면 두 가지, 즉 서비스 이름과 서비스를 실행할 포트를 입력해야 합니다.

`deploy-microservice.sh <MICROSESRVICE_NAME> <PORT>`

27. [27]다음 명령을 사용하여 나머지 두 마이크로 서비스에 대한 파이프라인을 빌드합니다.

```
cd /home/ec2-user/lab-2-pipeline/scripts/

./deploy-microservice.sh MustacheMeProcessor 8082

./deploy-microservice.sh MustacheMeInfo 8092
```

28. [28]이제 CodePipeline Management 콘솔 화면에 다음과 같이 파이프라인 3개가 보일 것입니다.

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture4.png)

각 CodePipeline은 생성될 때 실행되려고 하지만, 마이크로 서비스 별 CodeCommit 리포지토리가 비어 있으므로 오류 상태가 될 것입니다. 코드를 커밋하여 CodeCommit 리포지토리로 푸시하자마자 새 릴리스가 트리거되어 성공적으로 완료됩니다.

29. [29]각 파이프라인을 통하여 마이크로 서비스 3개가 모두 배포되면 브라우저에서 ALB(Application Load Balancer)의 URL로 연결하여 이를 확인할 수 있습니다. 마이크로 서비스 CloudFormation **스택 3개**,(“*MustacheMeInfoStack*”, “*MustacheMeProcessorStack*” 및 “*MustachMeWebServerStack”*)가 모두 배포되고 “***CREATE\_COMPLETE***” 상태가 될 때까지 기다립니다. 이 정보는 기본 CloudFormation 스택의 Outputs 탭에서 확인할  수 있습니다.

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture5.png)

잠시 쉬었다가 이미지에 수염을 추가하여 마이크로 서비스가 제대로 작동하는지 확인해 보십시오! MustacheMe 애플리케이션이 8000번 포트에서 실행되고 있으므로 이에 접근하려면 위의 URL이 필요하다는 것을 기억하십시오 이미지 처리 섹션이 작동하지 않으면 MustacheMe Processor 마이크로 서비스가 아직 배포 및 작동되지 않았기 때문이므로*MustacheMeProcessorStack*이라는 CloudFormation 스택 이름이 *CREATE\_COMPLETE* 상태가 될 때까지 기다립니다. 세션 정보와 연결 정보가 데이터를 반환하지 않으면 MustacheMeInfo 마이크로 서비스가 아직 작동하지 않는 것이므로, *MustacheMeInfoStack*이라는 CloudFormation 스택 이름이 *CREATE\_COMPLETE* 상태가 될 때까지 기다립니다.


## 작업 6:각 마이크로 서비스 배포 파이프라인에 테스트 단계를 추가(선택 사항)

30. [30]이제 마이크로 서비스 3개가 모두 작동하므로 각 마이크로 서비스에 테스트 작업을 추가하여 예상한 대로 작동하는지 확인할 수 있습니다. 이를 위해 Jenkins와 통합된 [Postman] (https://www.getpostman.com/) 테스트 프레임워크를 사용합니다. 지속적 통합 프로세스의 일부로 Jenkins를 호출하여 Postman 테스트 스크립트를 실행하고 그 결과를 출력합니다. 테스트 중 어느 하나라도 실패하면 Jenkins 빌드도 실패합니다.

다음 명령을 실행하여 MustacheMeWebServer 마이크로 서비스에 대한 Postman 테스트 스크립트를 확인합니다.

`cat /home/ec2-user/repos/MustacheMeWebServer/postman-collection.json`

파일 내용이 마이크로 서비스 엔드포인트에 대해 몇 가지 테스트를 실행한다는 것을 알 수 있을 것입니다.

본 과정을 위하여 구성한 Postman “모음”이기는 하나 MustacheMe 마이크로 서비스의 특정 URL에 맞게 사용자 정의했습니다.

- 엔드포인트가 200(OK)이라는 HTTP 응답 코드를 반환하는지 테스트합니다.

- 반환된 html에 “Simple Mustache Service”라는 텍스트가 포함되어 있는지 테스트합니다.

31. [31]CloudFormation에서 업데이트 명령을 사용하여 마이크로 서비스 파이프라인 CloudFormation 템플릿을 업데이트할 수 있습니다. 이렇게 하면 마이크로 서비스에 대한 엔드포인트를 테스트할 수 있도록 배포 이후의 단계가 빌드 파이프라인에 추가됩니다. “*ExtendedFlag*”라는 CloudFormation 파라미터를 변경하여 “Test” 작업이 추가된 파이프라인을 생성하고 마이크로 서비스를 위한 테스트 프로젝트를 Jenkins에 배포할 수도 있습니다.

먼저, 업데이트될 Cloudformation 템플릿을 살펴봅니다. "SimpleCodePipeline"이라는 리소스 대신에 "ExtendedCodePipeline"이라는 리소스가 생성되며, 각 마이크로 서비스 엔드포인트를 테스트하기 위한 Jenkins 작업인 "JenkinsTestJobResource" 리소스도 생성됩니다.

`less /home/ec2-user/lab-2-pipeline/scripts/microservice-pipeline.yaml`

32. [32]CodePipeline을 수정하려면 AWS Management Console에서 CloudFormation 서비스를 엽니다. “MustacheMeWebServerPipeline”이라는 CloudFormation 스택 이름을 선택하고 아래 스크린샷과 같이 “Update Stack” 옵션을 클릭합니다.

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture6.png)

33. [33]"Use current template" 옵션을 선택한 후 Next를 클릭합니다. “ExtendedFlag”라는 파라미터를 선택하고 아래 스크린샷과 같이 "true"를 선택한 후 Next를 클릭합니다.

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture7.png)

34. [34]Options 페이지에서 기본 설정을 수락한 후 Next를 클릭합니다.

35. 이제 Review 페이지에는 현재 배포된 내용 및 변경해야 할 사항을 기반으로 CloudFormation에서 계산한
변경 집합(Change Sets)이 표시됩니다. 아래 스크린샷과 같이, 한 CodePipeline이 제거되고 다른 CodePipeline이 추가되며 Jenkins Test Resource가 추가된 것을 볼 수 있습니다. Update 버튼을 클릭하여 변경 사항을 실행합니다.

[](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture8.png)

36. [36]AWS Management Console에서 CodePipeline 서비스를 클릭합니다. “MustacheMeWebServerPipelineExt”라는 이름의 파이프라인을 선택합니다. 아래 스크린샷과 같이 “TestAction” 작업이 포함된 “Test”라는 추가 단계가 있는지 확인합니다.

파이프라인이 모든 단계를 통과해야 하기 때문에 “Succeeded” 상태로 완료되는데 몇 분이 걸립니다.

[](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture9.png)

37. [37]테스트 작업에 있는 Jenkins 프로바이더 링크를 클릭하여 테스트 결과를 확인할 수 있습니다. 링크를 클릭하면 다음과 같은 페이지가 나타납니다. Jenkins '**Admin** 사용자의 비밀번호는 **JenkinsStack** CloudFormation 스택의 **JenkinsPassword** 출력 값으로 확인할 수 있습니다.

38. [38] 확인되는 빌드 번호 **\# 2**를 클릭한 후, **Test Result** 페이지를 클릭합니다.

[](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture10.png)

39. [39]이 페이지의 **All Tests** 섹션에서 “**(root)**” 라는 링크를 클릭합니다. 이 페이지의 **All Tests** 섹션에서 “**MustacheMeWebServer**”라는 링크를 클릭합니다. 이렇게 하면 Postman 모음 파일로부터 테스트 2개가 성공적으로 실행되었음을 알리는 페이지가 다음과 같이 나타납니다.

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture11.png)

40. [40]이제 다음 CLI 명령을 실행하여 나머지 두 마이크로 서비스(MustacheMeProcessorPipeline 및 MustacheMeInfoPipeline)에 대해서도 이 단계를 반복합니다.

```
aws cloudformation update-stack --stack-name MustacheMeProcessorPipeline --use-previous-template --parameters ParameterKey=MicroserviceName,UsePreviousValue=true ParameterKey=RepoName,UsePreviousValue=true ParameterKey=PortNumber,UsePreviousValue=true ParameterKey=ExtendedFlag,ParameterValue=true

aws cloudformation update-stack --stack-name MustacheMeInfoPipeline --use-previous-template --parameters ParameterKey=MicroserviceName,UsePreviousValue=true ParameterKey=RepoName,UsePreviousValue=true ParameterKey=PortNumber,UsePreviousValue=true ParameterKey=ExtendedFlag,ParameterValue=true
```

이제 애플리케이션을 빌드, 테스트 및 업데이트하기 위한 CI/CD 프로세스를 완전히 자동화하였습니다.

**이로써 실습 2를 마칩니다. 즐거운 시간이 되었기를 바랍니다.**
