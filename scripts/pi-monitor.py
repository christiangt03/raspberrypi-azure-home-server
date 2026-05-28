#!/usr/bin/env python3
"""Recolector de metricas de la Raspberry Pi -> Azure Log Analytics.

Lee CPU, RAM, disco y temperatura del sistema y los envia
mediante HTTPS firmado con HMAC-SHA256 al HTTP Data Collector
API de Azure Log Analytics. La tabla destino se llama
PiMetrics_CL y se crea automaticamente en el workspace.

Configuracion: lee credenciales de /etc/pi-monitor.conf.
Programado para correr cada minuto vía systemd timer.
"""

import base64
import hashlib
import hmac
import json
import socket
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

CONFIG_PATH = "/etc/pi-monitor.conf"


def load_config():
    cfg = {}
    for line in Path(CONFIG_PATH).read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            cfg[k.strip()] = v.strip()
    return cfg


def cpu_percent(interval=1.0):
    def read():
        with open("/proc/stat") as f:
            parts = f.readline().split()
        vals = [int(x) for x in parts[1:]]
        idle = vals[3] + vals[4]
        total = sum(vals)
        return idle, total

    idle1, total1 = read()
    time.sleep(interval)
    idle2, total2 = read()
    didle = idle2 - idle1
    dtotal = total2 - total1
    if dtotal == 0:
        return 0.0
    return round(100.0 * (dtotal - didle) / dtotal, 2)


def mem_info():
    info = {}
    with open("/proc/meminfo") as f:
        for line in f:
            key, _, rest = line.partition(":")
            info[key.strip()] = int(rest.strip().split()[0])
    total_kb = info["MemTotal"]
    avail_kb = info["MemAvailable"]
    used_kb = total_kb - avail_kb
    return {
        "MemTotalMB": round(total_kb / 1024, 1),
        "MemAvailableMB": round(avail_kb / 1024, 1),
        "MemUsedPercent": round(100.0 * used_kb / total_kb, 2),
        "MemAvailablePercent": round(100.0 * avail_kb / total_kb, 2),
    }


def disk_info(path="/"):
    import os
    st = os.statvfs(path)
    total = st.f_blocks * st.f_frsize
    free = st.f_bavail * st.f_frsize
    used = total - free
    return {
        "DiskTotalGB": round(total / (1024 ** 3), 2),
        "DiskFreeGB": round(free / (1024 ** 3), 2),
        "DiskUsedPercent": round(100.0 * used / total, 2),
        "DiskFreePercent": round(100.0 * free / total, 2),
    }


def cpu_temperature():
    try:
        with open("/sys/class/thermal/thermal_zone0/temp") as f:
            return round(int(f.read().strip()) / 1000.0, 1)
    except Exception:
        return None


def build_signature(workspace_id, shared_key, date, content_length):
    string_to_hash = (
        f"POST\n{content_length}\napplication/json\nx-ms-date:{date}\n/api/logs"
    )
    decoded_key = base64.b64decode(shared_key)
    digest = hmac.new(
        decoded_key, string_to_hash.encode("utf-8"), hashlib.sha256
    ).digest()
    return f"SharedKey {workspace_id}:{base64.b64encode(digest).decode()}"


def post_metrics(cfg, records):
    body = json.dumps(records).encode("utf-8")
    date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT")
    auth = build_signature(cfg["WORKSPACE_ID"], cfg["WORKSPACE_KEY"], date, len(body))
    url = f"https://{cfg['WORKSPACE_ID']}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("content-type", "application/json")
    req.add_header("Authorization", auth)
    req.add_header("Log-Type", cfg["LOG_TYPE"])
    req.add_header("x-ms-date", date)
    req.add_header("time-generated-field", "TimeGenerated")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.status


def main():
    cfg = load_config()
    cpu = cpu_percent(interval=1.0)
    mem = mem_info()
    disk = disk_info("/")
    temp = cpu_temperature()
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    record = {
        "TimeGenerated": now,
        "Computer": socket.gethostname(),
        "CpuPercent": cpu,
        "CpuTempC": temp,
        **mem,
        **disk,
    }
    try:
        status = post_metrics(cfg, [record])
        print(f"OK status={status} cpu={cpu}% mem_used={record['MemUsedPercent']}% disk_used={record['DiskUsedPercent']}%")
        return 0
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
