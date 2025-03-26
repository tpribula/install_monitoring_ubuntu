#!/bin/bash

set -e
set -u

# Detect Ubuntu machine's IP address
IP_ADDRESS=$(hostname -I | awk '{print $1}')

# VMware vSphere Credentials (Set These Before Running)
VSPHERE_HOST="your-vcenter-ip-or-hostname"
VSPHERE_USER="vsphere-username"
VSPHERE_PASSWORD="your-password"
EMAIL_ADDRESS="your-email-address"
EMAIL_PASSWORD="your-password"

echo "🚀 Detected machine IP address: $IP_ADDRESS"

echo "🛠 Updating system..."
sudo apt update && sudo apt upgrade -y

echo "🛠 Installing required packages..."
sudo apt install -y wget curl unzip python3-pip

# -------------------------------
# Install Prometheus
# -------------------------------
echo "🛠 Installing Prometheus..."
PROMETHEUS_VERSION="3.2.1"  # Updated to the latest version
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v$PROMETHEUS_VERSION/prometheus-$PROMETHEUS_VERSION.linux-amd64.tar.gz
tar xvf prometheus-$PROMETHEUS_VERSION.linux-amd64.tar.gz
sudo mv prometheus-$PROMETHEUS_VERSION.linux-amd64 /usr/local/prometheus

echo "🔧 Creating Prometheus configuration..."
sudo tee /usr/local/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "vmware"
    static_configs:
      - targets: ["$IP_ADDRESS:9272"]
EOF

echo "🔧 Creating Prometheus systemd service..."
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus
After=network.target

[Service]
ExecStart=/usr/local/prometheus/prometheus --config.file=/usr/local/prometheus/prometheus.yml
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus

echo "✅ Prometheus Installed & Running!"

# -------------------------------
# Install Grafana
# -------------------------------
echo "🛠 Installing Grafana..."
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
sudo apt update
sudo apt install -y grafana

sudo tee -a /etc/grafana/grafana.ini > /dev/null <<EOL

#################################### SMTP Configuration ######################
[smtp]
enabled = true
host = smtp.gmail.com:587
user = $EMAIL_ADDRESS
password = "$EMAIL_PASSWORD"
from_address = $EMAIL_ADDRESS
from_name = Grafana Alerts
ehlo_identity = grafana.local
startTLS_policy = OpportunisticStartTLS
EOF

sudo systemctl enable grafana-server
sudo systemctl start grafana-server

echo "✅ Grafana Installed & Running!"
echo "🎨 Access Grafana at http://$IP_ADDRESS:3000 (Login: admin/admin)"

# -------------------------------
# Install VMware Exporter
# -------------------------------
echo "🛠 Installing vmware_exporter..."
sudo useradd vmware

pip3 install vmware-exporter

echo "🔧 Creating vmware_exporter configuration..."
sudo mkdir -p /opt/vmware_exporter
sudo cat <<EOF | sudo tee /opt/vmware_exporter/config.yml > /dev/null
default:
  vsphere_host: "$VSPHERE_HOST"
  vsphere_user: "$VSPHERE_USER"
  vsphere_password: "$VSPHERE_PASSWORD"
  ignore_ssl: True
  specs_size: 5000
  fetch_custom_attributes: False
  fetch_tags: False
  fetch_alarms: False
  collect_only:
    vms: True
    vmguests: False
    datastores: False
    hosts: True
    snapshots: False
EOF

echo "🔧 Creating vmware_exporter systemd service..."
sudo tee /etc/systemd/system/vmware_exporter.service > /dev/null <<EOF
[Unit]
Description=VMware Exporter for Prometheus
After=network.target

[Service]
Type=simple
User=vmware
Group=vmware
ExecStart=/usr/local/bin/vmware_exporter -c /opt/vmware_exporter/config.yml
WorkingDirectory=/opt/vmware_exporter

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable vmware_exporter
sudo systemctl start vmware_exporter

echo "✅ VMware Exporter Installed & Running!"

# -------------------------------
# Installation Complete
# -------------------------------
echo "🎉 All services are installed and running!"
echo "🔹 Prometheus → http://$IP_ADDRESS:9090"
echo "🔹 Grafana → http://$IP_ADDRESS:3000 (admin/admin - first login)"
echo "🔹 VMware Exporter Metrics → http://$IP_ADDRESS:9272/metrics"
