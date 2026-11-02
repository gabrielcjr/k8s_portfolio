#!/usr/bin/env bash
# ==============================================================================
# Master Cluster Bootstrap Script (Zero to Live in ~5 minutes)
# Recovers the entire multi-tenant cluster on a fresh Ubuntu 22.04 / 24.04 VM
# Repo: https://github.com/gabrielcjr/k8s_portfolio
# ==============================================================================
set -euo pipefail

export HOME="${HOME:-/home/ubuntu}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${HOME}/.local/bin"

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_VERSION="v3.5.2"

echo -e "${BLUE}${BOLD}========================================================================${NC}"
echo -e "${GREEN}${BOLD}     🚀 Starting Automated Cluster Bootstrap & Recovery          ${NC}"
echo -e "${BLUE}${BOLD}========================================================================${NC}"

# 1. Install Base Packages & Docker / GitHub CLI
echo -e "\n${YELLOW}[1/10] Installing Base Dependencies, Docker & GitHub CLI...${NC}"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget git nginx certbot python3-certbot-nginx jq ca-certificates python3 docker.io

sudo systemctl enable --now docker
sudo usermod -aG docker "$USER" 2>/dev/null || true

if ! command -v gh &>/dev/null; then
    echo "Installing GitHub CLI (gh)..."
    sudo mkdir -p -m 755 /etc/apt/keyrings
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update && sudo apt-get install -y gh
fi

# 2. Check GitHub Auth
echo -e "\n${YELLOW}[2/10] Verifying GitHub Authentication...${NC}"
if ! gh auth status &>/dev/null; then
    echo -e "${RED}You need to authenticate with GitHub to pull private backups.${NC}"
    echo "Please run: gh auth login"
    exit 1
fi
gh auth setup-git 2>/dev/null || true
echo -e "${GREEN}✔ GitHub CLI authenticated.${NC}"

# 3. Install K3s Kubernetes
echo -e "\n${YELLOW}[3/10] Installing & Configuring K3s Kubernetes...${NC}"
if ! command -v k3s &>/dev/null; then
    curl -sfL https://get.k3s.io | sh -
fi

mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown -R "$USER:$USER" "$HOME/.kube/config"
sudo mkdir -p /root/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
export KUBECONFIG="$HOME/.kube/config"

echo "Waiting for K3s node to enter Ready state..."
until kubectl get nodes | grep -w "Ready" &>/dev/null; do
    sleep 2
done
echo -e "${GREEN}✔ K3s is Ready.${NC}"

# 4. Create All Cluster Namespaces & Install ArgoCD
echo -e "\n${YELLOW}[4/10] Creating Namespaces & Installing ArgoCD (${ARGOCD_VERSION})...${NC}"
kubectl apply -f "${SCRIPT_DIR}/00-namespaces.yaml"
if ! kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"; then
    kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
fi

echo "Waiting for ArgoCD server deployment..."
kubectl -n argocd rollout status deployment/argocd-server --timeout=180s
echo -e "${GREEN}✔ ArgoCD installed and running.${NC}"

# 5. Pre-Deploy Restore: Secrets (including Private Repo Creds) & SSL Certs
echo -e "\n${YELLOW}[5/10] Restoring Secrets & SSL Certificates (Pre-Deploy Phase)...${NC}"
if [ -f "${SCRIPT_DIR}/scripts/cluster_restore.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/cluster_restore.sh" --phase pre-deploy
fi

# 6. Build & Import Local Image for SentinelMCP
echo -e "\n${YELLOW}[6/10] Building & Importing SentinelMCP Image into K3s...${NC}"
if ! sudo k3s ctr images ls -q | grep -q "sentinelmcp:latest"; then
    SENTINEL_DIR="/tmp/sentinelmcp_build"
    rm -rf "${SENTINEL_DIR}"
    if gh repo clone gabrielcjr/sentinelmcp "${SENTINEL_DIR}" &>/dev/null; then
        sudo docker build -t sentinelmcp:latest "${SENTINEL_DIR}"
        sudo docker save sentinelmcp:latest | sudo k3s ctr images import -
        rm -rf "${SENTINEL_DIR}"
        echo -e "${GREEN}✔ Built and imported sentinelmcp:latest into K3s containerd.${NC}"
    else
        echo -e "${YELLOW}Warning: Could not clone gabrielcjr/sentinelmcp; skipping image build.${NC}"
    fi
else
    echo -e "${GREEN}✔ sentinelmcp:latest already present in K3s containerd.${NC}"
fi

# 7. Deploy All 11 Applications via ArgoCD
echo -e "\n${YELLOW}[7/10] Deploying All Workloads via GitOps...${NC}"
kubectl apply -f "${SCRIPT_DIR}/argocd/applications.yaml"
echo -e "${GREEN}✔ All 11 ArgoCD applications registered.${NC}"

# 8. Data Restore: PostgreSQL & SQLite Volumes
echo -e "\n${YELLOW}[8/10] Restoring Databases (PostgreSQL & SQLite PVCs)...${NC}"
if [ -f "${SCRIPT_DIR}/scripts/cluster_restore.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/cluster_restore.sh" --phase data
fi

# 9. Configure Host Nginx Reverse Proxy & Host Firewall (Ports 80/443)
echo -e "\n${YELLOW}[9/10] Configuring Host Nginx Gateway & Opening HTTP/HTTPS Ports...${NC}"
sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
if [ -d "${SCRIPT_DIR}/nginx/sites-available" ]; then
    sudo cp -r "${SCRIPT_DIR}/nginx/sites-available/"* /etc/nginx/sites-available/
    if [ -d "/etc/letsencrypt/live" ]; then
        for site in "${SCRIPT_DIR}/nginx/sites-available/"*; do
            site_name="$(basename "$site")"
            sudo ln -sf "/etc/nginx/sites-available/${site_name}" "/etc/nginx/sites-enabled/${site_name}"
        done
    else
        echo -e "${YELLOW}Warning: /etc/letsencrypt/live not found; copied site configs to /etc/nginx/sites-available but skipped enabling SSL sites until certificates are issued.${NC}"
    fi
fi

if sudo nginx -t 2>/dev/null; then
    sudo systemctl restart nginx
    echo -e "${GREEN}✔ Nginx reverse proxy active.${NC}"
else
    echo -e "${YELLOW}Warning: nginx -t reported an issue; please verify /etc/letsencrypt certificates.${NC}"
fi

# Open ports 80 and 443 in host iptables (Oracle Cloud Ubuntu images block them by default)
for port in 80 443; do
    if ! sudo iptables -C INPUT -p tcp -m tcp --dport "${port}" -j ACCEPT 2>/dev/null; then
        sudo iptables -I INPUT 1 -p tcp -m tcp --dport "${port}" -j ACCEPT || true
    fi
done

# 10. Apply Host Security Hardening & Daily Backup Cron
echo -e "\n${YELLOW}[10/10] Applying Host Security Hardening & Backup Cron...${NC}"
echo -e "PermitRootLogin no\nX11Forwarding no" | sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null
if sudo sshd -t 2>/dev/null; then
    sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd 2>/dev/null || true
fi
sudo systemctl stop rpcbind.service rpcbind.socket 2>/dev/null || true
sudo systemctl disable rpcbind.service rpcbind.socket 2>/dev/null || true
sudo systemctl mask rpcbind.service rpcbind.socket 2>/dev/null || true

CRON_LOG="${HOME}/cluster_backup.log"
CRON_JOB="0 3 * * * /usr/bin/env bash ${SCRIPT_DIR}/scripts/cluster_backup.sh >> ${CRON_LOG} 2>&1"
(crontab -l 2>/dev/null | grep -v "cluster_backup.sh" || true; echo "$CRON_JOB") | crontab -
echo -e "${GREEN}✔ Daily backup scheduled at 03:00 UTC (logging to ${CRON_LOG}).${NC}"

PUBLIC_IP=$(curl -s https://api.ipify.org || echo "YOUR_NEW_IP")

echo -e "\n${BLUE}${BOLD}========================================================================${NC}"
echo -e "${GREEN}${BOLD}✨ BOOTSTRAP COMPLETE! Cluster is live.${NC}"
echo -e "${BLUE}${BOLD}========================================================================${NC}"
echo -e "Next steps:"
echo -e "1. Ensure ports 80 & 443 are open in your Cloud Provider Security List / NSG."
echo -e "2. Update your Cloudflare DNS A records (@ and subdomains) to point to: ${BOLD}${PUBLIC_IP}${NC}"
echo -e "3. Monitor workload readiness with: ${BOLD}kubectl get pods -A${NC}"
echo -e "4. Access ArgoCD UI at: ${BOLD}https://argocd.gabrielcjr.website${NC}\n"
