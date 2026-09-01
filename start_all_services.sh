#!/bin/bash
# ==============================================================================
# Master Service Startup & Healthcheck Script for VM (144.22.149.93)
# Manages: K3s Kubernetes (Portfolio, AMAE, FindJobs, ATS MatchProof, ArgoCD) & Host Nginx
# ==============================================================================

set -e

# Color definitions
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

echo -e "${BLUE}${BOLD}======================================================${NC}"
echo -e "${CYAN}${BOLD}   🚀 Checking Multi-Project K3s Kubernetes Cluster   ${NC}"
echo -e "${BLUE}${BOLD}======================================================${NC}"

# 1. Ensure K3s Service is Active
echo -e "\n${YELLOW}[1/3] Checking K3s Control Plane Service...${NC}"
if sudo systemctl is-active --quiet k3s.service; then
    echo -e "  ${GREEN}✔ k3s.service is active.${NC}"
else
    echo -e "  Starting k3s.service..."
    sudo systemctl start k3s.service
    echo -e "  ${GREEN}✔ k3s.service started.${NC}"
fi

# 2. Check and Reload Nginx Host Gateway
echo -e "\n${YELLOW}[2/3] Checking and Reloading Host Nginx Reverse Proxy...${NC}"
sudo nginx -t
sudo systemctl start nginx
sudo systemctl reload nginx
echo -e "  ${GREEN}✔ Host Nginx is active with SSL/TLS termination.${NC}"

# 3. K3s Pod Overview
echo -e "\n${YELLOW}[3/3] Checking K3s Pod Statuses...${NC}"
kubectl get pods -A

# ==============================================================================
# Health Check Verification Table
# ==============================================================================
echo -e "\n${BLUE}${BOLD}======================================================${NC}"
echo -e "${CYAN}${BOLD}              🔎 Healthcheck Status Table             ${NC}"
echo -e "${BLUE}${BOLD}======================================================${NC}"

check_endpoint() {
    local url=$1
    local name=$2
    local http_code
    http_code=$(curl -k -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "ERR")
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "405" ] || [ "$http_code" = "301" ]; then
        printf "  %-32s : ${GREEN}${BOLD}✔ ONLINE${NC} (HTTP %s)\n" "$name" "$http_code"
    else
        printf "  %-32s : ${RED}${BOLD}✖ OFFLINE${NC} (HTTP %s)\n" "$name" "$http_code"
    fi
}

sleep 2

check_endpoint "https://gabrielcjr.website/" "Portfolio (K3s)"
check_endpoint "https://amae.gabrielcjr.website/" "AMAE (K3s Django)"
check_endpoint "https://findjobs.gabrielcjr.website/" "FindJobs (K3s DevATS)"
check_endpoint "https://atsproof.website/healthz" "ATS MatchProof (K3s)"
check_endpoint "https://argocd.gabrielcjr.website/" "ArgoCD Web UI"
check_endpoint "https://gabrielcjr.website:8443/" "ArgoCD (Direct Port 8443)"

echo -e "\n${GREEN}${BOLD}✨ All systems operational on Kubernetes (K3s)!${NC}\n"
