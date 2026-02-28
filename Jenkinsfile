pipeline {
  agent { label 'docker-agent1' }
  options { timestamps() }

  environment {
    VM_USER    = 'deploy'
    VM_IP      = '192.168.122.230'
    DOCKER_CTX = 'vm-lab'
    PROJECT    = 'lab'
    VM_DIR     = '/home/deploy/lab/app'   
  }
  
  stages {
    stage('Sanity on agent') {
      steps {
        sh '''
          set -eu
          which ssh
          docker --version
          docker compose version
        '''
      }
    }

    stage('Ensure remote Docker context') {
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            ssh -o StrictHostKeyChecking=no ${VM_USER}@${VM_IP} 'echo ok'
            docker context ls | grep -q "^${DOCKER_CTX} " || \
              docker context create ${DOCKER_CTX} --docker "host=ssh://${VM_USER}@${VM_IP}"
            docker --context ${DOCKER_CTX} info
          '''
        }
      }
    }

    stage('Sync repo to VM') {
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            ssh ${VM_USER}@${VM_IP} "mkdir -p ${VM_DIR}"
            rsync -az --delete ./ ${VM_USER}@${VM_IP}:${VM_DIR}/
          '''
        }
      }
    }
    
    stage('Debug: verify compose paths') {
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            echo "== Local workspace PWD =="
            pwd
            echo "== Local workspace =="
            ls -la
            echo
            echo "== Remote VM dir =="
            ssh ${VM_USER}@${VM_IP} "ls -la ${VM_DIR} || true; \
              find ${VM_DIR} -maxdepth 2 -type f \\( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' \\) -print"
          '''
        }
      }
    }

    stage('Compose up (remote via SSH)') {
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            export DOCKER_BUILDKIT=1
            ssh ${VM_USER}@${VM_IP} "
              cd ${VM_DIR} && \
              PROJECT=${PROJECT} LAB_HOST=${VM_IP} ./start-lab.sh
              # Explicitly override the default PROJECT=lab and LAB_HOST=localhost variables using Jenkins-provided values
            "
          '''
        }
      }
    }

    stage('Smoke tests') {
      steps {
        sh '''
          set -eu
          curl -sf http://${VM_IP}:8080 >/dev/null 
          curl -sf http://${VM_IP}:3000/login >/dev/null 
          curl -sf http://${VM_IP}:9090/-/ready >/dev/null 
        '''
      }
    }
  }

  post {
    failure {
      echo "Hint: tail remote logs → docker --context ${DOCKER_CTX} compose --project-directory ${VM_DIR} -p ${PROJECT} logs --no-color --tail=200"
    }
  }
}
