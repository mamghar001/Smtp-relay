// rotate_senders.js - Haraka plugin for automatic mailbox rotation
// Each email sent gets a different FROM address from the pool

// ============================================
// CONFIGURE YOUR MAILBOXES HERE
// ============================================
// Add all your mailboxes that will be used for rotation
// Format: {host: 'smtp.server.com', user: 'email@domain.com', pass: 'password'}

const mailboxes = [
    // Example entries - replace with your actual mailboxes
    {host: 'mail.aioutboundagents.shop', user: 'abigail.harris@aioutboundagents.shop', pass: 'MoeScale123!'},
    {host: 'mail.affiliategrowth.shop', user: 'abigail.jones@affiliategrowth.shop', pass: 'MoeScale123!'},
    {host: 'mail.aioutboundagents.shop', user: 'abigail.moore@aioutboundagents.shop', pass: 'MoeScale123!'},
    {host: 'mail.affiliategrowth.shop', user: 'abigail.white@affiliategrowth.shop', pass: 'MoeScale123!'},
    {host: 'mail.b2bgrowth.shop', user: 'addison.harris@b2bgrowth.shop', pass: 'MoeScale123!'},
    {host: 'mail.b2bgrowth.shop', user: 'addison.jackson@b2bgrowth.shop', pass: 'MoeScale123!'},
    {host: 'mail.b2bgrowth.shop', user: 'addison.morris@b2bgrowth.shop', pass: 'MoeScale123!'},
    {host: 'mail.aioutboundagents.shop', user: 'addison.scott@aioutboundagents.shop', pass: 'MoeScale123!'},
    {host: 'mail.b2baioutbound.shop', user: 'amelia.brown@b2baioutbound.shop', pass: 'MoeScale123!'},
    {host: 'mail.aiemail.shop', user: 'amelia.evans@aiemail.shop', pass: 'MoeScale123!'},
    {host: 'mail.b2bgrowth.shop', user: 'amelia.evans@b2bgrowth.shop', pass: 'MoeScale123!'},
    {host: 'mail.affiliategrowth.shop', user: 'amelia.king@affiliategrowth.shop', pass: 'MoeScale123!'},
    {host: 'mail.aioutboundagents.shop', user: 'amelia.taylor@aioutboundagents.shop', pass: 'MoeScale123!'},
    {host: 'mail.aioutboundagents.shop', user: 'amelia.turner@aioutboundagents.shop', pass: 'MoeScale123!'},
    {host: 'mail.b2baioutbound.shop', user: 'amelia.walker@b2baioutbound.shop', pass: 'MoeScale123!'},
    {host: 'mail.b2bgrowth.shop', user: 'amelia.white@b2bgrowth.shop', pass: 'MoeScale123!'},
    {host: 'mail.aiemail.shop', user: 'amelia.williams@aiemail.shop', pass: 'MoeScale123!'},
    {host: 'mail.moescalesystem.shop', user: 'aria.bell@moescalesystem.shop', pass: 'MoeScale123!'},
    {host: 'mail.moescalesystem.shop', user: 'aria.harris@moescalesystem.shop', pass: 'MoeScale123!'},
    {host: 'mail.affiliategrowth.shop', user: 'aria.johnson@affiliategrowth.shop', pass: 'MoeScale123!'},
    {host: 'mail.affiliategrowth.shop', user: 'aria.mitchell@affiliategrowth.shop', pass: 'MoeScale123!'},
    {host: 'mail.b2baioutbound.shop', user: 'aria.mitchell@b2baioutbound.shop', pass: 'MoeScale123!'},
    {host: 'mail.b2bgrowth.shop', user: 'aria.thompson@b2bgrowth.shop', pass: 'MoeScale123!'},
    {host: 'mail.affiliategrowth.shop', user: 'aubrey.carter@affiliategrowth.shop', pass: 'MoeScale123!'},
    {host: 'mail.moescalesystem.shop', user: 'aubrey.mitchell@moescalesystem.shop', pass: 'MoeScale123!'},
    {host: 'mail.b2baioutbound.shop', user: 'aubrey.nelson@b2baioutbound.shop', pass: 'MoeScale123!'},
    {host: 'mail.b2baioutbound.shop', user: 'aubrey.robinson@b2baioutbound.shop', pass: 'MoeScale123!'},
    {host: 'mail.affiliategrowth.shop', user: 'aubrey.williams@affiliategrowth.shop', pass: 'MoeScale123!'},
    {host: 'mail.moescalesystem.shop', user: 'aubrey.williams@moescalesystem.shop', pass: 'MoeScale123!'},
    {host: 'mail.moescalesystem.shop', user: 'audrey.bailey@moescalesystem.shop', pass: 'MoeScale123!'},
    // Add more mailboxes as needed...
];

// Per-connection storage for selected mailbox
const connectionMailboxes = new Map();

exports.register = function() {
    this.loginfo('rotate_senders: registering hooks');
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
        const oldFrom = header.get('From');
        
        if (oldFrom) {
            // Parse old From to get display name if any
            let newFrom = selected.user;
            const match = oldFrom.match(/^([^<]+)/);
            if (match) {
                const displayName = match[1].trim();
                if (displayName && displayName !== oldFrom) {
                    newFrom = displayName + ' <' + selected.user + '>';
                }
            }
            
            header.remove('From');
            header.add('From', newFrom);
            plugin.loginfo('ROTATE DATA: Changed From header from "' + oldFrom + '" to "' + newFrom + '"');
        } else {
            header.add('From', selected.user);
            plugin.loginfo('ROTATE DATA: Added From header ' + selected.user);
        }
    } catch (err) {
        plugin.logerror('ROTATE DATA ERROR: ' + err.message);
    }
    
    next();
};

// Hook: Return MX for outbound delivery
exports.rotate_mx = function(next, hmail, domain) {
    const plugin = this;
    const connection = hmail.connection;
    
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
