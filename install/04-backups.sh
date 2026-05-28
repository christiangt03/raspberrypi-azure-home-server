#!/bin/bash
# 04-backups.sh
# Crea el Storage Account, container y lifecycle policy para backups.

set -e

RG="${RG:-rg-raspberrypi-arc}"
LOCATION="${LOCATION:-spaincentral}"
# El nombre debe ser globalmente único, 3-24 chars, alfanumérico
STORAGE_NAME="${STORAGE_NAME:-backuprpi$(date +%s | tail -c 5)}"
CONTAINER="${CONTAINER:-pi-backups}"

echo "=== 1. Crear Storage Account ==="
az storage account create \
    --name "$STORAGE_NAME" \
    --resource-group "$RG" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --access-tier Cool \
    --allow-blob-public-access false \
    --min-tls-version TLS1_2

echo "=== 2. Crear container ==="
az storage container create \
    --name "$CONTAINER" \
    --account-name "$STORAGE_NAME" \
    --auth-mode login

echo "=== 3. Aplicar lifecycle policy (borrar > 7 dias) ==="
cat > /tmp/lifecycle.json <<EOF
{
  "rules": [{
    "name": "delete-after-7-days",
    "enabled": true,
    "type": "Lifecycle",
    "definition": {
      "actions": {
        "baseBlob": {
          "delete": {
            "daysAfterModificationGreaterThan": 7
          }
        }
      },
      "filters": {
        "blobTypes": ["blockBlob"],
        "prefixMatch": ["${CONTAINER}/"]
      }
    }
  }]
}
EOF

az storage account management-policy create \
    --account-name "$STORAGE_NAME" \
    --resource-group "$RG" \
    --policy @/tmp/lifecycle.json

echo ""
echo "Storage Account creado: $STORAGE_NAME"
echo "Container: $CONTAINER"
echo ""
echo "Obtén la clave para configurar /etc/pi-backup.conf:"
echo "  Storage Key: az storage account keys list --account-name $STORAGE_NAME --resource-group $RG --query '[0].value' -o tsv"
