#!/bin/bash
# 03-monitoring.sh
# Crea el Log Analytics Workspace, Action Group y 4 alertas.

set -e

RG="${RG:-rg-raspberrypi-arc}"
LOCATION="${LOCATION:-spaincentral}"
WORKSPACE_NAME="${WORKSPACE_NAME:-law-raspberrypi}"
ACTION_GROUP_NAME="${ACTION_GROUP_NAME:-ag-raspberrypi}"
ALERT_EMAIL="${ALERT_EMAIL:-your.email@example.com}"

echo "=== 1. Registrar providers ==="
az provider register --namespace Microsoft.OperationalInsights --wait
az provider register --namespace Microsoft.Insights --wait
az provider register --namespace Microsoft.AlertsManagement --wait

echo "=== 2. Crear Log Analytics Workspace ==="
az monitor log-analytics workspace create \
    --resource-group "$RG" \
    --workspace-name "$WORKSPACE_NAME" \
    --location "$LOCATION" \
    --sku PerGB2018 \
    --retention-time 30

echo "=== 3. Crear Action Group con email ==="
az monitor action-group create \
    --name "$ACTION_GROUP_NAME" \
    --resource-group "$RG" \
    --short-name PiAlerts \
    --action email contacto "$ALERT_EMAIL"

SUB=$(az account show --query id -o tsv)
LAW_ID="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE_NAME"
AG_ID="/subscriptions/$SUB/resourceGroups/$RG/providers/microsoft.insights/actionGroups/$ACTION_GROUP_NAME"

echo "=== 4. Crear 4 alertas ==="

# Alerta CPU
az monitor scheduled-query create \
    -n "alert-pi-cpu-high" -g "$RG" \
    --scopes "$LAW_ID" \
    --condition "count 'cpu' > 0 at least 1 violations out of 1 aggregated points" \
    --condition-query cpu="PiMetrics_CL | summarize avgCpu=avg(CpuPercent_d) by bin(TimeGenerated, 5m), Computer | where avgCpu > 80" \
    --window-size 15m --evaluation-frequency 5m --severity 2 \
    --description "Raspberry Pi: CPU > 80% durante 5 min" \
    --action-groups "$AG_ID"

# Alerta RAM
az monitor scheduled-query create \
    -n "alert-pi-ram-low" -g "$RG" \
    --scopes "$LAW_ID" \
    --condition "count 'mem' > 0 at least 1 violations out of 1 aggregated points" \
    --condition-query mem="PiMetrics_CL | summarize avgMem=avg(MemAvailablePercent_d) by bin(TimeGenerated, 5m), Computer | where avgMem < 15" \
    --window-size 15m --evaluation-frequency 5m --severity 2 \
    --description "Raspberry Pi: RAM disponible < 15% durante 5 min" \
    --action-groups "$AG_ID"

# Alerta Disco
az monitor scheduled-query create \
    -n "alert-pi-disk-low" -g "$RG" \
    --scopes "$LAW_ID" \
    --condition "count 'disk' > 0 at least 1 violations out of 1 aggregated points" \
    --condition-query disk="PiMetrics_CL | summarize avgDisk=avg(DiskFreePercent_d) by bin(TimeGenerated, 5m), Computer | where avgDisk < 10" \
    --window-size 15m --evaluation-frequency 5m --severity 1 \
    --description "Raspberry Pi: Disco libre < 10%" \
    --action-groups "$AG_ID"

# Alerta Heartbeat
az monitor scheduled-query create \
    -n "alert-pi-heartbeat-lost" -g "$RG" \
    --scopes "$LAW_ID" \
    --condition "count 'hb' < 1 at least 1 violations out of 1 aggregated points" \
    --condition-query hb="PiMetrics_CL" \
    --window-size 10m --evaluation-frequency 5m --severity 1 \
    --description "Raspberry Pi: Sin datos en 10 min (Pi desconectada o script fallando)" \
    --action-groups "$AG_ID"

echo ""
echo "Workspace, Action Group y 4 alertas creadas."
echo ""
echo "Obtén las claves del workspace para configurar /etc/pi-monitor.conf:"
echo "  Customer ID:    az monitor log-analytics workspace show -g $RG -n $WORKSPACE_NAME --query customerId -o tsv"
echo "  Primary Key:    az monitor log-analytics workspace get-shared-keys -g $RG -n $WORKSPACE_NAME --query primarySharedKey -o tsv"
