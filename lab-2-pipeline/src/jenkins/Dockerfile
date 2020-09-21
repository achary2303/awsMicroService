FROM awsbootcamp/jenkins

# Setup the Jenkins Plugins and copy groovy scripts
COPY groovy-scripts/*.groovy /usr/share/jenkins/ref/init.groovy.d/
RUN /usr/local/bin/install-plugins.sh aws-codepipeline:0.27 matrix-auth:1.4 junit:1.18 matrix-project:1.7.1
