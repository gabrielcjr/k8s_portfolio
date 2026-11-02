# K3s Multi-Project GitOps & Disaster Recovery Repository

This repository (`gabrielcjr/k8s_portfolio`) is the central GitOps control plane and automated Disaster Recovery (DR) bootstrap kit for the entire Kubernetes (`k3s`) cluster.

If the host VM is ever reclaimed or deleted, any fresh **Ubuntu 22.04 / 24.04 LTS** instance can be brought from bare OS to 100% live (with all 11 applications, secrets, SSL certificates, and databases restored) using `./bootstrap.sh`.

---

## 1. Quick Recovery Runbook ("Day Zero")

### Step 1: Provision a New Ubuntu VM
* Allow incoming TCP ports **22 (SSH)**, **80 (HTTP)**, and **443 (HTTPS)** in your cloud provider's firewall / Security List.
* SSH into the new server:
  ```bash
  ssh ubuntu@<NEW_VM_IP>
  ```

### Step 2: Authenticate GitHub CLI & Run `bootstrap.sh`
```bash
sudo apt-get update && sudo apt-get install -y git gh
gh auth login
git clone https://github.com/gabrielcjr/k8s_portfolio.git
cd k8s_portfolio
./bootstrap.sh
```

### Step 3: Update Cloudflare DNS
* Update your DNS `A` records (`gabrielcjr.website`, `*.gabrielcjr.website`, `atsproof.website`) to point to `<NEW_VM_IP>`.
* Verify all endpoints with:
  ```bash
  ./start_all_services.sh
  ```

---

## 2. Managed Workloads & Services (11 / 11 Apps in ArgoCD)

| Service / App | Namespace | Public URL | Source Repository | Persistent State Backed Up |
| :--- | :--- | :--- | :--- | :--- |
| **Portfolio** | `portfolio` | `https://gabrielcjr.website` | `gabrielcjr/portfolio` | Stateless |
| **ATS MatchProof** | `atsproof` | `https://atsproof.website` | `gabrielcjr/atsproof` | `atsproof-secret` |
| **FindJobs** | `jobs` | `https://findjobs.gabrielcjr.website` | `gabrielcjr/jobs_nestjs_react` | PostgreSQL (`jobs_postgres.sql`) + `jobs-secret` |
| **AMAE** | `amae` | `https://amae.gabrielcjr.website` | `gabrielcjr/amae` | PostgreSQL (`amae_postgres.sql`) + `amae-secret` |
| **KoBo Missões** | `kobo` | `https://missoes.gabrielcjr.website` | `gabrielcjr/k8s-kobo` *(Private)* | SQLite PVC (`kobo-missoes_data.tar.gz`) |
| **KoBo Evangelismo** | `kobo` | `https://evangelismo.gabrielcjr.website` | `gabrielcjr/k8s-kobo` *(Private)* | SQLite PVC (`kobo-evangelismo_data.tar.gz`) |
| **KoBo Getsêmani** | `kobo` | `https://getsemani.gabrielcjr.website` | `gabrielcjr/k8s-kobo` *(Private)* | SQLite PVC (`kobo-getsemani_data.tar.gz`) |
| **Leilões Judiciais** | `leiloes` | `https://leiloes.gabrielcjr.website` | `gabrielcjr/leiloes-judiciais` *(Private)* | SQLite & Datasets (`leiloes_data.tar.gz`) |
| **EdgeShield** | `edgeshield` | Internal Service | `gabrielcjr/edgeshield` | Redis |
| **SentinelMCP** | `default` | Internal SRE Agent | `gabrielcjr/sentinelmcp` | `sentinelmcp-secrets` + local image build |
| **Jaeger** | `jaeger` | `https://grafana.gabrielcjr.website` | `gabrielcjr/k8s_portfolio` (`jaeger/`) | In-memory traces |

---

## 3. Repository Layout

* **`bootstrap.sh`** — Master 10-step provisioning and disaster recovery script:
  1. Installs system packages, Docker, and GitHub CLI (`gh`).
  2. Verifies GitHub authentication.
  3. Installs `k3s` and configures `/root/.kube/config` and `~/.kube/config`.
  4. Creates all cluster namespaces (`00-namespaces.yaml`) and installs ArgoCD (`v3.5.2`).
  5. Runs `scripts/cluster_restore.sh --phase pre-deploy` to restore sanitized Kubernetes secrets (including private GitHub repo credentials) and `/etc/letsencrypt` SSL certificates.
  6. Clones `gabrielcjr/sentinelmcp`, builds `sentinelmcp:latest`, and imports it into `k3s` containerd.
  7. Applies `argocd/applications.yaml` to deploy all 11 workloads via GitOps.
  8. Runs `scripts/cluster_restore.sh --phase data` to wait for database pods to become ready and restores PostgreSQL and SQLite volumes.
  9. Configures host Nginx reverse proxy (`nginx/sites-available/*`) and opens TCP ports `80` and `443` in host `iptables`.
  10. Applies SSH and `rpcbind` security hardening and installs the daily `03:00 UTC` backup cron job.
* **`scripts/cluster_backup.sh`** — Automated backup script:
  * Exports PostgreSQL cluster dumps (`pg_dumpall --clean --if-exists`) for `amae` and `jobs`.
  * Performs hot, corruption-free online backups of all SQLite databases across all 3 KoBo PVCs and Leilões using Python's `sqlite3.Connection.backup()` API.
  * Exports and sanitizes Kubernetes secrets (stripping cluster-specific `uid` and `resourceVersion`).
  * Archives `/etc/letsencrypt` and `/etc/nginx`.
  * Uploads the compressed archive to the private [`gabrielcjr/cluster-backups`](https://github.com/gabrielcjr/cluster-backups) repository as a GitHub Release (`latest` + timestamped tag) and prunes releases older than the 14 most recent snapshots.
* **`scripts/cluster_restore.sh`** — Two-phase restore script (`--phase pre-deploy`, `--phase data`, or `--phase all`).
* **`start_all_services.sh`** — Health check script that verifies `k3s`, `nginx`, and all public HTTPS endpoints.

---

## 4. Manual Backup & Restore Commands

```bash
# Run an immediate manual backup to gabrielcjr/cluster-backups
./scripts/cluster_backup.sh

# Restore only secrets & SSL certs
./scripts/cluster_restore.sh --phase pre-deploy

# Restore only databases (PostgreSQL & SQLite PVCs)
./scripts/cluster_restore.sh --phase data

# Run full restore (both phases)
./scripts/cluster_restore.sh --phase all
```
