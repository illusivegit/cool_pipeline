// ============================================================================
// Pipeline v2 — Build Once, Deploy Many (parameterized + rollback support)
// ============================================================================
//
// Modes:
//   full           — Normal CI/CD: commit → build → test → promote
//   rollback-fast  — Pattern 1: redeploy a known-good registry artifact
//   rollback-safe  — Pattern 2: test artifact against current env, then promote
//
// Stage execution matrix:
//   ┌───────────────────────────┬──────┬───────────────┬───────────────┐
//   │ Stage                     │ full │ rollback-fast  │ rollback-safe │
//   ├───────────────────────────┼──────┼───────────────┼───────────────┤
//   │ Sanity                    │  ✓   │      ✓        │      ✓        │
//   │ Docker context            │  ✓   │      ✓        │      ✓        │
//   │ Sync repo to VM           │  ✓   │      ✓        │      ✓        │
//   │ Lint                      │  ✓   │      ─        │      ─        │
//   │ Secret scan               │  ✓   │      ─        │      ─        │
//   │ SAST (SonarQube)          │  ✓   │      ─        │      ─        │
//   │ Dependency audit          │  ✓   │      ─        │      ─        │
//   │ Fetch secrets             │  ✓   │      ✓        │      ✓        │
//   │ Build + Tag + Push        │  ✓   │      ─        │      ─        │
//   │ Image scan (Trivy)        │  ✓   │      ─        │      ─        │
//   │ Resolve tag               │  ✓   │      ✓        │      ✓        │
//   │ Test deploy               │  ✓   │      ─        │      ✓        │
//   │ Health (test)             │  ✓   │      ─        │      ✓        │
//   │ Observability tests       │  ✓   │      ─        │      ✓        │
//   │ DAST (ZAP)                │  ✓   │      ─        │      ✓        │
//   │ Teardown test             │  ✓   │      ─        │      ✓        │
//   │ Promote                   │  ✓   │      ✓        │      ✓        │
//   │ Health (prod)             │  ✓   │      ✓        │      ✓        │
//   │ State contract            │  ✓   │      ✓        │      ✓        │
//   │ Version validation        │  ✓   │      ✓        │      ✓        │
//   └───────────────────────────┴──────┴───────────────┴───────────────┘
// ============================================================================

pipeline {
  agent { label 'agent1' }
  options { timestamps() }

  parameters {
    choice(name: 'MODE', choices: ['full', 'rollback-fast', 'rollback-safe'],
           description: 'full = normal CI/CD | rollback-fast = redeploy artifact (Pattern 1) | rollback-safe = test then promote (Pattern 2)')
    string(name: 'DEPLOY_TAG', defaultValue: '',
           description: 'Registry image tag for rollback modes (e.g. abc1234). Ignored in full mode.')
  }

  environment {
    VM_USER    = 'jenkins'
    VM_IP      = '192.168.122.230'
    DOCKER_CTX = 'vm-lab'
    PROJECT    = 'lab'
    VM_DIR     = '/home/jenkins/lab/app'
    VAULT_ADDR    = 'http://vault-server:8200'
    VM_VAULT_ADDR = 'http://192.168.122.1:8200'
    REGISTRY      = 'localhost:5050'
    SONAR_SCANNER_VERSION = '8.0.1.6346'
    TRIVY_VERSION = '0.69.3'
    GITLEAKS_VERSION = '8.30.0'
    ZAP_VERSION = '2.17.0'
  }

  stages {

    // ── Infrastructure ────────────────────────────────────────────────────────

    stage('Sanity on agent') {
      steps {
        sh '''
          set -eu
          echo "=== Agent toolchain ==="
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
            REPO_URL=$(git remote get-url origin)
            # Jenkins SCM checkout may use detached HEAD; fall back to
            # GIT_BRANCH env var set by Jenkins Git plugin (e.g. origin/v2)
            REPO_BRANCH=$(git rev-parse --abbrev-ref HEAD)
            if [ "${REPO_BRANCH}" = "HEAD" ]; then
              REPO_BRANCH=$(echo "${GIT_BRANCH:-main}" | sed 's|^origin/||')
            fi

            ssh ${VM_USER}@${VM_IP} "
              if [ -d ${VM_DIR}/.git ]; then
                cd ${VM_DIR} && \
                git fetch origin && \
                git checkout ${REPO_BRANCH} && \
                git reset --hard origin/${REPO_BRANCH}
              else
                mkdir -p \$(dirname ${VM_DIR}) && \
                git clone --branch ${REPO_BRANCH} ${REPO_URL} ${VM_DIR}
              fi
            "
          '''
        }
      }
    }

    // ── Commit Stage (full mode only) ─────────────────────────────────────────

    stage('Lint') {
      when { expression { params.MODE == 'full' } }
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
      when { expression { params.MODE == 'full' } }
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
          if [ -d ".git" ]; then
            echo "Scanning git history for secrets..."
            "${GITLEAKS_BIN}" git \
              -f sarif \
              -r "${WORKSPACE}/gitleaks-report.sarif" \
              --no-banner
          else
            echo "No .git directory found — skipping gitleaks scan"
          fi
        '''
      }
    }

    stage('SAST (SonarQube)') {
      when { expression { params.MODE == 'full' } }
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
      when { expression { params.MODE == 'full' } }
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

    // ── Build Stage (full mode only) ──────────────────────────────────────────

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
                VAULT_ADDR=${VM_VAULT_ADDR} \
                VAULT_ROLE_ID=${VAULT_ROLE_ID} \
                VAULT_SECRET_ID=${VAULT_SECRET_ID} \
                make fetch-secrets
              "
            '''
          }
        }
      }
    }

    stage('Build + Tag + Push') {
      when { expression { params.MODE == 'full' } }
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            GIT_SHA=$(git rev-parse --short=7 HEAD)

            ssh ${VM_USER}@${VM_IP} "
              cd ${VM_DIR} && \
              make render-alertmanager && \
              DOCKER_BUILDKIT=1 docker compose -p ${PROJECT} build backend && \
              docker tag ${PROJECT}-flask-backend:latest \
                ${REGISTRY}/${PROJECT}-flask-backend:${GIT_SHA} && \
              docker push ${REGISTRY}/${PROJECT}-flask-backend:${GIT_SHA}
            "

            # Persist tag for downstream stages
            echo "${GIT_SHA}" > ${WORKSPACE}/.git-sha
            echo "Built and pushed: ${REGISTRY}/${PROJECT}-flask-backend:${GIT_SHA}"
          '''
        }
      }
    }

    stage('Image scan (Trivy)') {
      when { expression { params.MODE == 'full' } }
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            GIT_SHA=$(cat ${WORKSPACE}/.git-sha)

            ssh ${VM_USER}@${VM_IP} "
              TRIVY_DIR=/home/jenkins/.trivy
              TRIVY_BIN=\\${TRIVY_DIR}/trivy

              if [ ! -x \\${TRIVY_BIN} ] || \\
                 [ \\\"\\$(\\${TRIVY_BIN} version 2>/dev/null | awk '/^Version:/{print \\$2}')\\\" != '${TRIVY_VERSION}' ]; then
                echo 'Installing Trivy ${TRIVY_VERSION}...'
                mkdir -p \\${TRIVY_DIR}
                curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \\
                  | sh -s -- -b \\${TRIVY_DIR} v${TRIVY_VERSION}
              else
                echo 'Using cached Trivy ${TRIVY_VERSION}'
              fi

              echo 'Scanning for CRITICAL+HIGH vulnerabilities...'
              \\${TRIVY_BIN} image \\
                --severity CRITICAL,HIGH --scanners vuln \\
                ${REGISTRY}/${PROJECT}-flask-backend:${GIT_SHA} || true

              echo 'Gating on CRITICAL vulnerabilities...'
              \\${TRIVY_BIN} image \\
                --severity CRITICAL --exit-code 1 --scanners vuln --quiet \\
                ${REGISTRY}/${PROJECT}-flask-backend:${GIT_SHA}
            "
          '''
        }
      }
    }

    // ── Convergence Point ─────────────────────────────────────────────────────

    stage('Resolve tag') {
      steps {
        script {
          if (params.MODE == 'full') {
            env.RELEASE_TAG = readFile("${WORKSPACE}/.git-sha").trim()
          } else {
            if (!params.DEPLOY_TAG?.trim()) {
              error("DEPLOY_TAG is required for rollback modes (e.g. abc1234)")
            }
            env.RELEASE_TAG = params.DEPLOY_TAG.trim()
          }
          echo "Release tag resolved: ${env.RELEASE_TAG}"
          echo "Image: ${env.REGISTRY}/${env.PROJECT}-flask-backend:${env.RELEASE_TAG}"
        }
      }
    }

    // ── Test Stage (full + rollback-safe) ─────────────────────────────────────

    stage('Test deploy') {
      when { expression { params.MODE in ['full', 'rollback-safe'] } }
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            ssh ${VM_USER}@${VM_IP} "
              cd ${VM_DIR} && \
              make render-alertmanager && \
              BACKEND_IMAGE=${REGISTRY}/${PROJECT}-flask-backend:${RELEASE_TAG} \
              BACKEND_PORT=9000 FRONTEND_PORT=9080 GRAFANA_PORT=9300 \
              PROMETHEUS_PORT=9190 ALERTMANAGER_PORT=9193 \
              OTEL_GRPC_PORT=4327 OTEL_HTTP_PORT=4328 \
              NODE_EXPORTER_PORT=9110 \
              docker compose \
                -f docker-compose.yml \
                -f docker-compose.test.yml \
                -p ${PROJECT}-test up -d
            "
          '''
        }
      }
    }

    stage('Health checks (test)') {
      when { expression { params.MODE in ['full', 'rollback-safe'] } }
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            echo "Waiting for test environment readiness (up to 3 minutes)..."
            for i in $(seq 1 18); do
              ready=$(ssh ${VM_USER}@${VM_IP} "
                curl -sf http://localhost:9080/ >/dev/null 2>&1 && \
                curl -sf http://localhost:9000/health >/dev/null 2>&1 && \
                echo READY || echo WAIT
              ")
              if [ "$ready" = "READY" ]; then
                echo "Test environment ready after $((i*10)) seconds."
                break
              fi
              if [ "$i" -eq 18 ]; then
                echo "ERROR: Test environment did not become ready in 180s"
                exit 1
              fi
              echo "  Not ready yet (attempt $i/18)..."
              sleep 10
            done

            # Extended endpoint verification on test ports
            echo "Running test environment endpoint checks..."
            ssh ${VM_USER}@${VM_IP} "
              curl -sf http://localhost:9080/           >/dev/null && echo 'PASS  Frontend (test:9080)'
              curl -sf http://localhost:9000/health     >/dev/null && echo 'PASS  Backend /health (test:9000)'
              curl -sf http://localhost:9000/metrics    >/dev/null && echo 'PASS  Backend /metrics (test:9000)'
              curl -sf http://localhost:9190/-/healthy  >/dev/null && echo 'PASS  Prometheus (test:9190)'
              curl -sf http://localhost:9300/api/health >/dev/null && echo 'PASS  Grafana (test:9300)'
            "
          '''
        }
      }
    }

    stage('Observability integration tests') {
      when { expression { params.MODE in ['full', 'rollback-safe'] } }
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            echo "Running observability integration tests against test environment..."
            ssh ${VM_USER}@${VM_IP} "
              cd ${VM_DIR} && \
              bash scripts/observability-integration-tests.sh localhost 9000 9190 3200 3100
            "
          '''
        }
      }
    }

    stage('DAST (OWASP ZAP)') {
      when { expression { params.MODE in ['full', 'rollback-safe'] } }
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

          # ── Write automation plan (targets TEST environment) ───
          mkdir -p "${ZAP_REPORTS}"

          cat > "${ZAP_REPORTS}/zap-baseline-plan.yaml" << ZAPPLAN
---
env:
  contexts:
    - name: baseline
      urls:
        - http://${VM_IP}:9080
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

          # ── Run ZAP baseline scan against TEST environment ─────
          echo "Running OWASP ZAP baseline scan against test environment..."
          "${ZAP_HOME}/zap.sh" -cmd \
            -autorun "${ZAP_REPORTS}/zap-baseline-plan.yaml"
        '''
      }
    }

    stage('Teardown test') {
      when { expression { params.MODE in ['full', 'rollback-safe'] } }
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            echo "Tearing down test environment..."
            ssh ${VM_USER}@${VM_IP} "
              cd ${VM_DIR} && \
              docker compose \
                -f docker-compose.yml \
                -f docker-compose.test.yml \
                -p ${PROJECT}-test down -v --remove-orphans
            "
            echo "Test environment torn down."
          '''
        }
      }
    }

    // ── Promote Stage (all modes) ─────────────────────────────────────────────

    stage('Promote') {
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            echo "Promoting ${RELEASE_TAG} to production..."
            ssh ${VM_USER}@${VM_IP} "
              cd ${VM_DIR} && \
              make render-alertmanager && \
              BACKEND_IMAGE=${REGISTRY}/${PROJECT}-flask-backend:${RELEASE_TAG} \
              docker compose -p ${PROJECT} up -d
            "
            echo "Production deploy complete."
          '''
        }
      }
    }

    stage('Health checks (prod)') {
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

  // ── Post Actions ────────────────────────────────────────────────────────────

  post {
    always {
      sshagent(credentials: ['vm-ssh']) {
        sh '''
          ssh ${VM_USER}@${VM_IP} "
            cd ${VM_DIR} && \
            docker compose -f docker-compose.yml -f docker-compose.test.yml \
              -p ${PROJECT}-test down -v --remove-orphans 2>/dev/null || true
          " || true
        '''
      }
    }
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
