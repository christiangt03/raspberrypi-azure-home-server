#!/bin/bash
# 01-azure-arc.sh
# Instala Azure CLI y conecta la Raspberry Pi a Azure Arc.
# Funciona en Debian 13 ARM64 (workaround incluido para el bug del script oficial).

set -e

# Variables - PERSONALIZA ESTAS
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-YOUR_SUBSCRIPTION_ID}"
TENANT_ID="${TENANT_ID:-YOUR_TENANT_ID}"
RG="${RG:-rg-raspberrypi-arc}"
LOCATION="${LOCATION:-spaincentral}"
MACHINE_NAME="${MACHINE_NAME:-raspberrypi-trk}"

echo "=== 1. Instalar Azure CLI ==="
if ! command -v az > /dev/null; then
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
fi

echo "=== 2. Login a Azure (device code) ==="
az login --use-device-code

echo "=== 3. Registrar resource providers ==="
az provider register --namespace Microsoft.HybridCompute --wait
az provider register --namespace Microsoft.GuestConfiguration --wait
az provider register --namespace Microsoft.HybridConnectivity --wait

echo "=== 4. Crear resource group ==="
az group create --name "$RG" --location "$LOCATION"

echo "=== 5. Instalar azcmagent (workaround ARM64) ==="
# El script oficial aka.ms/azcmagent instala paquete amd64
# en Debian 13. Descargamos manualmente el .deb arm64 del repo bookworm.
cd /tmp
wget -q "https://packages.microsoft.com/debian/12/prod/pool/main/a/azcmagent/azcmagent_1.64.03414.1079_arm64.deb" \
     -O azcmagent_arm64.deb
sudo dpkg -i azcmagent_arm64.deb

echo "=== 6. Conectar la Pi a Azure Arc ==="
sudo azcmagent connect \
    --resource-group "$RG" \
    --tenant-id "$TENANT_ID" \
    --location "$LOCATION" \
    --subscription-id "$SUBSCRIPTION_ID" \
    --resource-name "$MACHINE_NAME"

echo ""
echo "Pi conectada a Azure Arc como $MACHINE_NAME"
echo "Verifica: sudo azcmagent show"
