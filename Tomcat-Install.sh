#!/bin/bash

set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# Install Java (Tomcat needs Java)
echo "=== Step 1: Install Java on Ubuntu 24.04 ==="
apt-get update -y
apt-get install -y openjdk-17-jdk wget tar

echo "=== Step 2: Create a Tomcat user ==="
id tomcat >/dev/null 2>&1 || useradd -m -U -d /opt/tomcat -s /bin/false tomcat

echo "=== Step 3: Install Tomcat on Ubuntu ==="
TOMCAT_VERSION="10.1.24"
TOMCAT_TGZ="apache-tomcat-${TOMCAT_VERSION}.tar.gz"

# Download Tomcat (latest stable Tomcat 10.x)
# Prefer official CDN; fallback to archive if needed
cd /tmp
wget -q "https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/${TOMCAT_TGZ}" \
  || wget -q "https://archive.apache.org/dist/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/${TOMCAT_TGZ}"

mkdir -p /opt/tomcat

# Extract into /opt/tomcat (strip the top-level folder)
tar -xzf "/tmp/${TOMCAT_TGZ}" -C /opt/tomcat --strip-components=1

# Set permissions
echo "=== Step 4: Update permissions of Tomcat ==="
chown -R tomcat:tomcat /opt/tomcat
chmod -R u+x /opt/tomcat/bin

# Configure Tomcat service
echo "=== Step 5: Configure Tomcat as a service ==="
cat >/etc/systemd/system/tomcat.service <<'EOF'
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=simple
User=tomcat
Group=tomcat
Environment="JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_BASE=/opt/tomcat"
ExecStart=/opt/tomcat/bin/catalina.sh run
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start Tomcat
echo "=== Step 6: Reload systemd and Start Tomcat ==="
systemctl daemon-reload
systemctl enable --now tomcat

echo "=== Done: Tomcat installation finished ==="

######## Lines Above Installed Tomcat successfully #########

# Add admin user to tomcat-users.xml
sed -i '/<\/tomcat-users>/i \
<role rolename="admin-gui"/>\n\
<role rolename="admin-script"/>\n\
<user username="admin" password="StrongPassword123" roles="admin-gui,admin-script"/>' /opt/tomcat/conf/tomcat-users.xml

# Remove the RemoteAddrValve line in host-manager
sed -i '/RemoteAddrValve/d' /opt/tomcat/webapps/host-manager/META-INF/context.xml

# Remove the RemoteAddrValve line in manager
sed -i '/RemoteAddrValve/d' /opt/tomcat/webapps/manager/META-INF/context.xml

# Restart The Tomcat Application
sudo systemctl restart tomcat

# ----------------------------------------
# Install and Configure Ansible
# ----------------------------------------
# Create ansible user with sudo privileges
# sudo useradd -m -s /bin/bash ansible
sudo useradd ansible -m 
echo 'ansible:ansible' | sudo chpasswd
sudo usermod -aG sudo ansible

# Give user Authorization | Without Needing Password
sudo EDITOR='tee -a' visudo << 'EOF'
ansible ALL=(ALL) NOPASSWD:ALL
EOF

# Update the sshd_config Authentication file (Password and SSH)
sudo sed -i 's@^#\?PasswordAuthentication .*@PasswordAuthentication yes@' /etc/ssh/sshd_config
sudo sed -i '/^PasswordAuthentication yes/a ChallengeResponseAuthentication yes' /etc/ssh/sshd_config
sudo systemctl restart ssh

# ----------------------------------------
# Install and Configure Node Exporter
# ----------------------------------------
# Create node_exporter user
sudo useradd --no-create-home node_exporter

# Download and install Node Exporter
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v1.0.1/node_exporter-1.0.1.linux-amd64.tar.gz
tar xzf node_exporter-1.0.1.linux-amd64.tar.gz
sudo cp node_exporter-1.0.1.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-1.0.1.linux-amd64*

# Download service file directly from GitHub (instead of assuming it exists locally)
sudo wget -O /etc/systemd/system/node-exporter.service \
https://raw.githubusercontent.com/awanmbandi/realworld-cicd-pipeline-project/refs/heads/prometheus-and-grafana-install/node-exporter.service

# Reload systemd and enable/start Node Exporter
sudo systemctl daemon-reload
sudo systemctl enable node-exporter
sudo systemctl start node-exporter