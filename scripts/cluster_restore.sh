#!/usr/bin/env bash
# ==============================================================================
# Cluster Automated Restore Script
# Restores Databases, Secrets, and SSL Certificates from gabrielcjr/cluster-backups
# ==============================================================================
set -euo pipefail

BACKUP_REPO="gabrielcjr/cluster-backups"
RESTORE_DIR="/tmp/cluster_restore"
rm -rf "${RESTORE_DIR}"
mkdir -p "${RESTORE_DIR}"

echo "=== [1/5] Downloading Latest Backup from GitHub Releases ==="
gh release download latest --repo "${BACKUP_REPO}" --pattern "*.tar.gz" --dir "${RESTORE_DIR}"
ARCHIVE_FILE=$(find "${RESTORE_DIR}" -name "*.tar.gz" | head -n 1)

if [ -z "${ARCHIVE_FILE}" ]; then
    echo "Error: No backup archive found in GitHub release!"
    exit 1
fi

echo "  -> Extracting ${ARCHIVE_FILE}..."
tar -xzf "${ARCHIVE_FILE}" -C "${RESTORE_DIR}"

echo "=== [2/5] Restoring Kubernetes Secrets ==="
if [ -d "${RESTORE_DIR}/secrets" ]; then
    for sec in "${RESTORE_DIR}/secrets/"*.yaml; do
        if [ -f "$sec" ]; then
            echo "  Applying secret: $(basename "$sec")"
            kubectl apply -f "$sec" || echo "Warning: failed to apply $sec"
        fi
    done
fi

echo "=== [3/5] Restoring SSL Certificates (/etc/letsencrypt) ==="
if [ -f "${RESTORE_DIR}/certs/letsencrypt.tar.gz" ]; then
    sudo mkdir -p /etc/letsencrypt
    sudo tar -xzf "${RESTORE_DIR}/certs/letsencrypt.tar.gz" -C /etc/
    echo "  SSL certificates restored to /etc/letsencrypt."
fi

echo "=== [4/5] Restoring Databases ==="
# 1. AMAE PostgreSQL
if [ -f "${RESTORE_DIR}/databases/amae_postgres.sql" ]; then
    echo "  Waiting for AMAE PostgreSQL pod to become Ready..."
    kubectl wait --namespace amae --for=condition=Ready pod/postgres-0 --timeout=120s || true
    echo "  Restoring AMAE PostgreSQL database..."
    kubectl exec -i -n amae postgres-0 -- psql -U amae < "${RESTORE_DIR}/databases/amae_postgres.sql" || echo "Warning: AMAE restore had errors"
fi

# 2. Jobs PostgreSQL
if [ -f "${RESTORE_DIR}/databases/jobs_postgres.sql" ]; then
    echo "  Waiting for Jobs PostgreSQL pod to become Ready..."
    kubectl wait --namespace jobs --for=condition=Ready pod/postgres-0 --timeout=120s || true
    echo "  Restoring Jobs PostgreSQL database..."
    kubectl exec -i -n jobs postgres-0 -- psql -U postgres < "${RESTORE_DIR}/databases/jobs_postgres.sql" || echo "Warning: Jobs restore had errors"
fi

# 3. KoBo SQLite databases
if [ -f "${RESTORE_DIR}/databases/kobo_data.tar.gz" ]; then
    echo "  Restoring KoBo SQLite files..."
    cat "${RESTORE_DIR}/databases/kobo_data.tar.gz" | kubectl exec -i -n kobo deployment/kobo-missoes -- tar -xzf - -C /data || true
fi

# 4. Leilões Judiciais SQLite
if [ -f "${RESTORE_DIR}/databases/leiloes_data.tar.gz" ]; then
    echo "  Restoring Leilões SQLite files..."
    cat "${RESTORE_DIR}/databases/leiloes_data.tar.gz" | kubectl exec -i -n leiloes deployment/leiloes-web -- tar -xzf - -C /app/dados || true
fi

echo "=== [5/5] Cleanup ==="
rm -rf "${RESTORE_DIR}"

echo "========================================================================"
echo "✔ All secrets, SSL certificates, and database states restored!"
echo "========================================================================"
