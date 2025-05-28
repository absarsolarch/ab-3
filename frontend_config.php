<?php
// Configuration for three-tier architecture
// This file will be overwritten by the setup script with the actual values
$app_tier_endpoint = "APP_TIER_ENDPOINT_PLACEHOLDER";
$redis_host = "REDIS_HOST_PLACEHOLDER";
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
