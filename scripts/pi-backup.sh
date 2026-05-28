#!/bin/bash
# Backup diario de la Raspberry Pi a Azure Blob Storage.
#
# Comprime /home/<usuario> + /etc + /var/spool/cron en tar.gz
# y lo sube a Azure Blob Storage. La lifecycle policy de Azure
# borra automáticamente blobs con más de 7 días.
#
# Configuración: lee credenciales de /etc/pi-backup.conf.
# Programado para correr cada noche vía systemd timer (03:00).

set -euo pipefail

CONFIG=/etc/pi-backup.conf
LOG=/var/log/pi-backup.log

# Cargar credenciales
if [ ! -r "$CONFIG" ]; then
    echo "ERROR: No se puede leer $CONFIG" >&2
    exit 1
fi
# shellcheck source=/etc/pi-backup.conf
source "$CONFIG"

# Logging
exec >> "$LOG" 2>&1
echo "============================================================"
echo "Backup iniciado: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +%Y-%m-%d-%H%M)
BACKUP_NAME="${HOSTNAME}-backup-${TIMESTAMP}.tar.gz"
TMP_FILE="/tmp/${BACKUP_NAME}"

# Detectar usuario de la home (asume primer usuario en /home)
HOME_USER=$(ls /home | head -1)
HOME_DIR="/home/${HOME_USER}"

echo "Archivo destino: $BACKUP_NAME"
echo "Home a respaldar: $HOME_DIR"
echo ""
echo "--- Creando archivo comprimido ---"
START=$(date +%s)

tar --create \
    --gzip \
    --file "$TMP_FILE" \
    --absolute-names \
    --exclude="${HOME_DIR}/.cache" \
    --exclude="${HOME_DIR}/.local/share/Trash" \
    --exclude="${HOME_DIR}/.npm" \
    --exclude="${HOME_DIR}/.clientsshproxy" \
    --exclude="${HOME_DIR}/.azure/logs" \
    --exclude='*/node_modules' \
    --exclude='*/__pycache__' \
    --exclude='*.pyc' \
    "$HOME_DIR" \
    /etc \
    /var/spool/cron 2>/dev/null || true

SIZE=$(du -h "$TMP_FILE" | cut -f1)
ELAPSED_TAR=$(($(date +%s) - START))
echo "Archivo creado: $SIZE en ${ELAPSED_TAR}s"

echo ""
echo "--- Subiendo a Azure Blob Storage ---"
START_UP=$(date +%s)

az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$STORAGE_KEY" \
    --container-name "$CONTAINER" \
    --name "$BACKUP_NAME" \
    --file "$TMP_FILE" \
    --overwrite \
    --no-progress 2>&1 | tail -5

ELAPSED_UP=$(($(date +%s) - START_UP))
echo "Subida completada en ${ELAPSED_UP}s"

echo ""
echo "--- Limpieza local ---"
rm -f "$TMP_FILE"
echo "Archivo temporal borrado"

echo ""
echo "--- Backups en Azure (últimos) ---"
az storage blob list \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$STORAGE_KEY" \
    --container-name "$CONTAINER" \
    --query "reverse(sort_by([], &properties.creationTime))[].{name:name, size:properties.contentLength, created:properties.creationTime}" \
    --output table 2>&1 | head -10

TOTAL_ELAPSED=$(($(date +%s) - START))
echo ""
echo "Backup completado en ${TOTAL_ELAPSED}s total - $(date '+%H:%M:%S')"
echo ""
