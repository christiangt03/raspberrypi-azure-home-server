#!/bin/bash
# 05-deploy-scripts.sh
# Instala los scripts y los timers de systemd en la Pi.
# Ejecutar DESPUES de configurar /etc/pi-monitor.conf y /etc/pi-backup.conf.

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== 1. Instalar scripts ==="
sudo install -m 755 -o root -g root "$REPO_DIR/scripts/pi-monitor.py" /usr/local/bin/pi-monitor.py
sudo install -m 700 -o root -g root "$REPO_DIR/scripts/pi-backup.sh" /usr/local/bin/pi-backup.sh

echo "=== 2. Instalar archivos systemd ==="
sudo install -m 644 "$REPO_DIR/systemd/pi-monitor.service" /etc/systemd/system/
sudo install -m 644 "$REPO_DIR/systemd/pi-monitor.timer" /etc/systemd/system/
sudo install -m 644 "$REPO_DIR/systemd/pi-backup.service" /etc/systemd/system/
sudo install -m 644 "$REPO_DIR/systemd/pi-backup.timer" /etc/systemd/system/

echo "=== 3. Activar timers ==="
sudo systemctl daemon-reload
sudo systemctl enable --now pi-monitor.timer
sudo systemctl enable --now pi-backup.timer

echo "=== 4. Verificar ==="
systemctl list-timers pi-monitor.timer pi-backup.timer --no-pager

echo ""
echo "Scripts desplegados y timers activos."
echo "Para probar manualmente:"
echo "  sudo /usr/local/bin/pi-monitor.py"
echo "  sudo /usr/local/bin/pi-backup.sh"
