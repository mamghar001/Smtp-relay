// human_delay.js - Adds human-like delays between email sends
// Helps avoid triggering rate limits by introducing random delays

exports.hook_queue_outbound = function(next, connection) {
    const plugin = this;
    
    // Random delay between 30-120 seconds (adjust as needed)
    const minDelay = 30 * 1000;  // 30 seconds
    const maxDelay = 120 * 1000; // 120 seconds
    const delay = Math.floor(Math.random() * (maxDelay - minDelay + 1)) + minDelay;
    
    plugin.loginfo('HUMAN_DELAY: Delaying send by ' + delay + 'ms (' + (delay/1000) + ' seconds)');
    
    setTimeout(() => {
        plugin.loginfo('HUMAN_DELAY: Delay complete, proceeding with send');
        next();
    }, delay);
};

// Optional: Add delay after queue (between sends)
exports.hook_delivered = function(next, hmail, params) {
    const plugin = this;
    
    // Random delay between deliveries (10-60 seconds)
    const minDelay = 10 * 1000;
    const maxDelay = 60 * 1000;
    const delay = Math.floor(Math.random() * (maxDelay - minDelay + 1)) + minDelay;
    
    plugin.loginfo('HUMAN_DELAY: Post-delivery delay of ' + (delay/1000) + ' seconds');
    
    setTimeout(() => {
        next();
    }, delay);
};
