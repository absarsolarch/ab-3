<?php
// Configuration for three-tier architecture
// This file will be overwritten by the setup script with the actual values
$app_tier_endpoint = "APP_TIER_ENDPOINT_PLACEHOLDER";
$redis_host = "REDIS_HOST_PLACEHOLDER";
$redis_port = 6379;
$debug_mode = true;

// Initialize Redis for session management
ini_set('session.save_handler', 'redis');
ini_set('session.save_path', "tcp://$redis_host:$redis_port");
?>
