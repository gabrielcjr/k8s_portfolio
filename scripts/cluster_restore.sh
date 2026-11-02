#!/usr/bin/env bash
# ==============================================================================
# Cluster Automated Restore Script
# Supports:
#   --phase pre-deploy  (Secrets + SSL Certificates before ArgoCD sync)
#   --phase data        (PostgreSQL + SQLite volumes after ArgoCD creates pods)
#   --phase all         (Default: runs both pre-deploy and data)
# ==============================================================================
set -euo pipefail

export HOME="${HOME:-/home/ubuntu}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${HOME}/.local/bin"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

PHASE="all"
if [ "${1:-}" = "--phase" ] && [ -n "${2:-}" ]; then
    PHASE="$2"
fi

BACKUP_REPO="gabrielcjr/cluster-backups"
RESTORE_DIR="/tmp/cluster_restore_staging"

download_and_extract() {
    if [ -d "${RESTORE_DIR}/secrets" ] || [ -d "${RESTORE_DIR}/databases" ]; then
        echo "=== Using cached backup in ${RESTORE_DIR} ==="
        return 0
    fi
    rm -rf "${RESTORE_DIR}"
    mkdir -p "${RESTORE_DIR}"
    echo "=== Downloading Latest Backup from GitHub Releases (${BACKUP_REPO}) ==="
    gh release download latest --repo "${BACKUP_REPO}" --pattern "*.tar.gz" --dir "${RESTORE_DIR}"
    local archive_file
    archive_file=$(find "${RESTORE_DIR}" -maxdepth 1 -name "*.tar.gz" | head -n 1)
    if [ -z "${archive_file}" ]; then
        echo "Error: No backup archive found in GitHub release!"
        exit 1
    fi
    echo "  -> Extracting ${archive_file}..."
    tar -xzf "${archive_file}" -C "${RESTORE_DIR}"
}

wait_for_pod_ready() {
    local ns="$1"
    local selector_or_name="$2"
    local timeout_sec="${3:-180}"
    local elapsed=0

    echo "  -> Waiting for ${ns}/${selector_or_name} to be scheduled..."
    until kubectl get -n "${ns}" ${selector_or_name} &>/dev/null; do
        sleep 3
        elapsed=$((elapsed + 3))
        if [ "${elapsed}" -ge "${timeout_sec}" ]; then
            echo "  Warning: Timed out waiting for ${ns}/${selector_or_name} to appear."
            return 1
        fi
    done

    if [[ "${selector_or_name}" == deployment/* ]]; then
        kubectl rollout status -n "${ns}" "${selector_or_name}" --timeout="${timeout_sec}s"
    else
        kubectl wait -n "${ns}" --for=condition=Ready "${selector_or_name}" --timeout="${timeout_sec}s"
    fi
}

run_pre_deploy() {
    download_and_extract

    echo "=== [Pre-Deploy 1/2] Restoring Kubernetes Secrets ==="
    if [ -d "${RESTORE_DIR}/secrets" ]; then
        for sec in "${RESTORE_DIR}/secrets/"*; do
            [ -f "$sec" ] || continue
            echo "  -> Applying secret: $(basename "$sec")"
            # Ensure target namespace exists and strip cluster-specific UID/resourceVersion
            local ns
            ns=$(kubectl apply -f "$sec" --dry-run=client -o json | jq -r '.metadata.namespace // "default"')
            kubectl create namespace "${ns}" 2>/dev/null || true
            kubectl apply -f "$sec" --dry-run=client -o json | \
                jq 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.managedFields, .metadata.ownerReferences)' | \
                kubectl apply -f -
        done
    fi

    echo "=== [Pre-Deploy 2/2] Restoring SSL Certificates (/etc/letsencrypt) ==="
    if [ -f "${RESTORE_DIR}/certs/letsencrypt.tar.gz" ]; then
        sudo mkdir -p /etc/letsencrypt
        sudo tar -xzf "${RESTORE_DIR}/certs/letsencrypt.tar.gz" -C /etc/
        echo "  -> SSL certificates restored to /etc/letsencrypt."
    fi
}

run_data_restore() {
    download_and_extract

    echo "=== [Data Restore 1/4] Restoring AMAE PostgreSQL ==="
    if [ -f "${RESTORE_DIR}/databases/amae_postgres.sql" ]; then
        if wait_for_pod_ready "amae" "pod/postgres-0" 180; then
            kubectl exec -i -n amae postgres-0 -- psql -U amae -d postgres < "${RESTORE_DIR}/databases/amae_postgres.sql" >/dev/null
            kubectl rollout restart deployment/web -n amae 2>/dev/null || true
            echo "  -> AMAE PostgreSQL restored."
        fi
    fi

    echo "=== [Data Restore 2/4] Restoring Jobs PostgreSQL ==="
    if [ -f "${RESTORE_DIR}/databases/jobs_postgres.sql" ]; then
        if wait_for_pod_ready "jobs" "pod/postgres-0" 180; then
            kubectl exec -i -n jobs postgres-0 -- psql -U postgres -d postgres < "${RESTORE_DIR}/databases/jobs_postgres.sql" >/dev/null
            kubectl rollout restart deployment/backend -n jobs 2>/dev/null || true
            echo "  -> Jobs PostgreSQL restored."
        fi
    fi

    echo "=== [Data Restore 3/4] Restoring KoBo SQLite Volumes (All 3 Tenants) ==="
    for tenant in kobo-missoes kobo-evangelismo kobo-getsemani; do
        local tar_file="${RESTORE_DIR}/databases/${tenant}_data.tar.gz"
        # Fallback for older backup archives that only had kobo_data.tar.gz
        if [ ! -f "${tar_file}" ] && [ "${tenant}" = "kobo-missoes" ] && [ -f "${RESTORE_DIR}/databases/kobo_data.tar.gz" ]; then
            tar_file="${RESTORE_DIR}/databases/kobo_data.tar.gz"
        fi
        if [ -f "${tar_file}" ]; then
            if wait_for_pod_ready "kobo" "deployment/${tenant}" 180; then
                cat "${tar_file}" | kubectl exec -i -n kobo "deployment/${tenant}" -- tar -xzf - -C /data
                kubectl rollout restart "deployment/${tenant}" -n kobo 2>/dev/null || true
                echo "  -> Restored ${tenant} (/data)."
            fi
        fi
    done

    echo "=== [Data Restore 4/4] Restoring Leilões Judiciais SQLite Volume ==="
    if [ -f "${RESTORE_DIR}/databases/leiloes_data.tar.gz" ]; then
        if wait_for_pod_ready "leiloes" "deployment/leiloes-web" 180; then
            cat "${RESTORE_DIR}/databases/leiloes_data.tar.gz" | kubectl exec -i -n leiloes deployment/leiloes-web -- tar -xzf - -C /app/dados
            kubectl rollout restart deployment/leiloes-web -n leiloes 2>/dev/null || true
            echo "  -> Restored Leilões (/app/dados)."
        fi
    fi

    rm -rf "${RESTORE_DIR}"
}

case "${PHASE}" in
    pre-deploy)
        run_pre_deploy
        ;;
    data)
        run_data_restore
        ;;
    all)
        run_pre_deploy
        run_data_restore
        ;;
    *)
        echo "Usage: $0 [--phase pre-deploy|data|all]"
        exit 1
        ;;
esac

echo "========================================================================"
echo "✔ Restore phase (${PHASE}) completed successfully!"
echo "========================================================================"
