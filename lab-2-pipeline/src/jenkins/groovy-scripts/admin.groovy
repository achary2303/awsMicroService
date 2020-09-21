import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstance()

def hudsonRealm = new HudsonPrivateSecurityRealm(false)

def env = System.getenv()
String user= env['JENKINS_USERNAME']
if ( !user ) {
  user='admin'
}

String password= env['JENKINS_PASSWORD']

hudsonRealm.createAccount(user, password)
instance.setSecurityRealm(hudsonRealm)
def strategy = new GlobalMatrixAuthorizationStrategy()
strategy.add(Jenkins.ADMINISTER, user)
instance.setAuthorizationStrategy(strategy)
instance.save()
