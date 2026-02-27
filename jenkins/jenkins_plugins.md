## Plugins 

1. **Pipeline Plugin** ✅ **PRE-INSTALLED**
   - Core pipeline functionality (`pipeline {}` block)
   - **Status**: Native Jenkins plugin

2. **Timestamper Plugin** ✅ **PRE-INSTALLED**
   - `options { timestamps() }`


3. **SSH Agent Plugin** ❌ **NOT PRE-INSTALLED**
   - `sshagent(credentials: ['vm-ssh'])`
   - **Status**: External plugin (requires manual installation)

4. **Credentials Plugin** ✅ **PRE-INSTALLED**
   - `credentials: ['vm-ssh']`
   - **Status**: Native Jenkins plugin (bundled with core)

5. **Pipeline: Basic Steps** ✅ **PRE-INSTALLED**
   - `sh` steps, `echo` commands
   - **Status**: Native Jenkins pipeline plugin

6. **Pipeline: Nodes and Processes** ✅ **PRE-INSTALLED**
   - Provides `sh` step functionality
   - **Status**: Native Jenkins pipeline plugin

### **Indirectly Used/Required Plugins:**

7. **Docker Pipeline** ❌ **NOT PRE-INSTALLED**
   - Implied by Docker operations and `docker-agent1` label
   - **Status**: External plugin (requires manual installation)

8. **Docker plugin** ❌ **NOT PRE-INSTALLED**
   - Docker integration for the agent
   - **Status**: External plugin (requires manual installation)

## Summary

| Plugin | Used in Script | Pre-installed | Plugin Link |
|--------|----------------|---------------|-------------|
| Pipeline Plugin | ✅ | ✅ | - |
| Timestamper | ✅ | ✅ | [Timestamper](https://plugins.jenkins.io/timestamper) |
| SSH Agent Plugin | ✅ | ❌ | [SSH Agent](https://plugins.jenkins.io/ssh-agent) |
| Credentials Plugin | ✅ | ✅ | - |
| Pipeline: Basic Steps | ✅ | ✅ | - |
| Pipeline: Nodes and Processes | ✅ | ✅ | - |
| Docker Pipeline | ✅ (implied) | ❌ | [Docker Pipeline](https://plugins.jenkins.io/docker-workflow) |
| Docker plugin | ✅ (implied) | ❌ | [Docker Plugin](https://plugins.jenkins.io/docker-plugin) |

