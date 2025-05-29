<?php
// Configuration for three-tier architecture
// This file will be overwritten by the setup script with the actual values

// Set the app tier endpoint - this will be replaced by CloudFormation
$app_tier_endpoint = getenv('APP_TIER_ENDPOINT');
if (!$app_tier_endpoint) {
    // If environment variable is not set, check if we're in a CloudFormation deployment
    if (file_exists('/var/www/html/frontend_config.php')) {
        // We're in a CloudFormation deployment, but the environment variable isn't set yet
        // This is a temporary fallback that should be replaced by the setup script
        $app_tier_endpoint = "APP_TIER_ENDPOINT_PLACEHOLDER";
    } else {
        // Local development fallback
        $app_tier_endpoint = "http://localhost";
    }
}

// Set Redis host - this will be replaced by CloudFormation
$redis_host = getenv('REDIS_HOST');
if (!$redis_host) {
    $redis_host = "REDIS_HOST_PLACEHOLDER";
}

$redis_port = 6379;
$debug_mode = true;

// Check if Redis extension is loaded
if (!extension_loaded('redis')) {
    error_log('Redis extension is not loaded. Please check your PHP configuration.');
    // Continue without Redis for session management
} else {
    // Initialize Redis for session management
    ini_set('session.save_handler', 'redis');
    ini_set('session.save_path', "tcp://$redis_host:$redis_port");
}
?>
