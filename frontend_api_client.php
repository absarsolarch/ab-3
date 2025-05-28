<?php
require_once "frontend_config.php";

// Function to get properties from app tier
function getProperties() {
    global $app_tier_endpoint;
    $properties = [];
    
    try {
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $app_tier_endpoint . "/backend_api.php?api=properties");
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        $response = curl_exec($ch);
        $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        if ($http_code == 200 && $response) {
            $properties = json_decode($response, true);
            if (!is_array($properties)) {
                $properties = [];
            }
        }
    } catch (Exception $e) {
        error_log("Error fetching properties: " . $e->getMessage());
    }
    
    return $properties;
}

// Function to format price in MYR
function formatPrice($price) {
    return 'RM ' . number_format($price, 2);
}
?>
