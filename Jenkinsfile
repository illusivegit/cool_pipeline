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

    stage('Lint') {
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            ssh ${VM_USER}@${VM_IP} "
              cd ${VM_DIR} && \
              find lib/ scripts/ -name '*.sh' -exec shellcheck -x {} + 2>/dev/null || echo 'shellcheck not installed — skipping'
            "
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
              make up
            "
          '''
        }
      }
    }

    stage('Health checks') {
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            echo "Waiting for services to stabilize..."
            sleep 15
            ssh ${VM_USER}@${VM_IP} "
              cd ${VM_DIR} && \
              LAB_HOST=${VM_IP} make health
            "
          '''
        }
      }
    }

    stage('State contract') {
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            ssh ${VM_USER}@${VM_IP} "
              cd ${VM_DIR} && \
              LAB_HOST=${VM_IP} make state
            "
          '''
        }
      }
    }

    stage('Version validation') {
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            ssh ${VM_USER}@${VM_IP} "
              cd ${VM_DIR} && \
              make validate-versions
            "
          '''
        }
      }
    }
  }

  post {
    failure {
      sshagent(credentials: ['vm-ssh']) {
        sh '''
          ssh ${VM_USER}@${VM_IP} "
            cd ${VM_DIR} && \
            docker compose -p ${PROJECT} logs --no-color --tail=200
          " > failure-logs.txt 2>&1 || true
        '''
      }
      archiveArtifacts artifacts: 'failure-logs.txt', allowEmptyArchive: true
      echo "Hint: check failure-logs.txt artifact for container logs"
    }
    success {
      sshagent(credentials: ['vm-ssh']) {
        sh '''
          ssh ${VM_USER}@${VM_IP} "
            cat ${VM_DIR}/artifacts/state/*/state.kv 2>/dev/null | tail -30 || echo 'No state artifact found'
          "
        '''
      }
    }
  }
}
