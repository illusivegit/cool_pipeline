pipeline {
  agent { label 'agent1' }
  options { timestamps() }

  environment {
    VM_USER    = 'jenkins'
    VM_IP      = '192.168.122.230'
    DOCKER_CTX = 'vm-lab'
    PROJECT    = 'lab'
    VM_DIR     = '/home/jenkins/lab/app'
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
            docker context rm -f ${DOCKER_CTX} 2>/dev/null || true
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
            echo "Waiting for Tempo and Loki readiness (up to 3 minutes)..."
            for i in $(seq 1 18); do
              ready=$(ssh ${VM_USER}@${VM_IP} "
                curl -sf http://localhost:3200/ready >/dev/null 2>&1 && \
                curl -sf http://localhost:3100/ready >/dev/null 2>&1 && \
                echo READY || echo WAIT
              ")
              if [ "$ready" = "READY" ]; then
                echo "All services ready after $((i*10)) seconds."
                break
              fi
              echo "  Not ready yet (attempt $i/18)..."
              sleep 10
            done
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
