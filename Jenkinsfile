pipeline {
  agent { label 'agent1' }
  options { timestamps() }

  environment {
    VM_USER    = 'jenkins'
    VM_IP      = '192.168.122.230'
    DOCKER_CTX = 'vm-lab'
    PROJECT    = 'lab'
    VM_DIR     = '/home/jenkins/lab/app'
    VAULT_ADDR = 'http://vault-server:8200'
    SONAR_SCANNER_VERSION = '8.0.1.6346'
    TRIVY_VERSION = '0.69.3'
    GITLEAKS_VERSION = '8.30.0'
    ZAP_VERSION = '2.17.0'
  }

  stages {
    stage('Sanity on agent') {
      steps {
        sh '''
          set -eu
          which ssh
          docker --version
          docker compose version
          curl --version | head -1
          jq --version
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

    stage('Secret scan (gitleaks)') {
      steps {
        sh '''
          set -eu

          # ── Install gitleaks if not cached ─────────────────────
          GITLEAKS_DIR="${WORKSPACE}/.gitleaks"
          GITLEAKS_BIN="${GITLEAKS_DIR}/gitleaks"

          if [ ! -x "${GITLEAKS_BIN}" ] || \
             [ "$(${GITLEAKS_BIN} version 2>/dev/null)" != "${GITLEAKS_VERSION}" ]; then
            echo "Installing gitleaks ${GITLEAKS_VERSION}..."
            mkdir -p "${GITLEAKS_DIR}"
            curl -sfL \
              "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
              -o "${GITLEAKS_DIR}/gitleaks.tar.gz"
            tar -xzf "${GITLEAKS_DIR}/gitleaks.tar.gz" -C "${GITLEAKS_DIR}" gitleaks
            rm -f "${GITLEAKS_DIR}/gitleaks.tar.gz"
          else
            echo "Using cached gitleaks ${GITLEAKS_VERSION}"
          fi

          # ── Scan git history for secrets ───────────────────────
          echo "Scanning git history for secrets..."
          "${GITLEAKS_BIN}" git \
            -f sarif \
            -r "${WORKSPACE}/gitleaks-report.sarif" \
            --no-banner
        '''
      }
    }

    stage('SAST (SonarQube)') {
      steps {
        withCredentials([
          string(credentialsId: 'vault-role-id',   variable: 'VAULT_ROLE_ID'),
          string(credentialsId: 'vault-secret-id', variable: 'VAULT_SECRET_ID')
        ]) {
          sh '''
            set -eu

            # ── Authenticate to Vault via AppRole ──────────────────────
            echo "Authenticating to Vault..."
            VAULT_TOKEN=$(curl -sf --max-time 10 \
              --request POST \
              --data "{\\"role_id\\":\\"${VAULT_ROLE_ID}\\",\\"secret_id\\":\\"${VAULT_SECRET_ID}\\"}" \
              "${VAULT_ADDR}/v1/auth/approle/login" \
              | jq -re '.auth.client_token')

            # ── Fetch SonarQube secrets from Vault KV ──────────────────
            echo "Fetching SonarQube credentials from Vault..."
            sonar_json=$(curl -sf --max-time 10 \
              -H "X-Vault-Token: ${VAULT_TOKEN}" \
              "${VAULT_ADDR}/v1/secret/data/lab/sonarqube")

            SONAR_TOKEN=$(echo "$sonar_json" | jq -re '.data.data.SONAR_TOKEN')
            SONAR_HOST_URL=$(echo "$sonar_json" | jq -re '.data.data.SONAR_HOST_URL')

            # ── Install sonar-scanner if not cached ────────────────────
            SCANNER_DIR="${WORKSPACE}/.sonar-scanner"
            SCANNER_BIN="${SCANNER_DIR}/sonar-scanner-${SONAR_SCANNER_VERSION}-linux-x64/bin/sonar-scanner"

            if [ ! -x "${SCANNER_BIN}" ]; then
              echo "Installing sonar-scanner ${SONAR_SCANNER_VERSION}..."
              mkdir -p "${SCANNER_DIR}"
              curl -sfL \
                "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip" \
                -o "${SCANNER_DIR}/scanner.zip"
              unzip -qo "${SCANNER_DIR}/scanner.zip" -d "${SCANNER_DIR}"
              rm -f "${SCANNER_DIR}/scanner.zip"
              echo "  Installed to ${SCANNER_DIR}"
            else
              echo "Using cached sonar-scanner ${SONAR_SCANNER_VERSION}"
            fi

            # ── Run the scan ───────────────────────────────────────────
            # sonar.login works with both SonarQube 9.x and 10+
            echo "Running SonarQube analysis..."
            "${SCANNER_BIN}" \
              -Dsonar.host.url="${SONAR_HOST_URL}" \
              -Dsonar.login="${SONAR_TOKEN}" \
              -Dsonar.projectBaseDir="${WORKSPACE}"
          '''
        }
      }
    }

    stage('Dependency audit (pip-audit)') {
      steps {
        sh '''
          set -eu

          # ── Install pip-audit in a venv if not cached ──────────
          PIPAUDIT_DIR="${WORKSPACE}/.pip-audit-venv"
          PIPAUDIT_BIN="${PIPAUDIT_DIR}/bin/pip-audit"

          if [ ! -x "${PIPAUDIT_BIN}" ]; then
            echo "Installing pip-audit..."
            python3 -m venv "${PIPAUDIT_DIR}"
            "${PIPAUDIT_DIR}/bin/pip" install --quiet pip-audit
          else
            echo "Using cached pip-audit"
          fi

          # ── Audit Python dependencies ──────────────────────────
          echo "Auditing Python dependencies..."
          "${PIPAUDIT_BIN}" -r backend/requirements.txt || true
        '''
      }
    }

    stage('Fetch secrets from Vault') {
      steps {
        sshagent(credentials: ['vm-ssh']) {
          withCredentials([
            string(credentialsId: 'vault-role-id',   variable: 'VAULT_ROLE_ID'),
            string(credentialsId: 'vault-secret-id', variable: 'VAULT_SECRET_ID')
          ]) {
            sh '''
              set -eu
              ssh ${VM_USER}@${VM_IP} "
                cd ${VM_DIR} && \
                VAULT_ADDR=http://vault-server:8200 \
                VAULT_ROLE_ID=${VAULT_ROLE_ID} \
                VAULT_SECRET_ID=${VAULT_SECRET_ID} \
                make fetch-secrets
              "
            '''
          }
        }
      }
    }

    stage('Build images') {
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            ssh ${VM_USER}@${VM_IP} "
              cd ${VM_DIR} && \
              make render-alertmanager && \
              DOCKER_BUILDKIT=1 docker compose -p ${PROJECT} build
            "
          '''
        }
      }
    }

    stage('Image scan (Trivy)') {
      steps {
        sh '''
          set -eu

          # ── Install Trivy if not cached ──────────────────────
          TRIVY_DIR="${WORKSPACE}/.trivy"
          TRIVY_BIN="${TRIVY_DIR}/trivy"

          if [ ! -x "${TRIVY_BIN}" ] || \
             [ "$(${TRIVY_BIN} version 2>/dev/null | awk '/^Version:/{print $2}')" != "${TRIVY_VERSION}" ]; then
            echo "Installing Trivy ${TRIVY_VERSION}..."
            mkdir -p "${TRIVY_DIR}"
            curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
              | sh -s -- -b "${TRIVY_DIR}" v${TRIVY_VERSION}
          else
            echo "Using cached Trivy ${TRIVY_VERSION}"
          fi

          # ── Scan via agent's local Docker daemon ─────────────
          # Report HIGH + CRITICAL (informational)
          echo "Scanning built images for vulnerabilities..."
          "${TRIVY_BIN}" image \
            --severity CRITICAL,HIGH \
            --scanners vuln \
            ${PROJECT}-flask-backend:latest || true

          # Gate on CRITICAL only (pipeline fails)
          "${TRIVY_BIN}" image \
            --severity CRITICAL \
            --exit-code 1 \
            --scanners vuln \
            --quiet \
            ${PROJECT}-flask-backend:latest
        '''
      }
    }

    stage('Deploy') {
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            ssh ${VM_USER}@${VM_IP} "
              cd ${VM_DIR} && \
              docker compose -p ${PROJECT} up -d
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

    stage('DAST (OWASP ZAP)') {
      steps {
        sh '''
          set -eu

          # ── Install ZAP if not cached ──────────────────────────
          ZAP_DIR="${WORKSPACE}/.zap"
          ZAP_HOME="${ZAP_DIR}/ZAP_${ZAP_VERSION}"
          ZAP_REPORTS="${WORKSPACE}/zap-reports"

          if [ ! -x "${ZAP_HOME}/zap.sh" ]; then
            echo "Installing ZAP ${ZAP_VERSION}..."
            mkdir -p "${ZAP_DIR}"
            curl -sfL \
              "https://github.com/zaproxy/zaproxy/releases/download/v${ZAP_VERSION}/ZAP_${ZAP_VERSION}_Linux.tar.gz" \
              -o "${ZAP_DIR}/zap.tar.gz"
            tar -xzf "${ZAP_DIR}/zap.tar.gz" -C "${ZAP_DIR}"
            rm -f "${ZAP_DIR}/zap.tar.gz"
            echo "  Installed to ${ZAP_HOME}"
          else
            echo "Using cached ZAP ${ZAP_VERSION}"
          fi

          # ── Write automation plan ──────────────────────────────
          mkdir -p "${ZAP_REPORTS}"

          cat > "${ZAP_REPORTS}/zap-baseline-plan.yaml" << ZAPPLAN
---
env:
  contexts:
    - name: baseline
      urls:
        - http://${VM_IP}:8080
  parameters:
    failOnError: true
    failOnWarning: false
    progressToStdout: true

jobs:
  - type: passiveScan-config
    parameters:
      maxAlertsPerRule: 10
      scanOnlyInScope: true

  - type: spider
    parameters:
      maxDuration: 1
      maxDepth: 5

  - type: passiveScan-wait
    parameters:
      maxDuration: 5

  - type: report
    parameters:
      template: traditional-json
      reportDir: ${ZAP_REPORTS}
      reportFile: zap-report
      displayReport: false
    risks:
      - high
      - medium
      - low
      - info

  - type: exitStatus
    parameters: {}
ZAPPLAN

          # ── Run ZAP baseline scan ─────────────────────────────
          echo "Running OWASP ZAP baseline scan..."
          "${ZAP_HOME}/zap.sh" -cmd \
            -autorun "${ZAP_REPORTS}/zap-baseline-plan.yaml"
        '''
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
