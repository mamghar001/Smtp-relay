// rotate_senders.js - Haraka plugin for automatic mailbox rotation with display names
// Reads mailbox configuration from config/mailboxes.json

const fs = require('fs');
const path = require('path');

// Load mailboxes from config file
let mailboxes = [];

try {
    const configPath = path.join(process.cwd(), 'config', 'mailboxes.json');
    const configData = fs.readFileSync(configPath, 'utf8');
    const config = JSON.parse(configData);
    mailboxes = config.mailboxes || [];
    
    if (mailboxes.length === 0) {
        throw new Error('No mailboxes found in config/mailboxes.json');
    }
} catch (err) {
    // Fallback to empty array - plugin will log error
    console.error('ERROR: Could not load mailboxes.json:', err.message);
    mailboxes = [];
}

// Per-connection storage for selected mailbox
const connectionMailboxes = new Map();

exports.register = function() {
    const plugin = this;
    
    if (mailboxes.length === 0) {
        plugin.logerror('rotate_senders: NO MAILBOXES LOADED - check config/mailboxes.json');
    } else {
        plugin.loginfo('rotate_senders: Loaded ' + mailboxes.length + ' mailboxes from config/mailboxes.json');
    }
    
    // Hook into MAIL FROM command - runs BEFORE auth/flat_file's constrain_sender
    this.register_hook('mail', 'rotate_envelope_sender');
    // Hook into data to modify headers
    this.register_hook('data_post', 'rotate_from_header');
    // Hook into outbound MX selection
    this.register_hook('get_mx', 'rotate_mx');
    // Cleanup on disconnect
    this.register_hook('disconnect', 'cleanup');
};

// Hook: Modify envelope sender when MAIL FROM is received
exports.rotate_envelope_sender = function(next, connection, params) {
    const plugin = this;
    
    if (mailboxes.length === 0) {
        plugin.logerror('rotate_senders: Cannot rotate - no mailboxes loaded');
        return next();
    }
    
    try {
        // Select random mailbox
        const randomIndex = Math.floor(Math.random() * mailboxes.length);
        const selected = mailboxes[randomIndex];
        
        // Store for this connection
        connectionMailboxes.set(connection.uuid, selected);
        
        plugin.loginfo('ROTATE MAIL: Selected ' + selected.user + ' for connection ' + connection.uuid);
        
        // Modify the envelope sender in the transaction
        if (connection.transaction) {
            const Address = require('address-rfc2821').Address;
            const oldFrom = connection.transaction.mail_from ? connection.transaction.mail_from.toString() : 'none';
            
            // Create new Address object with rotated mailbox
            connection.transaction.mail_from = new Address('<' + selected.user + '>');
            
            plugin.loginfo('ROTATE MAIL: Changed envelope from ' + oldFrom + ' to ' + selected.user);
        }
    } catch (err) {
        plugin.logerror('ROTATE MAIL ERROR: ' + err.message);
    }
    
    next();
};

// Hook: Modify From header in email body
exports.rotate_from_header = function(next, connection) {
    const plugin = this;
    const selected = connectionMailboxes.get(connection.uuid);
    
    if (!selected || !connection.transaction) {
        return next();
    }
    
    try {
        const header = connection.transaction.header;
        
        // Build From header with display name: "Display Name" <email@domain.com>
        let newFrom;
        if (selected.displayName) {
            newFrom = '"' + selected.displayName + '" <' + selected.user + '>';
        } else {
            newFrom = selected.user;
        }
        
        // Remove any existing From header (scratch Mautic's FROM completely)
        header.remove('From');
        
        // Add our rotated From header
        header.add('From', newFrom);
        
        plugin.loginfo('ROTATE DATA: Set From header to "' + newFrom + '"');
        
    } catch (err) {
        plugin.logerror('ROTATE DATA ERROR: ' + err.message);
    }
    
    next();
};

// Hook: Return MX for outbound delivery
exports.rotate_mx = function(next, hmail, domain) {
    const plugin = this;
    const connection = hmail.connection;
    
    if (mailboxes.length === 0) {
        return next(DENY, 'No mailboxes configured');
    }
    
    // Try to get the mailbox selected for this connection
    let selected = null;
    if (connection && connection.uuid) {
        selected = connectionMailboxes.get(connection.uuid);
    }
    
    // Fallback: pick random
    if (!selected) {
        const randomIndex = Math.floor(Math.random() * mailboxes.length);
        selected = mailboxes[randomIndex];
        plugin.loginfo('ROTATE MX: Random fallback selected ' + selected.user);
    }
    
    plugin.loginfo('ROTATE MX: Using ' + selected.user + ' via ' + selected.host);
    
    next(OK, {
        priority: 0,
        exchange: selected.host,
        port: 587,
        auth_user: selected.user,
        auth_pass: selected.pass
    });
};

// Cleanup on disconnect
exports.cleanup = function(next, connection) {
    connectionMailboxes.delete(connection.uuid);
    next();
};
