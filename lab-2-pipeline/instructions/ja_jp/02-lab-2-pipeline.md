# ラボ 2: コンテナベースのマイクロサービスのための継続的インテグレーション/デリバリーパイプライン

**概要**   

ラボ 2 では、ラボ 1 で使用した概念と手法に基づいた構築を行います。ラボ 2 ではラボ 1 の 3 つのマイクロサービスを使用して、各マイクロサービスのビルド、デプロイ、およびテストを自動化するための継続的インテグレーションパイプラインを各マイクロサービスに対して構築します。

- **フロントエンド:** MustacheMe ウェブアプリケーション

- **メタデータ:** MustacheMe 情報マイクロサービス

- **イメージ処理:** MustacheMe プロセッササービス

このラボにはこれらの個々のマイクロサービスのビルドとデプロイを自動化するためのステップが含まれています。まず始めに Jenkins Docker イメージをビルドし、これを Amazon ECS サービスに変換します。すべてのサービスは、Amazon CodeCommit に存在するソースから Amazon CodePipeline を使用してビルドされます。結果として生成されたイメージは Amazon ECR に保存され、Amazon ECS にデプロイされます。すべてのネットワークトラフィックフローは Amazon ALB を経由し、マイクロサービスごとにホスト ECS インスタンス上の異なるポートが使用されます。最後に、デプロイした各マイクロサービスを検証できる、サードパーティーツール（[Postman](https://app.getpostman.com/)）を使用したテストを追加します。

要約すると、以下のようになります。

1. 提供された Dockerfile を使用して Jenkins Docker イメージを作成する

1. Docker イメージを保存するための Amazon ECR リポジトリを作成する

1. Jenkins ECS サービスを作成する

1. 3 つのマイクロサービスをビルドしてデプロイするためのスクリプトを記述する

1. マイクロサービスビルドを検証するためのテストスイートを CodePipeline に追加
    する

**所要時間**

このラボの所要時間は **45 分から 1 時間**です。

## EC2 CLI インスタンスに接続する

**概要**

ラボ 1 と同じように、コマンドを実行するために EC2 インスタンスに接続する必要があります。ラボ 2 では初期セットアップおよびラボ 2 用のデプロイの一環として独自の CLI インスタンスを作成します。ラボ 1 と同じ CLI インスタンスは使用しません。

---

## タスク 1: CLI インスタンスの DNS 名を取得する

**概要**

接続しようとしている CLI インスタンスは CloudFormation スタックの一部です。この名前を見つけます。

1. qwikLABS ラボページで、[**コンソールを開く**] をクリックし、**awsstudent** 用に提供されている認証情報を使用してログインします。[**サービス**] で [**CloudFormation**] をクリックします。

1. 表にスタックのリストが表示されます。これらは YAML 形式の CloudFormation テンプレートによって定義されるインフラストラクチャの詳細を示しています。**CliInstanceStack** という名前のチェックボックスをオンにします。

1. 下のペインで [**出力**] タブをクリックします。

1. インスタンスの DNS は、PublicDnsNameという**キー**に対する**値**です。

1. これを別の場所（クリップボードやバッファなど）にコピーします。

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture1.png)

## タスク 2: インスタンスに接続する

1. ディレクトリを .pem ファイルがある場所に変更します。

**注:** これはラボ 1 とは別の .pem ファイルです。認証情報はラボごとに固有となります。

1. SSH コマンドでインスタンスに接続します。

```
ssh -i <yourkey.pem> ec2-user@<your ec2 instance public dns name>
```      

## Jenkins を AWS ECS サービスとしてビルドして実行する

**概要**

この演習では、スクリプトを使用して Jenkins Docker コンテナをビルドし、ECR にプッシュします。Jenkins はその後、ECR から ECS にサービスとしてプロビジョニングされます。最初にこの操作を実行するスクリプトを見てみましょう。

**シナリオ**

モノリスを別々のマイクロサービスに分割することによってアーキテクチャの柔軟性を高めることができます。しかし、柔軟性と引き替えに複雑さが増すことになります。この複雑さを管理可能な状態に維持するために、できるだけ多くのプロセスを自動化する必要があります。このオートメーションによってデプロイに要する時間が短縮され、ビジネスの俊敏性が高まります。

本格的な CI/CD プロセスを構築するには、最初にビルドサーバーが必要です。この目的で Jenkins を使用します。Amazon EC2 インスタンス上で実行することも可能ですが、これはコンテナとマイクロサービスについてのブートキャンプであるため、Amazon ECR 内のサービスとして実行します。

次に必要なことは、Jenkins サービスをオートメーションに統合することです。CloudFormation を使用して、各マイクロサービスのビルドおよびその後続のデプロイを自動化するための一連の Amazon CodePipeline を作成します。これをスクリプト化して、各マイクロサービスに対して簡単に反復できるようにします。

## タスク 3: Jenkins Docker イメージをビルドして Amazon ECR にプッシュする

1. ラボ 2 の CLI インスタンスのソースディレクトリに移動します。

`cd /home/ec2-user/lab-2-pipeline/src/jenkins`

1. このディレクトリには、Jenkins コンテナをビルドするための Dockerfile があります。

このファイルはメインブートキャンプの Jenkins Docker イメージを基礎として使用し、いくつかのプラグインとスクリプトを単純に追加したものです。Dockerfile をざっと眺めて、動作を理解できるかどうかを確認します。

`cat Dockerfile`

1. Docker コマンドを実行する前に、Elastic Container Repository (ECR) を作成する必要があります。以下の AWS CLI コマンドによって、**jenkins** という名前の ECR リポジトリが作成されます。

`aws ecr create-repository --repository-name jenkins`

1. Jenkins Docker イメージをもうすぐビルドできます。この操作を行う前に、作成したリポジトリの URL を取得する必要があります。この値は Docker のビルドおよびプッシュコマンドの入力パラメータとして必要になります。URL を簡単に取得する方法は、AWS CLI を使用して ECR にクエリを実行することです。値をインスタンスの環境変数に書き込んでおき、後続のコマンドで値を引き続き使用できるようにしておきます。

```
export JENKINS_REPO_URI=$(aws ecr describe-repositories \
--repository-names jenkins \
--query 'repositories[].repositoryUri' --output text)
```

1. 次に、以下のコマンドを実行して、環境変数が正しく設定されていることを確認します。

`env | grep JENKINS`

JENKINS\_REPO\_URI が設定されていることを示す以下のような出力が表示されます。

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture2.png)

**注: ssh セッションが切断されたり、別の接続をオープンしたりした場合、この環境変数を再びエクスポートする必要があります。**

1. 環境がセットアップされたので、Docker のビルドコマンドを実行できます。**-t** を使用して、ECR リポジトリのタグを追加します。

`docker build -t ${JENKINS_REPO_URI}:lab-2-pipeline /home/ec2-user/lab-2-pipeline/src/jenkins`

1. Docker イメージを実行してイメージのリストを表示し、イメージがタグ付けされているリポジトリを表示します。

`docker images`

Jenkins イメージと ECR リポジトリが表示されるはずです。

1. 次に、docker push を使用して、Jenkins Docker イメージをローカルインスタンスから AWS ECR リポジトリにコピーします。

`docker push ${JENKINS_REPO_URI}:lab-2-pipeline`

1. 操作が完了したら、AWS マネジメントコンソール経由で、または以下のコマンドを実行して、ECR 内のイメージを表示できます。

`aws ecr list-images --repository-name jenkins`

Jenkins イメージをビルドして Elastic Container Registry にデプロイできたため、次のセクションに進みます。次のセクションでは、Jenkins を ECS サービスに変換し、オートメーションを使用して、MustacheMe アプリケーションの他のコンポーネントをコンテナ化された個別マイクロサービスのセットとしてビルドしてデプロイします。

## タスク 4: Jenkins Docker イメージを AWS ECS のサービスに変換する

1. Jenkins を Amazon ECS 内のサービスとして実行するということは、Jenkins Docker コンテナが応答しなくなった場合には ECS がこのコンテナを自動的に再起動することを意味します。このイメージは AWS マネジメントコンソールを使用してサービスとしてデプロイできますが、オートメーションの精神に基づき、AWS CloudFormation で使用できる YAML ファイルを作成しました。これにより、インフラストラクチャをプログラムによってデプロイおよび更新することが可能になります。多くの人は、YAML 形式の方が JSON よりも読み書きが簡単だと考えています。YAML ファイルを確認してみましょう。

`cat /home/ec2-user/lab-2-pipeline/scripts/jenkins-ecs-service.yaml`

ファイルの内容がわかりますか? ラボの後半ではもっと複雑な YAML ファイルが登場します。YAML ファイル内のいずれかの行の目的がわからない場合は、支援を求めてください。

1. それでは以下のコマンドを実行して、上記の YAML ファイルをテンプレートとして使用し、Jenkins をサービスとしてデプロイします。

```
aws cloudformation create-stack --stack-name JenkinsService \
--template-body file:///home/ec2-user/lab-2-pipeline/scripts/jenkins-ecs-service.yaml
```

このデプロイは、完了するかステータスが戻るまでに数分間かかる場合があります。CloudFormation ページの AWS マネジメントコンソールにスタックイベントが表示されます。

ページには、ステータスを更新するための更新ボタンがあります。

スタックは正しく作成されましたか? どのようなイベントが実行されましたか? イベントはどのような順序で実行されましたか? イベントとステータスは YAML ファイルに表示されていたものと一致したでしょうか。

## タスク 5: CloudFormation および CodePipeline を使用してマイクロサービス用の CI/CD プロセスを作成する

マイクロサービスごとに行う必要がある次のステップを以下に示します。

- マイクロサービス用の CodeCommit リポジトリを作成する

- マイクロサービス用の Jenkins ビルドジョブを作成する

- マイクロサービス用の CodePipeline を作成する

- マイクロサービス用の Application Load Balancer リスナーおよびターゲットグループを作成する

- Git リポジトリのクローンを作成し、Amazon CodeCommit リポジトリに 1 つのバージョンをコミットする

最初の 4 つのステップは、デプロイ用の YAML CloudFormation テンプレートにコード化されています。

1. 最初にこの YAML ファイルを見てみましょう。

`less /home/ec2-user/lab-2-pipeline/scripts/microservice-pipeline.yaml`


すべての入力パラメータが必須であることに注意してください。この理由は、テンプレートはテストを記述するラボの最後の部分だけでなく、3 つの各マイクロサービスで再利用するためです。

CloudFormation の重要な部分には、以下が含まれます。

- **JenkinsBuildJobResource** と呼ばれ、Lambda 関数として実装される Jenkins ジョブを作成するために使用されるカスタム CloudFormation リソース（Jenkins ジョブ構成 XML テンプレートファイルを取得し、ファイル内の指定されたパラメータを置換し、ファイルを Jenkins サーバーにアップロードして、新規ビルドプロジェクトを作成する）

- マイクロサービスと同じ名前で CodeCommit リポジトリを作成するために使用される CodeCommit リポジトリリソース

- Application Load Balancer の特定のポートに送信されたトラフィックをマイクロサービスに転送するために使用される Application Load Balancer リスナーリソース

- このマイクロサービス用の ECS サービスを接続するために ECS によって使用される Application Load Balancer ターゲットグループ

- 新規 git push コマンドでトリガーされるソースとしての CodeCommit リポジトリ、ビルドリソースとしての Jenkins、およびマイクロサービス ECS タスク定義を作成してマイクロサービスのための ECS サービスをデプロイする AWS Lambda 関数が含まれる CodePipeline リソース

1. それでは、AWS CLI を使用し、CloudFormation を使用してこのスタックを起動します。CLI を使用するのは、ラボの後の方でこのステップを自動化するためです。

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

1. CloudFormation スタックのステータスは、以下のコマンドを使用してコマンドラインで見ることができます。

```
aws cloudformation wait stack-create-complete \
--stack-name MustacheMeWebServerPipeline
```

1. スタックが正しく実行されたら、Git を使用して MustacheMe ウェブサーバーコードのクローンを独自の CodeCommit リポジトリに作成します。Git コマンドを実行する前に、リージョン用の別の環境変数を設定する必要があります。その後、Git を使用してリポジトリのクローンを作成できます。

```
export AWS_REGION=$(aws configure get region)

git clone \
https://git-codecommit.${AWS_REGION}.amazonaws.com/v1/repos/MustacheMeWebServer \
/home/ec2-user/repos/MustacheMeWebServer
```

クローンの作成先は空のリポジトリであるため、関連する警告を無視してかまいません。

1. リポジトリのクローンを作成した後で、ローカルリポジトリディレクトリにコードをコピーします。次に、Git を使用してすべてのファイルを追加し、コミットメッセージを追加し、初期コミットを実行します。


```
mv /home/ec2-user/lab-2-pipeline/src/MustacheMe/MustacheMeWebServer/* \
/home/ec2-user/repos/MustacheMeWebServer/

cd  /home/ec2-user/repos/MustacheMeWebServer

git add -A

git commit -m "Initial commit"

git push -u origin master
```

1. 変更内容を AWS CodeCommit にプッシュした後、CodePipeline が変更内容を取得して処理する動作を観察します。これは、CodePipeline が CodeCommit リポジトリのコミットを監視するように構成されているためです。この動作を AWS マネジメントコンソールを使って視覚的に確認することができます。

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture3.png)

お疲れ様でした。 デプロイを自動化し、最初のマイクロサービスをデプロイしました。 要約すると、マイクロサービスをデプロイするために以下のステップを行いました。


- CloudFormation スクリプトを実行してマイクロサービスのための以下のリソースを作成
- マイクロサービス用の CodeCommit リポジトリ
- Lambda 関数を介した Jenkins ジョブ、および Jenkins API を使用して新規 Jenkins ジョブをアップロードするカスタム CloudFormation リソース
- マイクロサービス用の CodePipeline（ソースコードが存在する CodeCommit リポジトリを、マイクロサービス用の Docker イメージをビルドして ECR にデプロイする Jenkins ビルドジョブに連携させ、最終的に CloudFormation テンプレート経由でマイクロサービスをデプロイする AWS Lambda 関数に接続）

- マイクロサービス用のローカル Git リポジトリにコミットされ、CodePipeline サービス経由でマイクロサービスのデプロイをトリガーする CodeCommit リポジトリにプッシュされたマイクロサービスのソースコード

- 残りのマイクロサービスについても、以下に示す同じ 5 つのステップを実行する必要あり

- Jenkins マイクロサービス用の CodeCommit リポジトリを作成する

- マイクロサービス用の Jenkins ビルドジョブを作成する

- マイクロサービス用の CodePipeline を作成する

- マイクロサービス用の Application Load Balancer リスナーおよびターゲットグループを作成する

- Git リポジトリのクローンを作成し、Amazon CodeCommit リポジトリに 1 つのバージョンをコミットする

これらは手動で実行できますが、スクリプトを使用してこれらを実行してみましょう。エラーが発生しにくく処理も高速です。スクリプトは既に使用したコマンドのグループです。

1. このバージョンのスクリプトは既に作成されています。

`cat /home/ec2-user/lab-2-pipeline/scripts/deploy-microservice.sh`

スクリプトをざっと眺めて、先ほど手動で実行したコマンドがどのように実行されるかを確認してください。

1. スクリプトでは、サービス名およびスクリプトを実行するポートという 2 つの情報を入力する必要があります。

`deploy-microservice.sh <MICROSESRVICE_NAME> <PORT>`

1. 以下のコマンドを実行して、残っている他の 2 つのマイクロサービスのためのパイプラインを構築します。

```
cd /home/ec2-user/lab-2-pipeline/scripts/

./deploy-microservice.sh MustacheMeProcessor 8082

./deploy-microservice.sh MustacheMeInfo 8092
```

1. これで、CodePipeline 管理コンソール画面に 3 種類のパイプラインが表示されるはずです。

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture4.png)

各 CodePipeline は失敗状態にあることに注意してください。これは、作成されたときに実行しようとしたが、マイクロサービスごとの CodeCommit リポジトリが空であったためです。コードがコミットされて CodeCommit リポジトリにプッシュされると、正しく実行されるはずの新しいリリースがすぐにトリガーされます。

1. 3 つのすべてのマイクロサービスが各パイプラインを通じてデプロイされると、ALB の URL を参照することによってこれらを表示できます。マイクロサービスの CloudFormation スタックである、**MustacheMeInfoStack**、**MustacheMeProcessorStack** および **MustachMeWebServerStack** の **3 つすべて**がデプロイされ、**CREATE\_COMPLETE** 状態になるまで待ちます。この状態は、ベースの CloudFormation スタックの [**出力**] タブから見ることができます。

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture5.png)

少し休憩を取り、画像に顔ひげを付けてマイクロサービスが動作することを確かめてみましょう。 MustacheMe ウェブアプリケーションはポート 8000 で実行されるため、アクセスするには上記の URL が必要であることを覚えておいてください。イメージ処理セクションが動作しない場合、MustacheMeProcessor マイクロサービスがまだデプロイされておらず、動作していないことが原因です。CloudFormation スタック名 **MustacheMeProcessorStack** が **CREATE\_COMPLETE** の状態になるまで待ちます。セッション情報および接続情報にデータが何も返されない場合は、MustacheMeInfo マイクロサービスがまだ稼働していないため、CloudFormation スタック名 **MustacheMeInfoStack** が  **CREATE\_COMPLETE** の状態になるまで待ちます。


## タスク 6: 各マイクロサービスデプロイパイプラインにテストフェーズを追加する（オプション）

1. 3 つのマイクロサービスがすべて動作したので、各マイクロサービスにテストアクションを追加して、各サービスが期待どおりに動作していることを確認することができます。これを行うには、Jenkins に統合されている [Postman](https://www.getpostman.com/) テストフレームワークを使用します。継続的インテグレーションプロセスの一部として Jenkins が起動され、postman テストスクリプトを実行して結果を出力します。いずれかのテストに失敗する場合、Jenkins ビルドは失敗します。

以下のコマンドを実行して、MustacheMeWebServer マイクロサービスの postman テストスクリプトを表示します。

`cat /home/ec2-user/repos/MustacheMeWebServer/postman-collection.json`

ファイルのコンテンツにより、マイクロサービスエンドポイントに対するテストがいくつか実行されることがわかります。

- ブートキャンプ用の Postman の「コレクション」を構成し、MustacheMe マイクロサービスの特定の URL にカスタマイズ完了

- エンドポイントが HTTP 応答コード 200 (OK) を返すかどうかテストする

- 返された html に ”Simple Mustache Service” というテキストが含まれているかどうかテストする

1. CloudFormation の update コマンドを使用して、マイクロサービスパイプライン CloudFormation テンプレートを更新することができます。これによって、マイクロサービスのエンドポイントをテストするための追加ステップが、ビルドパイプラインのデプロイステージの後に追加されます。**ExtendedFlag** という CloudFormation パラメータを変更して、追加された「Test」アクションでパイプラインを作成し、マイクロサービス用のテストプロジェクトを Jenkins にデプロイします。

最初に、更新される Cloudformation テンプレートを参照し、**SimpleCodePipeline** リソースの代わりに **ExtendedCodePipeline** という名前のリソースが作成されることに注目します。また、これは各マイクロサービスエンドポイントをテストする Jenkins ジョブである **JenkinsTestJobResource** というリソースも作成します。

`less /home/ec2-user/lab-2-pipeline/scripts/microservice-pipeline.yaml`

1. CodePipeline を変更するために、AWS マネジメントコンソールで CloudFormation サービスをクリックします。以下のスクリーンショットに示すように、**MustacheMeWebServerPipeline** という CloudFormation スタック名を選択し、[**スタックの更新**] をクリックします。

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture6.png)

1. \[**現在のテンプレートの使用**] をクリックし、[**次へ**] をクリックします。**ExtendedFlag** という名前のパラメータを選択し、下のスクリーンショットに示されているように [**true**] を選択してから、[**次へ**] をクリックします。

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture7.png)

1. \[**オプション**] ページでデフォルトを受け入れ、[**次へ**] をクリックします。

1. \[**確認**] ページに、現在デプロイされている内容および実行する必要がある変更に基づいて、CloudFormation が計算した変更セットが表示されます。以下のスクリーンショットに示すように、1 つの CodePipeline が削除されて別のものが追加され、さらに 1 つの Jenkins テストリソースが追加されていることが表示されているはずです。[**更新**] をクリックして変更を実装します。

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture8.png)

1. AWS マネジメントコンソールで CodePipeline サービスをクリックします。**MustacheMeWebServerPipelineExt** という名前のパイプラインを選択します。以下のスクリーンショットに示すように、**TestAction** というアクションを持つ **Test** という名前の追加ステージが存在することに注目します。

パイプラインはすべてのステージを通過する必要があるため、パイプラインが **Succeeded** 状態になるまで数分かかることに注意してください。

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture9.png)

1. テストアクションの Jenkins プロバイダーリンクをクリックすることによってテスト結果を検証できます。これにより、以下のようなページが開きます。Jenkins の **Admin** ユーザーのパスワードは、**JenkinsStack** CloudFormation スタックの **JenkinsPassword** の出力値として見つけることができます。

1.  正常なビルド番号 **\#2** をクリックし、[**Test Result**] ページをクリックします。

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture10.png)

1. ページの [**All Tests**] セクションの [**(root)**] リンクをクリックします。次に、ページの [**All Tests**] セクションの [**MustacheMeWebServer**] リンクをクリックします。これにより、postman のコレクションファイルからの 2 つのテストの実行に成功したことを示す以下のようなページが表示されます。

![](https://us-west-2-tcprod.s3.amazonaws.com/courses/ILT-DD-300-CORCEM/v3.3.1/lab-2-pipeline/images/Picture11.png)

1. 今度は以下の CLI コマンドを実行することによって、他の 2 つのマイクロサービス (MustacheMeProcessorPipeline および MustacheMeInfoPipeline) についてステップを繰り返します。

```
aws cloudformation update-stack --stack-name MustacheMeProcessorPipeline --use-previous-template --parameters ParameterKey=MicroserviceName,UsePreviousValue=true ParameterKey=RepoName,UsePreviousValue=true ParameterKey=PortNumber,UsePreviousValue=true ParameterKey=ExtendedFlag,ParameterValue=true

aws cloudformation update-stack --stack-name MustacheMeInfoPipeline --use-previous-template --parameters ParameterKey=MicroserviceName,UsePreviousValue=true ParameterKey=RepoName,UsePreviousValue=true ParameterKey=PortNumber,UsePreviousValue=true ParameterKey=ExtendedFlag,ParameterValue=true
```

これで、アプリケーションのビルド、テスト、および更新のための完全に自動化された CI/CD プロセスが完成しました。

**ラボ 2 はこれで終わりです。お楽しみいただけたでしょうか。**
