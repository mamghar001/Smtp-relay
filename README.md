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

### Quick Install (One Command)

```bash
# Clone the repo
git clone https://github.com/mamghar001/Smtp-relay.git
cd Smtp-relay

# Run installer
sudo ./install.sh
```

The installer will:
- ✅ Install Node.js 22
- ✅ Install Haraka from GitHub
- ✅ Set up all configuration files
- ✅ Install web monitoring plugins (graph + watch)
- ✅ Create helper scripts (haraka-stats, haraka-import, etc.)
- ✅ Set up systemd service

### Post-Install Configuration

**1. Add relay authentication:**
```bash
nano /etc/haraka/config/auth_flat_file.ini
```
```ini
[core]
methods = PLAIN,CRAM-MD5
constrain_sender = false

[users]
relay@yourdomain.com = YourStrongPassword123!
```

**2. Add your mailboxes (two options):**

*Option A: Edit JSON directly*
```bash
nano /etc/haraka/config/mailboxes.json
```

*Option B: Import from CSV*
```bash
# Create CSV file (see mailboxes.csv for format)
haraka-import mailboxes.csv
```

**3. Start the service:**
```bash
systemctl start haraka
```

**4. Check status:**
```bash
haraka-stats
```
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
