#!/bin/bash
# install.sh - Quick installer for Haraka SMTP Relay
# Usage: sudo ./install.sh

set -e

echo "=========================================="
echo "Haraka SMTP Relay Installer"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Error: Please run as root (sudo)"
    exit 1
fi

# Install Node.js
echo "[1/6] Installing Node.js..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
else
    echo "Node.js already installed: $(node --version)"
fi

# Install Haraka
echo ""
echo "[2/6] Installing Haraka..."
if [ ! -d "/opt/haraka-src" ]; then
    cd /opt
    git clone https://github.com/haraka/Haraka.git haraka-src
    cd haraka-src
    npm install
    npm link
else
    echo "Haraka already installed"
fi

# Create configuration directory
echo ""
echo "[3/6] Setting up configuration..."
mkdir -p /etc/haraka/config
mkdir -p /etc/haraka/plugins

# Copy plugin files
echo ""
echo "[4/6] Installing plugins..."
cp rotate_senders.js /etc/haraka/plugins/
cp plugins/human_delay.js /etc/haraka/plugins/ 2>/dev/null || true

# Copy config files
echo ""
echo "[5/6] Installing configuration..."
cp config/plugins /etc/haraka/config/
cp config/auth_flat_file.ini /etc/haraka/config/
cp config/smtp.ini /etc/haraka/config/ 2>/dev/null || true

# Create systemd service
echo ""
echo "[6/6] Creating systemd service..."
cp haraka.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable haraka

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Edit /etc/haraka/config/auth_flat_file.ini"
echo "   - Add your relay authentication credentials"
echo ""
echo "2. Edit /etc/haraka/plugins/rotate_senders.js"
echo "   - Add your mailbox pool (300+ mailboxes)"
echo ""
echo "3. Start the service:"
echo "   systemctl start haraka"
echo ""
echo "4. Check status:"
echo "   systemctl status haraka"
echo ""
echo "5. Test rotation:"
echo "   ./test_rotation.sh"
echo ""
