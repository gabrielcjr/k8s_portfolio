#!/usr/bin/env bash
# ==============================================================================
# Master Cluster Bootstrap Script (Zero to Live in ~5 minutes)
# Recovers the entire multi-tenant cluster on a fresh Ubuntu 22.04 / 24.04 VM
# Repo: https://github.com/gabrielcjr/k8s_portfolio
# ==============================================================================
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}========================================================================${NC}"
echo -e "${GREEN}${BOLD}     🚀 Starting Automated Cluster Bootstrap & Recovery          ${NC}"
echo -e "${BLUE}${BOLD}========================================================================${NC}"

# 1. Install Base Packages
echo -e "\n${YELLOW}[1/8] Installing Base Dependencies & GitHub CLI...${NC}"
sudo apt-get update
sudo apt-get install -y curl git nginx certbot python3-certbot-nginx jq ca-certificates

if ! command -v gh &>/dev/null; then
    echo "Installing GitHub CLI (gh)..."
    (type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
        && sudo mkdir -p -m 755 /etc/apt/keyrings \
        && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
        && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
        && sudo apt update \
        && sudo apt install gh -y
fi

# 2. Check GitHub Auth
echo -e "\n${YELLOW}[2/8] Verifying GitHub Authentication...${NC}"
if ! gh auth status &>/dev/null; then
    echo -e "${RED}You need to authenticate with GitHub to pull private backups.${NC}"
    echo "Please run: gh auth login"
    exit 1
fi
echo -e "${GREEN}✔ GitHub CLI authenticated.${NC}"

# 3. Install K3s Kubernetes
echo -e "\n${YELLOW}[3/8] Installing & Configuring K3s Kubernetes...${NC}"
if ! command -v k3s &>/dev/null; then
    curl -sfL https://get.k3s.io | sh -
fi

mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown -R "$USER:$USER" "$HOME/.kube/config"
sudo cp /etc/rancher/k3s/k3s.yaml /root/.kube/config 2>/dev/null || true

echo "Waiting for K3s node to enter Ready state..."
until kubectl get nodes | grep -w "Ready" &>/dev/null; do
    sleep 2
done
echo -e "${GREEN}✔ K3s is Ready.${NC}"

# 4. Install ArgoCD
echo -e "\n${YELLOW}[4/8] Installing ArgoCD GitOps Engine...${NC}"
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for ArgoCD server deployment..."
kubectl -n argocd rollout status deployment/argocd-server --timeout=180s
echo -e "${GREEN}✔ ArgoCD installed and running.${NC}"

# 5. Restore Secrets and SSL Certificates from Private Backup Repo
echo -e "\n${YELLOW}[5/8] Restoring Secrets & SSL Certificates...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/scripts/cluster_restore.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/cluster_restore.sh"
else
    echo "Notice: cluster_restore.sh not found, skipping initial secret restore."
fi

# 6. Deploy All 10 Applications via ArgoCD
echo -e "\n${YELLOW}[6/8] Deploying All Workloads via GitOps...${NC}"
kubectl apply -f "${SCRIPT_DIR}/00-namespaces.yaml" 2>/dev/null || true
kubectl apply -f "${SCRIPT_DIR}/argocd/applications.yaml"
echo -e "${GREEN}✔ ArgoCD applications registered. Reconciliation started.${NC}"

# 7. Configure Host Nginx Reverse Proxy
echo -e "\n${YELLOW}[7/8] Configuring Host Nginx Gateway...${NC}"
sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
if [ -d "${SCRIPT_DIR}/nginx/sites-available" ]; then
    sudo cp -r "${SCRIPT_DIR}/nginx/sites-available/"* /etc/nginx/sites-available/
    for site in "${SCRIPT_DIR}/nginx/sites-available/"*; do
        site_name="$(basename "$site")"
        sudo ln -sf "/etc/nginx/sites-available/${site_name}" "/etc/nginx/sites-enabled/${site_name}"
    done
fi

sudo nginx -t
sudo systemctl restart nginx
echo -e "${GREEN}✔ Nginx reverse proxy active with all site bindings.${NC}"

# 8. Setup Daily Backup Cron
echo -e "\n${YELLOW}[8/8] Setting Up Daily Automated Backup Cron Job...${NC}"
CRON_JOB="0 3 * * * /usr/bin/env bash /home/ubuntu/k8s_portfolio/scripts/cluster_backup.sh >> /var/log/cluster_backup.log 2>&1"
(crontab -l 2>/dev/null | grep -v "cluster_backup.sh" || true; echo "$CRON_JOB") | crontab -
echo -e "${GREEN}✔ Daily backup scheduled at 03:00 UTC.${NC}"

PUBLIC_IP=$(curl -s https://api.ipify.org || echo "YOUR_NEW_IP")

echo -e "\n${BLUE}${BOLD}========================================================================${NC}"
echo -e "${GREEN}${BOLD}✨ BOOTSTRAP COMPLETE! Cluster is live.${NC}"
echo -e "${BLUE}${BOLD}========================================================================${NC}"
echo -e "Next steps:"
echo -e "1. Update your Cloudflare DNS A records (@ and subdomains) to point to: ${BOLD}${PUBLIC_IP}${NC}"
echo -e "2. Monitor workload readiness with: ${BOLD}kubectl get pods -A${NC}"
echo -e "3. Access ArgoCD UI at: ${BOLD}https://argocd.gabrielcjr.website${NC}\n"
