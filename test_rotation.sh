#!/bin/bash
# test_rotation.sh - Test mailbox rotation functionality
# Usage: ./test_rotation.sh [relay-ip] [auth-user] [auth-pass] [recipient]

RELAY_IP="${1:-147.93.184.141}"
AUTH_USER="${2:-relay@yourdomain.com}"
AUTH_PASS="${3:-password}"
RECIPIENT="${4:-test@example.com}"
NUM_TESTS=10

echo "=========================================="
echo "Testing Mailbox Rotation"
echo "=========================================="
echo "Relay: $RELAY_IP:587"
echo "Auth: $AUTH_USER"
echo "Recipient: $RECIPIENT"
echo "Tests: $NUM_TESTS emails"
echo "=========================================="
echo ""

# Check if swaks is installed
if ! command -v swaks &> /dev/null; then
    echo "Error: swaks is required but not installed."
    echo "Install with: apt-get install swaks"
    exit 1
fi

# Send test emails
for i in $(seq 1 $NUM_TESTS); do
    echo -n "Sending email $i/$NUM_TESTS... "
    
    RESULT=$(swaks \
        --to "$RECIPIENT" \
        --from "sender@example.com" \
        --server "$RELAY_IP:587" \
        --auth-user "$AUTH_USER" \
        --auth-password "$AUTH_PASS" \
        --header "Subject: Rotation Test $i" \
        --body "This is test email $i" \
        --tls \
        2>&1 | grep -E "Queued|Ok|Error")
    
    if echo "$RESULT" | grep -q "Queued\|Ok"; then
        echo "✓ Sent"
    else
        echo "✗ Failed: $RESULT"
    fi
    
    # Small delay between sends
    sleep 1
done

echo ""
echo "=========================================="
echo "Test complete!"
echo "=========================================="
echo ""
echo "Check your recipient inbox for emails."
echo "Each email should have a different From: address."
echo ""
echo "To verify rotation, check email headers:"
echo "  grep '^From:' /var/mail/user"
