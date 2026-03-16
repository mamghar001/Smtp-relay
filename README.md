# Haraka SMTP Relay with Mailbox Rotation

A high-performance SMTP relay built on [Haraka](https://haraka.github.io/) that automatically rotates through multiple mailboxes for cold email campaigns.

## Features

- ✅ **Automatic Mailbox Rotation** - Each email sent from a different mailbox
- ✅ **TLS Encryption** - Secure SMTP connections
- ✅ **Authentication** - PLAIN and CRAM-MD5 auth methods
- ✅ **High Performance** - Node.js-based, handles thousands of connections
- ✅ **Easy Configuration** - Simple JavaScript plugin system
- ✅ **Backend MX Rotation** - Distributes load across multiple SMTP servers

## Architecture

```
Sender (Mautic/etc) 
    ↓
Haraka Relay (147.93.184.141:587)
    ↓ (rotates FROM address)
BillionMail Backend (300+ mailboxes)
    ↓
Destination Inbox
```

## Installation

### 1. Install Node.js

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
```

### 2. Install Haraka

```bash
cd /opt
git clone https://github.com/haraka/Haraka.git haraka-src
cd haraka-src
npm install
npm link
```

### 3. Create Haraka Configuration

```bash
mkdir -p /etc/haraka
cd /etc/haraka
haraka -i /etc/haraka
```

### 4. Copy Plugin Files

```bash
# Copy rotate_senders.js to plugins directory
cp rotate_senders.js /etc/haraka/plugins/

# Copy config files
cp plugins /etc/haraka/config/
cp auth_flat_file.ini /etc/haraka/config/
```

### 5. Configure Plugins

Edit `/etc/haraka/config/plugins`:

```
# Core plugins
helo.checks
tls
rotate_senders
auth/flat_file

# Optional: Add delay between sends
# human_delay

# Logging
process_title
```

### 6. Configure Authentication

Edit `/etc/haraka/config/auth_flat_file.ini`:

```ini
[core]
methods = PLAIN,CRAM-MD5
constrain_sender = false

[users]
# Add your relay authentication credentials
relay@yourdomain.com = YourStrongPassword123!
```

### 7. Configure Mailbox Pool

Edit `/etc/haraka/plugins/rotate_senders.js` and add your mailboxes:

```javascript
const mailboxes = [
    {host: 'mail.domain1.com', user: 'sender1@domain1.com', pass: 'password1'},
    {host: 'mail.domain2.com', user: 'sender2@domain2.com', pass: 'password2'},
    // Add all your mailboxes here
];
```

### 8. Configure TLS (Optional but Recommended)

```bash
# Place your SSL certificates
mkdir -p /etc/haraka/config/tls

# Copy certificates
cp your-cert.pem /etc/haraka/config/tls/yourdomain.com.pem
cp your-key.pem /etc/haraka/config/tls/yourdomain.com.key
```

### 9. Start Haraka

```bash
# Development mode (foreground)
haraka -c /etc/haraka

# Production mode (background)
nohup haraka -c /etc/haraka > /var/log/haraka.log 2>&1 &
```

### 10. Create Systemd Service (Optional)

Create `/etc/systemd/system/haraka.service`:

```ini
[Unit]
Description=Haraka SMTP Relay
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/haraka
ExecStart=/usr/bin/haraka -c /etc/haraka
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
systemctl daemon-reload
systemctl enable haraka
systemctl start haraka
```

## Configuration

### Plugin Configuration

The `rotate_senders.js` plugin handles:

1. **Envelope Sender Rotation** - Changes the MAIL FROM address
2. **Header Rotation** - Modifies the From: header in email body
3. **MX Rotation** - Selects different backend SMTP servers

### Mailbox Format

```javascript
{
    host: 'mail.example.com',        // Backend SMTP server
    user: 'sender@example.com',      // Full email address
    pass: 'password123'              // Mailbox password
}
```

### Testing

```bash
# Test with swaks
swaks --to recipient@example.com \
      --from "sender@yourdomain.com" \
      --server your-relay-ip:587 \
      --auth-user relay@yourdomain.com \
      --auth-password YourStrongPassword123! \
      --header "Subject: Test" \
      --body "Test message" \
      --tls
```

## Usage with Mautic

1. **Go to Configuration > Email Settings**
2. **Set Mailer to "Other SMTP Server"**
3. **Configure:**
   - SMTP Host: `your-relay-ip`
   - SMTP Port: `587`
   - SMTP Encryption: `TLS`
   - SMTP Authentication: `Yes`
   - Username: `relay@yourdomain.com`
   - Password: `YourStrongPassword123!`
4. **From Address:** Set your default sending address

## Monitoring

### Web Dashboard (NEW!)

Haraka now includes built-in web monitoring:

| Plugin | URL | Description |
|--------|-----|-------------|
| **Watch** | `http://YOUR_IP:8080/watch/` | Real-time SMTP traffic with live connections |
| **Graph** | `http://YOUR_IP:8080/graph` | Historical email statistics over time |

#### Setup

```bash
# Install required dependencies
cd /etc/haraka
npm install express sqlite3 haraka-plugin-graph haraka-plugin-watch

# Edit config/plugins - add these lines:
graph
watch

# Start/restart Haraka
haraka -c /etc/haraka
```

**Note:** The graph plugin needs email traffic to populate data. The watch plugin shows live connections immediately.

### Check Logs

```bash
# Real-time logs
tail -f /var/log/haraka.log

# Check rotation
grep "ROTATE" /var/log/haraka.log

# Check deliveries
grep "delivered" /var/log/haraka.log
```

### Verify Rotation

Send multiple test emails and check the From headers:

```bash
for i in {1..5}; do
  swaks --to test@example.com \
        --from "default@domain.com" \
        --server relay-ip:587 \
        --auth-user relay@domain.com \
        --auth-password pass \
        --tls
done
```

Each email should have a different From address.

## Troubleshooting

### Port Already in Use

```bash
# Find and kill process
fuser -k 587/tcp
```

### Multiple Haraka Instances

```bash
# Kill all instances
pkill -9 -f haraka
```

### Permission Denied

```bash
# Fix permissions
chmod 644 /etc/haraka/config/*
chmod 755 /etc/haraka/plugins/*.js
```

## Security Considerations

1. **Firewall:** Restrict port 587 to trusted IPs only
2. **Authentication:** Use strong passwords
3. **TLS:** Always enable TLS for production
4. **Rate Limiting:** Configure human_delay plugin for throttling
5. **Logs:** Rotate logs regularly to prevent disk fill

## Advanced Configuration

### Human Delay Plugin

Add random delays between sends (30-120 seconds):

```javascript
// plugins/human_delay.js
exports.hook_queue_outbound = function(next, connection) {
    const delay = Math.floor(Math.random() * 90000) + 30000; // 30-120s
    this.loginfo(`Delaying ${delay}ms`);
    setTimeout(() => next(), delay);
};
```

### Custom Mailbox Selection

Modify `rotate_senders.js` to use round-robin instead of random:

```javascript
let currentIndex = 0;

function getNextMailbox() {
    const mailbox = mailboxes[currentIndex];
    currentIndex = (currentIndex + 1) % mailboxes.length;
    return mailbox;
}
```

## License

MIT

## Credits

Built with [Haraka](https://haraka.github.io/) - A fast, extensible Node.js email server.
