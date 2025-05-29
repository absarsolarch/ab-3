<?php
require_once "frontend_config.php";

// Function to get properties from app tier
function getProperties() {
    global $app_tier_endpoint, $debug_mode;
    $properties = [];
    
    try {
        if ($debug_mode) {
            error_log("Attempting to connect to app tier at: " . $app_tier_endpoint);
        }
        
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, rtrim($app_tier_endpoint, '/') . "/backend_api.php?api=properties");
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 5);
        $response = curl_exec($ch);
        $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        
        if (curl_errno($ch)) {
            if ($debug_mode) {
                error_log("cURL Error: " . curl_error($ch));
            }
        }
        
        curl_close($ch);
        
        if ($http_code == 200 && $response) {
            $properties = json_decode($response, true);
            if (!is_array($properties)) {
                if ($debug_mode) {
                    error_log("Invalid JSON response: " . substr($response, 0, 1000));
                }
                $properties = [];
            }
        } else {
            if ($debug_mode) {
                error_log("API request failed with HTTP code $http_code: " . substr($response, 0, 1000));
            }
        }
    } catch (Exception $e) {
        if ($debug_mode) {
            error_log("Error fetching properties: " . $e->getMessage());
        }
    }
    
    return $properties;
}

// Function to check app tier health
function checkAppTierHealth() {
    global $app_tier_endpoint, $debug_mode;
    
    try {
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, rtrim($app_tier_endpoint, '/') . "/backend_api.php?api=health");
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
        curl_setopt($ch, CURLOPT_TIMEOUT, 5);
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 3);
        $response = curl_exec($ch);
        $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        if ($http_code == 200 && $response) {
            $health = json_decode($response, true);
            return $health && isset($health['status']) && $health['status'] == 'healthy';
        }
    } catch (Exception $e) {
        if ($debug_mode) {
            error_log("Error checking app tier health: " . $e->getMessage());
        }
    }
    
    return false;
}

// Function to format price in MYR
function formatPrice($price) {
    return 'RM ' . number_format($price, 2);
}
?>
