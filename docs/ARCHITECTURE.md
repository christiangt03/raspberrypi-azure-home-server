# Arquitectura

```
┌─────────────────────────────────┐         ┌─────────────────────────────────┐
│         EN CASA (LAN)           │         │      MICROSOFT AZURE            │
│                                 │         │                                 │
│  ┌─────────────────────────┐    │         │   ┌─────────────────────────┐   │
│  │   Raspberry Pi 3        │    │         │   │   rg-raspberrypi-arc    │   │
│  │   Debian 13 ARM64       │    │         │   │   (spaincentral)        │   │
│  │   192.168.1.22          │    │         │   │                         │   │
│  │                         │    │HTTPS 443│   │   ┌───────────────┐     │   │
│  │   ┌───────────────┐     │◄───┼─────────┼───┤   │  Azure Arc    │     │   │
│  │   │  Pi-Hole DNS  │     │    │ (tunel) │   │   │  Connected    │     │   │
│  │   │  (puerto 53)  │     │    │         │   │   │  Machine      │     │   │
│  │   └───────────────┘     │    │         │   │   └───────┬───────┘     │   │
│  │                         │    │         │   │           │             │   │
│  │   ┌───────────────┐     │    │         │   │   ┌───────▼───────┐     │   │
│  │   │  azcmagent    │     │    │         │   │   │ Log Analytics │     │   │
│  │   │  (Arc agent)  │─────┼────┼─────────┼───┼───►│ PiMetrics_CL │     │   │
│  │   └───────────────┘     │    │HTTPS 443│   │   └───────┬───────┘     │   │
│  │                         │    │         │   │           │             │   │
│  │   ┌───────────────┐     │    │         │   │   ┌───────▼───────┐     │   │
│  │   │ pi-monitor.py │─────┼────┼─────────┼───┼───►│  4 Alertas    │     │   │
│  │   │ (cada 60s)    │     │    │HTTP DCA │   │   │  (KQL queries)│     │   │
│  │   └───────────────┘     │    │  API    │   │   └───────┬───────┘     │   │
│  │                         │    │         │   │           │             │   │
│  │   ┌───────────────┐     │    │         │   │   ┌───────▼───────┐     │   │
│  │   │ pi-backup.sh  │─────┼────┼─────────┼───┼───►│ Action Group  │     │   │
│  │   │ (diario 03:00)│     │    │         │   │   │ → email       │     │   │
│  │   └───────────────┘     │    │HTTPS 443│   │   └───────────────┘     │   │
│  │           │             │    │         │   │                         │   │
│  │           │ tar.gz      │    │         │   │   ┌───────────────┐     │   │
│  │           └─────────────┼────┼─────────┼───┼───►│ Blob Storage  │     │   │
│  │                         │    │         │   │   │ pi-backups    │     │   │
│  └─────────────────────────┘    │         │   │   │ (7 dias)      │     │   │
│                                 │         │   │   └───────────────┘     │   │
│  ┌─────────────────────────┐    │         │   │                         │   │
│  │  Dispositivos LAN       │    │         │   │   ┌───────────────┐     │   │
│  │  (móvil, smart TV,      │    │         │   │   │ Action Group  │     │   │
│  │   tablet, consola)      │    │         │   │   │ → email       │     │   │
│  │                         │    │         │   │   └───────────────┘     │   │
│  │  DNS → 192.168.1.22 ────┼────┤         │   │                         │   │
│  └─────────────────────────┘    │         │   └─────────────────────────┘   │
└─────────────────────────────────┘         └─────────────────────────────────┘
```

## Componentes en la Pi

### Pi-Hole (DNS sinkhole)
- Versión 6.4.2
- Lista StevenBlack: 82.000+ dominios bloqueados
- Servicio `pihole-FTL` en puerto 53 (UDP+TCP)
- Panel web: `http://<IP-Pi>/admin`

### Azure Connected Machine Agent (azcmagent)
- Versión 1.64.03414.1079 (paquete arm64)
- Servicios systemd: `himdsd`, `arcproxyd`, `gcad`, `extd`
- Mantiene una conexión saliente HTTPS persistente a Azure

### pi-monitor.py
- Script Python 3 puro (sin dependencias externas)
- Cada 60 segundos (vía systemd timer):
  - Lee `/proc/stat`, `/proc/meminfo`, `statvfs()`, `/sys/class/thermal/thermal_zone0/temp`
  - Construye un JSON con las métricas
  - Firma con HMAC-SHA256 usando el primary key del workspace
  - Hace POST al endpoint HTTP Data Collector API
  - Los datos llegan a la tabla `PiMetrics_CL` en Log Analytics

### pi-backup.sh
- Script Bash con `set -euo pipefail`
- Cada noche a las 03:00 (vía systemd timer):
  - Empaqueta `/home/<usuario>`, `/etc`, `/var/spool/cron` en tar.gz
  - Excluye cachés, papelera, node_modules, etc.
  - Sube el archivo a Azure Blob Storage usando `az storage blob upload`
  - Limpia el archivo temporal local

## Componentes en Azure

### Resource Group `rg-raspberrypi-arc`
Contenedor lógico de todos los recursos. Región `spaincentral` (Madrid).

### Microsoft.HybridCompute/machines/raspberrypi-trk
La Pi registrada como recurso de Azure Arc. Permite gestión remota, SSH via Arc, y aplicación de extensiones.

### Microsoft.HybridConnectivity/endpoints/default
Endpoint que habilita SSH a la Pi a través de Azure (sin abrir puertos locales).

### Microsoft.OperationalInsights/workspaces/law-raspberrypi
Workspace de Log Analytics. SKU `PerGB2018`, retención 30 días.

### Microsoft.Insights/actiongroups/ag-raspberrypi
Action group que envía emails cuando se dispara alguna alerta.

### 4× Microsoft.Insights/scheduledQueryRules
- `alert-pi-cpu-high`: CPU > 80% durante 5 min
- `alert-pi-ram-low`: RAM disponible < 15%
- `alert-pi-disk-low`: Disco libre < 10%
- `alert-pi-heartbeat-lost`: Sin datos > 10 min

### Microsoft.Storage/storageAccounts/backuprpitrkXXXX
Standard_LRS, kind StorageV2, access tier Cool. Container `pi-backups` con lifecycle policy `delete-after-7-days`.

## Flujo de datos

1. **Métricas:** la Pi genera datos cada minuto → HTTPS POST firmado → Log Analytics → consultable con KQL.
2. **Alertas:** Azure Monitor ejecuta queries KQL cada 5 min → si se cumple condición → Action Group → email.
3. **Backups:** la Pi comprime y sube cada noche → Blob Storage → lifecycle policy borra blobs > 7 días automáticamente.
4. **Acceso remoto:** cliente con `az ssh arc` → endpoint de HybridConnectivity → túnel cifrado → SSH a la Pi.
5. **DNS:** dispositivos LAN consultan a 192.168.1.22 (Pi-Hole) → bloquea o reenvía a upstream (1.1.1.1).
