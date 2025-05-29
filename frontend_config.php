<?php
// Configuration for three-tier architecture
// This file will be overwritten by the setup script with the actual values

// Set the app tier endpoint - this will be replaced by CloudFormation
$app_tier_endpoint = getenv('APP_TIER_ENDPOINT');

// If environment variable is not set, check for other sources
if (!$app_tier_endpoint || $app_tier_endpoint == "APP_TIER_ENDPOINT_PLACEHOLDER") {
    // Try to get from AWS SSM Parameter Store if we're in AWS
    if (function_exists('exec')) {
        try {
            exec('aws ssm get-parameter --name "/ab3/app/endpoint" --query "Parameter.Value" --output text 2>/dev/null', $output, $return_var);
            if ($return_var == 0 && !empty($output[0])) {
                $app_tier_endpoint = trim($output[0]);
                error_log("Retrieved app_tier_endpoint from SSM: " . $app_tier_endpoint);
            }
        } catch (Exception $e) {
            error_log("Error retrieving from SSM: " . $e->getMessage());
        }
    }
    
    // If still not set, use the public DNS of the app tier load balancer
    // This is a fallback for local development
    if (!$app_tier_endpoint || $app_tier_endpoint == "APP_TIER_ENDPOINT_PLACEHOLDER") {
        // Try to get the app tier endpoint from a local config file
        if (file_exists(__DIR__ . '/local_config.php')) {
            include_once __DIR__ . '/local_config.php';
            if (isset($local_app_tier_endpoint)) {
                $app_tier_endpoint = $local_app_tier_endpoint;
                error_log("Using app_tier_endpoint from local_config.php: " . $app_tier_endpoint);
            }
        }
        
        // If still not set, use localhost as a last resort
        if (!$app_tier_endpoint || $app_tier_endpoint == "APP_TIER_ENDPOINT_PLACEHOLDER") {
            $app_tier_endpoint = "http://localhost";
            error_log("Using localhost as app_tier_endpoint fallback");
        }
    }
}

// Set Redis host - this will be replaced by CloudFormation
$redis_host = getenv('REDIS_HOST');
if (!$redis_host || $redis_host == "REDIS_HOST_PLACEHOLDER") {
    // Try to get from AWS SSM Parameter Store if we're in AWS
    if (function_exists('exec')) {
        try {
            exec('aws ssm get-parameter --name "/ab3/redis/endpoint" --query "Parameter.Value" --output text 2>/dev/null', $output, $return_var);
            if ($return_var == 0 && !empty($output[0])) {
                $redis_host = trim($output[0]);
                error_log("Retrieved redis_host from SSM: " . $redis_host);
            }
        } catch (Exception $e) {
            error_log("Error retrieving from SSM: " . $e->getMessage());
        }
    }
    
    // If still not set, use localhost for development
    if (!$redis_host || $redis_host == "REDIS_HOST_PLACEHOLDER") {
        $redis_host = "localhost";
        error_log("Using localhost as redis_host fallback");
    }
}

$redis_port = 6379;
$debug_mode = true;

// Log the configuration
error_log("Configuration loaded - app_tier_endpoint: " . $app_tier_endpoint . ", redis_host: " . $redis_host);

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
