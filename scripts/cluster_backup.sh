#!/usr/bin/env bash
# ==============================================================================
# Cluster Automated Backup Script (Databases + Secrets + SSL Certs)
# Target: Private GitHub Repo gabrielcjr/cluster-backups via GitHub CLI (gh)
# ==============================================================================
set -euo pipefail

export HOME="${HOME:-/home/ubuntu}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${HOME}/.local/bin"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

BACKUP_REPO="gabrielcjr/cluster-backups"
KEEP_RELEASES=14
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RELEASE_TAG="backup-${TIMESTAMP}"
WORK_DIR="/tmp/cluster_backup_${TIMESTAMP}"
ARCHIVE_PATH="/tmp/cluster_backup_${TIMESTAMP}.tar.gz"

cleanup() {
    rm -rf "${WORK_DIR}" "${ARCHIVE_PATH}"
}
trap cleanup EXIT

echo "=== [1/7] Preparing backup directory: ${WORK_DIR} ==="
mkdir -p "${WORK_DIR}/databases" "${WORK_DIR}/secrets" "${WORK_DIR}/certs"

# Helper to perform a hot atomic backup of SQLite .db files inside a container before tarring
backup_pod_dir_with_sqlite() {
    local namespace="$1"
    local resource="$2"
    local src_dir="$3"
    local out_tar="$4"

    kubectl exec -n "${namespace}" "${resource}" -- python3 -c "
import os, shutil, sqlite3, subprocess, sys

src = '${src_dir}'
stage = '/tmp/sqlite_safe_backup'
shutil.rmtree(stage, ignore_errors=True)
os.makedirs(stage, exist_ok=True)

for root, dirs, files in os.walk(src):
    rel = os.path.relpath(root, src)
    target_dir = stage if rel == '.' else os.path.join(stage, rel)
    os.makedirs(target_dir, exist_ok=True)
    for f in files:
        if f.endswith(('-wal', '-shm', '-journal')):
            continue
        s_path = os.path.join(root, f)
        d_path = os.path.join(target_dir, f)
        if f.endswith(('.db', '.sqlite', '.sqlite3')):
            try:
                s_conn = sqlite3.connect(s_path)
                d_conn = sqlite3.connect(d_path)
                with d_conn:
                    s_conn.backup(d_conn)
                d_conn.close()
                s_conn.close()
            except Exception:
                shutil.copy2(s_path, d_path)
        else:
            shutil.copy2(s_path, d_path)
"
    kubectl exec -n "${namespace}" "${resource}" -- tar -czf - -C /tmp/sqlite_safe_backup . > "${out_tar}"
    kubectl exec -n "${namespace}" "${resource}" -- rm -rf /tmp/sqlite_safe_backup
}

echo "=== [2/7] Exporting Kubernetes Databases ==="
# 1. AMAE PostgreSQL
if kubectl get pod postgres-0 -n amae &>/dev/null; then
    echo "  -> Dumping AMAE PostgreSQL..."
    kubectl exec -n amae postgres-0 -- pg_dumpall --clean --if-exists -U amae > "${WORK_DIR}/databases/amae_postgres.sql"
fi

# 2. Jobs PostgreSQL
if kubectl get pod postgres-0 -n jobs &>/dev/null; then
    echo "  -> Dumping Jobs PostgreSQL..."
    kubectl exec -n jobs postgres-0 -- pg_dumpall --clean --if-exists -U postgres > "${WORK_DIR}/databases/jobs_postgres.sql"
fi

# 3. KoBo SQLite databases across ALL 3 tenant PVCs
for tenant in kobo-missoes kobo-evangelismo kobo-getsemani; do
    if kubectl get deployment "${tenant}" -n kobo &>/dev/null; then
        echo "  -> Archiving ${tenant} SQLite volume (/data)..."
        backup_pod_dir_with_sqlite "kobo" "deployment/${tenant}" "/data" "${WORK_DIR}/databases/${tenant}_data.tar.gz"
    fi
done

# Backward-compatible symlink/copy for kobo_data.tar.gz -> kobo-missoes_data.tar.gz
if [ -f "${WORK_DIR}/databases/kobo-missoes_data.tar.gz" ]; then
    cp "${WORK_DIR}/databases/kobo-missoes_data.tar.gz" "${WORK_DIR}/databases/kobo_data.tar.gz"
fi

# 4. Leilões Judiciais SQLite & datasets
if kubectl get deployment leiloes-web -n leiloes &>/dev/null; then
    echo "  -> Archiving Leilões SQLite volume (/app/dados)..."
    backup_pod_dir_with_sqlite "leiloes" "deployment/leiloes-web" "/app/dados" "${WORK_DIR}/databases/leiloes_data.tar.gz"
fi

echo "=== [3/7] Exporting & Sanitizing Kubernetes Secrets ==="
export_clean_secret() {
    local ns="$1"
    local name="$2"
    local out="$3"
    if kubectl get secret -n "${ns}" "${name}" &>/dev/null; then
        kubectl get secret -n "${ns}" "${name}" -o json | \
            jq 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.managedFields, .metadata.ownerReferences, .metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"])' \
            > "${out}"
        echo "  -> Exported ${ns}/${name}"
    fi
}

export_clean_secret "amae" "amae-secret" "${WORK_DIR}/secrets/amae-secret.json"
export_clean_secret "jobs" "jobs-secret" "${WORK_DIR}/secrets/jobs-secret.json"
export_clean_secret "atsproof" "atsproof-secret" "${WORK_DIR}/secrets/atsproof-secret.json"
export_clean_secret "default" "sentinelmcp-secrets" "${WORK_DIR}/secrets/sentinelmcp-secrets.json"
export_clean_secret "argocd" "repo-k8s-kobo" "${WORK_DIR}/secrets/argocd-repo-k8s-kobo.json"
export_clean_secret "argocd" "repo-leiloes" "${WORK_DIR}/secrets/argocd-repo-leiloes.json"
export_clean_secret "argocd" "repo-creds-gabrielcjr" "${WORK_DIR}/secrets/argocd-repo-creds-gabrielcjr.json"

echo "=== [4/7] Archiving Host SSL Certificates & Nginx ==="
if [ -d "/etc/letsencrypt" ]; then
    sudo tar -czf "${WORK_DIR}/certs/letsencrypt.tar.gz" -C /etc letsencrypt
fi
if [ -d "/etc/nginx/sites-available" ]; then
    sudo tar -czf "${WORK_DIR}/certs/nginx_configs.tar.gz" -C /etc/nginx sites-available sites-enabled
fi

echo "=== [5/7] Creating Final Compressed Archive ==="
tar -czf "${ARCHIVE_PATH}" -C "${WORK_DIR}" .
ARCHIVE_SIZE=$(du -h "${ARCHIVE_PATH}" | cut -f1)
echo "  -> Archive created: ${ARCHIVE_PATH} (${ARCHIVE_SIZE})"

echo "=== [6/7] Uploading to Private GitHub Repository (${BACKUP_REPO}) ==="
gh release create "${RELEASE_TAG}" "${ARCHIVE_PATH}" \
    --repo "${BACKUP_REPO}" \
    --title "Cluster Backup ${TIMESTAMP}" \
    --notes "Automated cluster state snapshot (PostgreSQL, 3x KoBo SQLite PVCs, Leilões SQLite, sanitized k8s secrets, SSL certs)."

# Update static 'latest' release AND clean up its remote tag first
if gh release view latest --repo "${BACKUP_REPO}" &>/dev/null; then
    gh release delete latest --repo "${BACKUP_REPO}" --cleanup-tag --yes || true
fi
gh release create "latest" "${ARCHIVE_PATH}" \
    --repo "${BACKUP_REPO}" \
    --title "Latest Cluster Backup (${TIMESTAMP})" \
    --notes "Points to the latest successful backup (${RELEASE_TAG})."

echo "=== [7/7] Pruning Old Backups (Keeping latest ${KEEP_RELEASES}) ==="
OLD_TAGS=$(gh release list --repo "${BACKUP_REPO}" --limit 100 --json tagName -q '.[].tagName' | grep '^backup-' | tail -n +$((KEEP_RELEASES + 1)) || true)
for old_tag in ${OLD_TAGS}; do
    echo "  -> Pruning old release: ${old_tag}"
    gh release delete "${old_tag}" --repo "${BACKUP_REPO}" --cleanup-tag --yes || true
done

echo "========================================================================"
echo "✔ Backup uploaded successfully to https://github.com/${BACKUP_REPO}/releases"
echo "========================================================================"
