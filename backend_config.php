<?php
// Database connection parameters
// This file will be overwritten by the setup script with the actual values
$host = "DB_HOST_PLACEHOLDER";
$dbname = "DB_NAME_PLACEHOLDER";
$user = "DB_USER_PLACEHOLDER";
$password = "DB_PASSWORD_PLACEHOLDER";
$redis_host = "REDIS_HOST_PLACEHOLDER";
$redis_port = 6379;

// Debug mode - set to true to see detailed errors
$debug_mode = true;

// Check if Redis extension is loaded
if (!extension_loaded('redis')) {
    error_log('Redis extension is not loaded. Please check your PHP configuration.');
    // Continue without Redis for session management
} else {
    // Use Redis for session management
    ini_set('session.save_handler', 'redis');
    ini_set('session.save_path', "tcp://$redis_host:$redis_port");
}
?>
