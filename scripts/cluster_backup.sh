#!/usr/bin/env bash
# ==============================================================================
# Cluster Automated Backup Script (Databases + Secrets + SSL Certs)
# Target: Private GitHub Repo gabrielcjr/cluster-backups via GitHub CLI (gh)
# ==============================================================================
set -euo pipefail

BACKUP_REPO="gabrielcjr/cluster-backups"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RELEASE_TAG="backup-${TIMESTAMP}"
WORK_DIR="/tmp/cluster_backup_${TIMESTAMP}"
ARCHIVE_PATH="/tmp/cluster_backup_${TIMESTAMP}.tar.gz"

echo "=== [1/6] Preparing backup directory: ${WORK_DIR} ==="
mkdir -p "${WORK_DIR}/databases" "${WORK_DIR}/secrets" "${WORK_DIR}/certs"

echo "=== [2/6] Exporting Kubernetes Databases ==="
# 1. AMAE PostgreSQL
if kubectl get pod postgres-0 -n amae &>/dev/null; then
    echo "  -> Dumping AMAE PostgreSQL..."
    kubectl exec -n amae postgres-0 -- pg_dumpall -U amae > "${WORK_DIR}/databases/amae_postgres.sql" || echo "Warning: AMAE dump failed"
fi

# 2. Jobs PostgreSQL
if kubectl get pod postgres-0 -n jobs &>/dev/null; then
    echo "  -> Dumping Jobs PostgreSQL..."
    kubectl exec -n jobs postgres-0 -- pg_dumpall -U postgres > "${WORK_DIR}/databases/jobs_postgres.sql" || echo "Warning: Jobs dump failed"
fi

# 3. KoBo SQLite databases
if kubectl get deployment kobo-missoes -n kobo &>/dev/null; then
    echo "  -> Archiving KoBo SQLite databases..."
    kubectl exec -n kobo deployment/kobo-missoes -- tar -czf - -C /data . > "${WORK_DIR}/databases/kobo_data.tar.gz" || echo "Warning: KoBo archive failed"
fi

# 4. Leilões Judiciais SQLite & datasets
if kubectl get deployment leiloes-web -n leiloes &>/dev/null; then
    echo "  -> Archiving Leilões SQLite data..."
    kubectl exec -n leiloes deployment/leiloes-web -- tar -czf - -C /app/dados . > "${WORK_DIR}/databases/leiloes_data.tar.gz" || echo "Warning: Leilões archive failed"
fi

echo "=== [3/6] Exporting Kubernetes Secrets ==="
kubectl get secrets -n amae amae-secret -o yaml > "${WORK_DIR}/secrets/amae-secret.yaml" 2>/dev/null || true
kubectl get secrets -n jobs jobs-secret -o yaml > "${WORK_DIR}/secrets/jobs-secret.yaml" 2>/dev/null || true
kubectl get secrets -n atsproof atsproof-secret -o yaml > "${WORK_DIR}/secrets/atsproof-secret.yaml" 2>/dev/null || true
kubectl get secrets -n default sentinelmcp-secrets -o yaml > "${WORK_DIR}/secrets/sentinelmcp-secrets.yaml" 2>/dev/null || true
kubectl get secrets -n argocd repo-k8s-kobo -o yaml > "${WORK_DIR}/secrets/argocd-repo-k8s-kobo.yaml" 2>/dev/null || true

echo "=== [4/6] Archiving Host SSL Certificates & Nginx ==="
if [ -d "/etc/letsencrypt" ]; then
    sudo tar -czf "${WORK_DIR}/certs/letsencrypt.tar.gz" -C /etc letsencrypt 2>/dev/null || echo "Warning: Let's Encrypt archive failed"
fi

echo "=== [5/6] Creating Final Compressed Archive ==="
tar -czf "${ARCHIVE_PATH}" -C "${WORK_DIR}" .
rm -rf "${WORK_DIR}"
ARCHIVE_SIZE=$(du -h "${ARCHIVE_PATH}" | cut -f1)
echo "  -> Archive created: ${ARCHIVE_PATH} (${ARCHIVE_SIZE})"

echo "=== [6/6] Uploading to Private GitHub Repository (${BACKUP_REPO}) ==="
# Create GitHub Release with archive attached
gh release create "${RELEASE_TAG}" "${ARCHIVE_PATH}" \
    --repo "${BACKUP_REPO}" \
    --title "Cluster Backup ${TIMESTAMP}" \
    --notes "Automated cluster state snapshot including PostgreSQL, SQLite databases, k8s secrets, and SSL certs."

# Also point a static tag 'latest' to this release for easy bootstrap recovery
if gh release view latest --repo "${BACKUP_REPO}" &>/dev/null; then
    gh release delete latest --repo "${BACKUP_REPO}" --yes || true
    git -C /tmp tag -d latest 2>/dev/null || true
fi
gh release create "latest" "${ARCHIVE_PATH}" \
    --repo "${BACKUP_REPO}" \
    --title "Latest Cluster Backup" \
    --notes "Points to the latest successful backup (${RELEASE_TAG}). Download during bootstrap."

# Clean up local archive
rm -f "${ARCHIVE_PATH}"

echo "========================================================================"
echo "✔ Backup uploaded successfully to https://github.com/${BACKUP_REPO}/releases"
echo "========================================================================"
