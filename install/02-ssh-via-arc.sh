#!/bin/bash
# 02-ssh-via-arc.sh
# Habilita SSH a la Pi a través de Azure Arc (sin abrir puertos en el router).

set -e

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-YOUR_SUBSCRIPTION_ID}"
RG="${RG:-rg-raspberrypi-arc}"
MACHINE_NAME="${MACHINE_NAME:-raspberrypi-trk}"

BASE="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.HybridCompute/machines/$MACHINE_NAME/providers/Microsoft.HybridConnectivity/endpoints"

echo "=== 1. Crear endpoint 'default' ==="
az rest --method put \
    --uri "${BASE}/default?api-version=2023-03-15" \
    --body '{"properties":{"type":"default"}}'

echo "=== 2. Habilitar SSH en puerto 22 ==="
az rest --method put \
    --uri "${BASE}/default/serviceConfigurations/SSH?api-version=2023-03-15" \
    --body '{"properties":{"serviceName":"SSH","port":22}}'

echo ""
echo "SSH via Arc habilitado."
echo "Desde cualquier equipo con Azure CLI puedes conectarte:"
echo "  az extension add --name ssh"
echo "  az login"
echo "  az ssh arc -g $RG -n $MACHINE_NAME --local-user <tu_usuario>"
