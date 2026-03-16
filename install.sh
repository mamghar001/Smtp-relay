#!/bin/bash
# install.sh - Complete installer for Haraka SMTP Relay with Web Monitoring
# Usage: sudo ./install.sh
# This script sets up everything on a fresh VPS

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARAKA_DIR="/opt/haraka-src"
CONFIG_DIR="/etc/haraka"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error "Please run as root (sudo ./install.sh)"
    exit 1
fi

echo "=========================================="
echo "Haraka SMTP Relay - Complete Installer"
echo "=========================================="
echo ""

# Update system
log "Updating system packages..."
apt-get update -qq

# Install dependencies
log "Installing dependencies (curl, git, build-essential)..."
apt-get install -y -qq curl git build-essential sshpass net-tools

# Install Node.js
log "Installing Node.js 22..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null
    apt-get install -y -qq nodejs
    log "Node.js installed: $(node --version)"
else
    log "Node.js already installed: $(node --version)"
fi

# Install Haraka from source
log "Installing Haraka from GitHub..."
if [ ! -d "$HARAKA_DIR" ]; then
    git clone --depth 1 https://github.com/haraka/Haraka.git "$HARAKA_DIR" > /dev/null 2>&1
    cd "$HARAKA_DIR"
    npm install > /dev/null 2>&1
    npm link > /dev/null 2>&1
    log "Haraka installed successfully"
else
    warn "Haraka already exists at $HARAKA_DIR"
fi

# Create Haraka configuration directory
log "Setting up Haraka configuration..."
mkdir -p "$CONFIG_DIR/config"
mkdir -p "$CONFIG_DIR/plugins"
mkdir -p "$CONFIG_DIR/config/tls"
mkdir -p "$CONFIG_DIR/html"

# Copy main plugin
cp "$REPO_DIR/rotate_senders.js" "$CONFIG_DIR/plugins/"
chmod 644 "$CONFIG_DIR/plugins/rotate_senders.js"
log "Main plugin (rotate_senders.js) installed"

# Copy optional plugins
if [ -f "$REPO_DIR/plugins/human_delay.js" ]; then
    cp "$REPO_DIR/plugins/human_delay.js" "$CONFIG_DIR/plugins/"
    chmod 644 "$CONFIG_DIR/plugins/human_delay.js"
    log "human_delay plugin installed"
fi

# Copy all config files
log "Installing configuration files..."
cp "$REPO_DIR/config/plugins" "$CONFIG_DIR/config/"
cp "$REPO_DIR/config/auth_flat_file.ini" "$CONFIG_DIR/config/"
cp "$REPO_DIR/config/smtp.ini" "$CONFIG_DIR/config/" 2>/dev/null || true
cp "$REPO_DIR/config/graph.ini" "$CONFIG_DIR/config/" 2>/dev/null || true
cp "$REPO_DIR/config/http.ini" "$CONFIG_DIR/config/" 2>/dev/null || true

# Create mailboxes.json if it doesn't exist
if [ ! -f "$CONFIG_DIR/config/mailboxes.json" ]; then
    cat > "$CONFIG_DIR/config/mailboxes.json" << 'EOF'
{
  "mailboxes": [
    {
      "host": "mail.yourdomain.com",
      "user": "sender@yourdomain.com",
      "pass": "yourpassword",
      "displayName": "Sender Name"
    }
  ]
}
EOF
    chmod 644 "$CONFIG_DIR/config/mailboxes.json"
    warn "Created sample mailboxes.json - YOU MUST EDIT THIS FILE!"
fi

# Install npm dependencies for web monitoring
log "Installing web monitoring dependencies..."
cd "$CONFIG_DIR"
npm install express sqlite3 haraka-plugin-graph haraka-plugin-watch > /dev/null 2>&1 || {
    warn "Some npm packages may have warnings, continuing..."
}
log "Dependencies installed (express, sqlite3, graph, watch plugins)"

# Set permissions
chmod 644 "$CONFIG_DIR/config/"*.ini 2>/dev/null || true
chmod 644 "$CONFIG_DIR/config/"*.json 2>/dev/null || true
chmod 755 "$CONFIG_DIR/plugins/"*.js

# Create systemd service
log "Creating systemd service..."
cat > /etc/systemd/system/haraka.service << 'EOF'
[Unit]
Description=Haraka SMTP Relay
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/haraka
ExecStart=/opt/haraka-src/bin/haraka -c /etc/haraka
Restart=always
RestartSec=5
StandardOutput=append:/var/log/haraka.log
StandardError=append:/var/log/haraka.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable haraka
log "Systemd service created and enabled"

# Create log file
touch /var/log/haraka.log
chmod 644 /var/log/haraka.log

# Create helper scripts
log "Creating helper scripts..."

# Haraka stats script
cat > /usr/local/bin/haraka-stats << 'SCRIPT'
#!/bin/bash
# Quick stats for Haraka relay

LOG_FILE="/var/log/haraka.log"
MAILBOX_FILE="/etc/haraka/config/mailboxes.json"

echo "=========================================="
echo "📊 HARAKA SMTP RELAY STATS"
echo "=========================================="
echo ""

# Active connections
echo "📡 Active Connections:"
ss -tlnp 2>/dev/null | grep -E ":587|:8080" || netstat -tlnp 2>/dev/null | grep -E ":587|:8080" || echo "  (unable to check ports)"
echo ""

# Emails sent
if [ -f "$LOG_FILE" ]; then
    SENT=$(grep -c "Message Queued" "$LOG_FILE" 2>/dev/null || echo "0")
    DELIVERED=$(grep -c "delivered" "$LOG_FILE" 2>/dev/null || echo "0")
    echo "📧 Emails Queued: $SENT"
    echo "✅ Emails Delivered: $DELIVERED"
    echo ""
    
    # Recent rotations
    echo "🔄 Recent Rotations:"
    grep "ROTATE DATA" "$LOG_FILE" 2>/dev/null | tail -5 | sed 's/.*ROTATE DATA/  🔄/' || echo "  (no recent rotations)"
    echo ""
    
    # Recent errors
    ERRORS=$(grep -c "ERROR" "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$ERRORS" -gt 0 ]; then
        echo "⚠️  Errors in log: $ERRORS"
        echo ""
    fi
else
    echo "📧 Log file not found yet (service may not have run)"
    echo ""
fi

# Mailbox count
if [ -f "$MAILBOX_FILE" ]; then
    COUNT=$(grep -c '"host"' "$MAILBOX_FILE" 2>/dev/null || echo "0")
    echo "📬 Mailboxes configured: $COUNT"
    echo ""
fi

# Web interfaces
echo "🌐 Web Interfaces:"
echo "  • Real-time: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP'):8080/watch/"
echo "  • Graphs:    http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP'):8080/graph"
echo ""

# Service status
echo "🔧 Service Status:"
systemctl is-active haraka > /dev/null 2>&1 && echo "  ✅ Haraka is running" || echo "  ❌ Haraka is stopped"
echo ""
echo "=========================================="
SCRIPT
chmod +x /usr/local/bin/haraka-stats

# Mailbox import script
cat > /usr/local/bin/haraka-import << 'SCRIPT'
#!/bin/bash
# Import mailboxes from CSV to JSON
# Usage: haraka-import mailboxes.csv

CSV_FILE="$1"
MAILBOX_FILE="/etc/haraka/config/mailboxes.json"

if [ -z "$CSV_FILE" ]; then
    echo "Usage: haraka-import <csv_file>"
    echo ""
    echo "CSV format: host,user,pass,displayName"
    echo "Example: mail.domain.com,sender@domain.com,pass123,John Doe"
    exit 1
fi

if [ ! -f "$CSV_FILE" ]; then
    echo "Error: File not found: $CSV_FILE"
    exit 1
fi

# Backup existing
cp "$MAILBOX_FILE" "${MAILBOX_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Convert CSV to JSON
python3 << 'PYEOF'
import csv
import json
import sys

csv_file = "$CSV_FILE"
json_file = "/etc/haraka/config/mailboxes.json"

mailboxes = []
try:
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            mailboxes.append({
                "host": row.get("host", ""),
                "user": row.get("user", ""),
                "pass": row.get("pass", ""),
                "displayName": row.get("displayName", "")
            })
    
    with open(json_file, 'w') as f:
        json.dump({"mailboxes": mailboxes}, f, indent=2)
    
    print(f"✅ Imported {len(mailboxes)} mailboxes to {json_file}")
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
PYEOF

# Restart to reload
systemctl restart haraka
echo "🔄 Haraka restarted with new mailboxes"
SCRIPT
chmod +x /usr/local/bin/haraka-import

# Test rotation script
cat > /usr/local/bin/haraka-test << 'SCRIPT'
#!/bin/bash
# Test email rotation through the relay
# Usage: haraka-test recipient@example.com [count]

RECIPIENT="${1:-test@example.com}"
COUNT="${2:-3}"
RELAY_IP=$(curl -s ifconfig.me 2>/dev/null || echo "147.93.184.141")

echo "Testing Haraka rotation with $COUNT emails to $RECIPIENT..."
echo ""

for i in $(seq 1 $COUNT); do
    echo "Sending email $i/$COUNT..."
    swaks --to "$RECIPIENT" \
          --from "test@moescale.com" \
          --server "$RELAY_IP:587" \
          --auth-user "relay@moescale.com" \
          --auth-password "MoeScale123!" \
          --header "Subject: Test Rotation $i" \
          --body "This is test email $i" \
          --tls > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "  ✅ Email $i sent"
    else
        echo "  ❌ Email $i failed"
    fi
    
    sleep 2
done

echo ""
echo "Done! Check your inbox and /var/log/haraka.log"
SCRIPT
chmod +x /usr/local/bin/haraka-test

# Kill stale Haraka processes script
cat > /usr/local/bin/haraka-kill << 'SCRIPT'
#!/bin/bash
# Kill all stale Haraka processes

echo "Killing stale Haraka processes..."
fuser -k 587/tcp 2>/dev/null
fuser -k 8080/tcp 2>/dev/null
pkill -9 -f haraka 2>/dev/null
sleep 2
echo "✅ All Haraka processes killed"
echo "Run 'systemctl start haraka' to restart"
SCRIPT
chmod +x /usr/local/bin/haraka-kill

# Restart script
cat > /usr/local/bin/haraka-restart << 'SCRIPT'
#!/bin/bash
# Clean restart of Haraka

echo "🔄 Restarting Haraka..."
haraka-kill
systemctl restart haraka
sleep 3

if systemctl is-active haraka > /dev/null 2>&1; then
    echo "✅ Haraka restarted successfully"
    haraka-stats
else
    echo "❌ Failed to restart Haraka"
    echo "Check logs: tail -50 /var/log/haraka.log"
fi
SCRIPT
chmod +x /usr/local/bin/haraka-restart

log "Helper scripts created: haraka-stats, haraka-import, haraka-test, haraka-kill, haraka-restart"

# Final instructions
echo ""
echo "=========================================="
echo "✅ INSTALLATION COMPLETE!"
echo "=========================================="
echo ""
echo "📁 Configuration location: $CONFIG_DIR/"
echo "📝 Log file: /var/log/haraka.log"
echo ""
echo "⚠️  REQUIRED: Edit these files before starting:"
echo ""
echo "1. $CONFIG_DIR/config/auth_flat_file.ini"
echo "   → Add your relay authentication credentials"
echo ""
echo "2. $CONFIG_DIR/config/mailboxes.json"
echo "   → Add your 300 mailboxes (use 'haraka-import' for CSV)"
echo ""
echo "3. $CONFIG_DIR/config/tls/ (optional)"
echo "   → Add SSL certificates for TLS"
echo ""
echo "🚀 START THE SERVICE:"
echo "   systemctl start haraka"
echo ""
echo "📊 CHECK STATUS:"
echo "   haraka-stats"
echo ""
echo "🧪 TEST ROTATION:"
echo "   haraka-test recipient@yourdomain.com 5"
echo ""
echo "🌐 WEB INTERFACES:"
echo "   http://YOUR_IP:8080/watch/  (real-time)"
echo "   http://YOUR_IP:8080/graph   (historical)"
echo ""
echo "📚 Full documentation: https://github.com/mamghar001/Smtp-relay"
echo "=========================================="
