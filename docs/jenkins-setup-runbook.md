# Jenkins CI/CD Setup Runbook & After-Action Report

Date: 2026-03-06

## Overview

Stand up a containerized Jenkins controller + inbound agent on Docker Desktop, configure it to run the project's `Jenkinsfile`, and set up Postfix as a local SMTP relay for alert email delivery. What should have been straightforward turned into a minefield of mismatches, invisible trailing spaces, and sender-rewrite gotchas.

---

## 1. Jenkins Controller

### What worked

```bash
docker network create jenkins-network

docker run -d \
  --name jenkins-controller \
  --network jenkins-network \
  -p 8080:8080 \
  -p 50000:50000 \
  --restart=on-failure \
  -v jenkins_volume:/var/jenkins_home \
  jenkins/jenkins:2.541.2-lts-jdk21
```

### Gotcha: Pin the image

`jenkins/jenkins:lts-jdk21` is a rolling tag. Pin to a specific version (e.g., `2.541.2-lts-jdk21`) so you don't get surprise upgrades on `docker pull`.

Find your current version:
```bash
docker exec jenkins-controller cat /var/jenkins_home/config.xml | grep version
```

### Initial password

```bash
docker exec -it jenkins-controller cat /var/jenkins_home/secrets/initialAdminPassword
```

---

## 2. Plugin Selection (Setup Wizard)

### Required by the Jenkinsfile

| Plugin | Category | Why |
|---|---|---|
| Pipeline | Pipelines and Continuous Delivery | `pipeline {}` DSL |
| SSH Agent | Build Features | `sshagent(credentials: ['vm-ssh'])` |
| Timestamper | Build Features | `options { timestamps() }` |
| Credentials Binding | Build Features | Exposes credentials to build steps |

### Required by the workflow

| Plugin | Category | Why |
|---|---|---|
| Git | Source Code Management | Pull repo into workspace |
| GitHub | Source Code Management | Webhook triggers, commit status |

### Recommended

| Plugin | Category | Why |
|---|---|---|
| Pipeline Graph View | Pipelines and Continuous Delivery | Visual stage graph |
| Build Timeout | Build Features | Kill hung SSH sessions |
| Workspace Cleanup | Build Features | Clean workspace between runs |
| Configuration as Code | Organization and Administration | Reproducible controller config |

### Skip everything else

The remaining 42 plugins (Ant, Maven, LDAP, ClearCase, etc.) are irrelevant. Install later from Plugin Manager if needed.

---

## 3. Inbound Agent Image

### Problem: Dockerfile only installed jq

The original Dockerfile installed `jq` but the image was named `jenkins-inbound-agent-with-jq-docker-rsync`. The Jenkinsfile's "Sanity on agent" stage checks for `docker`, `docker compose`, `rsync`, and `ssh` — all missing.

### Problem: Using `latest` tag

`jenkins/inbound-agent:latest` is a rolling tag. Pin it.

### Fixed Dockerfile

File: `jenkins/jenkins-inbound-agent-with-jq-docker-rsync`

```dockerfile
FROM jenkins/inbound-agent:3355.v388858a_47b_33-15-jdk21

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg jq openssh-client git; \
    install -m 0755 -d /etc/apt/keyrings; \
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      -o /etc/apt/keyrings/docker.asc; \
    chmod a+r /etc/apt/keyrings/docker.asc; \
    . /etc/os-release; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
      https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin rsync; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

USER jenkins
```

Key decisions:
- `docker-ce-cli` only — agent doesn't need the daemon, just the CLI for remote Docker context over SSH
- `docker-compose-plugin` — provides `docker compose` v2
- `--no-install-recommends` — keeps image lean

### Build command

The file is a Dockerfile, not a directory. Use `-f`:

```bash
docker build -t jenkins-inbound-agent-with-jq-docker-rsync \
  -f jenkins/jenkins-inbound-agent-with-jq-docker-rsync jenkins/
```

**Wrong** (treats the file as a build context directory):
```bash
docker build -t jenkins-inbound-agent-with-jq-docker-rsync \
  jenkins/jenkins-inbound-agent-with-jq-docker-rsync
# ERROR: unable to prepare context: path "..." not found
```

---

## 4. Agent Node Configuration

### Problem: "Unknown client name: docker-agent1"

The agent container was started with `-name docker-agent1` but no node with that name existed in Jenkins. The node must be created in the Jenkins UI **before** starting the agent container.

**Fix**: Manage Jenkins > Nodes > New Node. The `-name` in `docker run` must exactly match the node name in Jenkins.

### Problem: Name mismatch (agent1 vs docker-agent1)

The node was created as `agent1` in Jenkins but the `docker run` used `-name docker-agent1`.

**Fix**: Use `-name agent1` to match the node name. Set the node's **Labels** field to `docker-agent1` to match `agent { label 'docker-agent1' }` in the Jenkinsfile.

Key distinction: `agent { label '...' }` matches the **Labels** field, not the node name.

### Problem: AccessDeniedException /home/deploy

The node's **Remote root directory** was set to `/home/deploy/agent1` but the `jenkins/inbound-agent` image runs as user `jenkins` (home: `/home/jenkins`). The jenkins user can't create `/home/deploy`.

**Fix**: Set Remote root directory to `/home/jenkins/agent`.

**Important**: After changing the Remote root directory, you must disconnect the agent and restart the container. The agent caches its workspace path from the initial connection.

```bash
# In Jenkins UI: Nodes > agent1 > Disconnect
docker restart jenkins-agent
```

### Working agent launch command

```bash
docker run -d --name jenkins-agent --init --restart=on-failure --network jenkins-network jenkins-inbound-agent-with-jq-docker-rsync -url http://jenkins-controller:8080 -secret <SECRET> -name agent1
```

Put it on one line to avoid trailing-space-after-backslash problems (see below).

---

## 5. The Trailing Space Problem

Three separate `docker run` attempts failed because of invisible trailing spaces after `\` line-continuation characters.

```bash
# THIS BREAKS — trailing space after backslash on line 2
docker run -d \
  --name jenkins-agent \                    # <-- space after \
  --init \
```

Bash interprets `\ ` (backslash-space) as an escaped space, not a line continuation. Everything after the break becomes a separate command, producing errors like:

- `bash: -url: command not found`
- `docker: invalid reference format`
- `bash: --init: command not found`

**Lesson**: Either put the whole command on one line, or be paranoid about trailing whitespace. In most editors, enable "show whitespace" or "trim trailing whitespace on save".

---

## 6. Postfix SMTP Relay

### Goal

Local-only Postfix relay so `mail` (and eventually Alertmanager) can send emails through Yahoo's SMTP.

### Problem 1: Missing SASL configuration

A pre-existing Postfix installation had no SASL auth configured. Yahoo rejected relay attempts silently.

Required settings that were missing:
```
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
```

### Problem 2: Wrong SASL username

Used `walid@yahoo.com` instead of `walidahmm@yahoo.com`. Yahoo locked the account after repeated failed auth attempts (`535 5.7.0 Too many bad auth attempts`). Had to wait ~15 minutes for the lockout to clear.

### Problem 3: Envelope sender mismatch (the big one)

After fixing auth, Yahoo still rejected with `550 Request failed; Mailbox unavailable`.

**Root cause**: The `mail` command sends as `wally@Maria.maria.com` (local user@hostname). Yahoo requires the `MAIL FROM` envelope sender to match the authenticated account.

**What didn't work**: `smtp_generic_maps` with a specific user mapping. It mapped `root@Maria.maria.com` but the actual sender was `wally@Maria.maria.com`. Every local user would need a separate entry.

**What worked**: `sender_canonical_maps` with a regexp catch-all that rewrites ALL senders:

```
# /etc/postfix/sender_canonical
/.*/  walidahmm@yahoo.com
```

Combined with `smtp_header_checks` to rewrite the `From:` header:

```
# /etc/postfix/header_checks
/^From:.*/ REPLACE From: walidahmm@yahoo.com
```

### Why the VM version didn't need sender rewriting

In the Infrastructure Automation Framework, **Alertmanager** sends the email — not `mail`. Alertmanager's config sets `smtp_from: 'walidahmm@yahoo.com'` directly, so the envelope sender is already correct. Postfix just relays it without rewriting. The `mail` command on a local workstation uses the local unix identity, which Yahoo rejects.

### Working install script

```bash
sudo bash /tmp/install-postfix-relay.sh
```

Uninstall:
```bash
sudo apt-get purge -y postfix libsasl2-modules && sudo rm -rf /etc/postfix && sudo apt-get autoremove -y
```

### Verify

```bash
echo 'Test from Postfix' | mail -s 'Relay test' walidahmm@yahoo.com
sudo journalctl -u postfix --no-pager -n 10 --since "1 min ago"
```

Look for `status=sent (250 OK, completed)`.

Note: Debian Trixie logs to journald, not `/var/log/mail.log`.

---

## Lessons Learned

| # | Lesson | Cost |
|---|---|---|
| 1 | Pin every image tag. Rolling tags (`latest`, `lts`) break silently. | Wasted debugging time when versions drift |
| 2 | The Dockerfile must actually install what the image name promises. | Build passes, pipeline fails at runtime |
| 3 | Jenkins node name, agent `-name`, and Jenkinsfile `label` are three different things that must align correctly. | 3 failed pipeline runs |
| 4 | `Remote root directory` must be writable by the container's runtime user. | AccessDeniedException |
| 5 | Trailing spaces after `\` are invisible and break line continuation. Use single-line commands or trim whitespace. | 3 separate `docker run` failures |
| 6 | After changing node config, disconnect + restart the agent. Config is cached at connect time. | Stale config persists across builds |
| 7 | SMTP relay providers reject `MAIL FROM` that doesn't match the authenticated account. | Bounced emails |
| 8 | `sender_canonical_maps` with regexp catch-all is the correct Postfix mechanism for universal sender rewriting. `smtp_generic_maps` requires per-user entries. | Multiple bounce cycles |
| 9 | Alertmanager controls its own sender address; `mail` uses local system identity. Same Postfix config behaves differently depending on who's sending. | Confusion about why VM worked but workstation didn't |
| 10 | Yahoo locks you out after repeated bad auth. Wait 15 min. | Staring at `Too many bad auth attempts` |
