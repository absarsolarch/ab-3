#!/bin/bash
# Web Server Setup Script

# Create health check file early for load balancer checks
echo "OK" > /var/www/html/health.html

# Install required packages (using dnf instead of yum for Amazon Linux 2023)
dnf update -y
dnf install -y httpd php php-pdo php-json php-curl php-devel php-pgsql gcc make

# Install PHP PEAR/PECL if not already installed
if ! command -v pecl &> /dev/null; then
    dnf install -y php-pear
fi

# Install Redis PHP extension using PECL with auto-accept
printf "\n" | pecl install redis
echo "extension=redis.so" > /etc/php.d/20-redis.ini

# Create shared session directory with proper permissions
mkdir -p /var/lib/php/sessions
chown apache:apache /var/lib/php/sessions
chmod 770 /var/lib/php/sessions

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Install AWS CLI if not already installed
if ! command -v aws &> /dev/null; then
    dnf install -y unzip
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
fi

# Get Redis endpoint from SSM Parameter Store with retry logic
MAX_RETRIES=10
RETRY_COUNT=0

# Get region from instance metadata or fallback to IMDSv2
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

# If region is still empty, try the old IMDSv1 method
if [ -z "$REGION" ]; then
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
fi

# If region is still empty, try to get it from the instance identity document
if [ -z "$REGION" ]; then
    REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | awk -F\" '{print $4}')
fi

# If we still don't have a region, default to us-east-1
if [ -z "$REGION" ]; then
    echo "Warning: Could not determine region from instance metadata, defaulting to us-east-1"
    REGION="us-east-1"
fi

echo "Retrieving parameters from SSM in region: $REGION"

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Attempting to retrieve Redis endpoint (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
  REDIS_HOST=$(aws ssm get-parameter --name "/ab3/redis/endpoint" --query "Parameter.Value" --output text --region $REGION 2>/dev/null)
  if [ $? -eq 0 ] && [ "$REDIS_HOST" != "None" ] && [ ! -z "$REDIS_HOST" ]; then
    echo "Successfully retrieved Redis endpoint: $REDIS_HOST"
    break
  fi
  echo "Waiting for Redis endpoint to be available... (Attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
  RETRY_COUNT=$((RETRY_COUNT+1))
  sleep 30
done

# Get App Tier endpoint with retry logic
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Attempting to retrieve App Tier endpoint (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
  APP_TIER_ENDPOINT=$(aws ssm get-parameter --name "/ab3/app/endpoint" --query "Parameter.Value" --output text --region $REGION 2>/dev/null)
  if [ $? -eq 0 ] && [ "$APP_TIER_ENDPOINT" != "None" ] && [ ! -z "$APP_TIER_ENDPOINT" ]; then
    echo "Successfully retrieved App Tier endpoint: $APP_TIER_ENDPOINT"
    # Remove trailing slash if present
    APP_TIER_ENDPOINT=${APP_TIER_ENDPOINT%/}
    break
  fi
  echo "Waiting for App Tier endpoint to be available... (Attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
  RETRY_COUNT=$((RETRY_COUNT+1))
  sleep 30
done

# Check if we got all the parameters
if [ -z "$REDIS_HOST" ] || [ -z "$APP_TIER_ENDPOINT" ]; then
  echo "ERROR: Failed to retrieve all required parameters from SSM" > /var/log/user-data-error.log
  echo "Using test mode configuration instead"
  
  # Get instance metadata for fallback configuration
  INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
  AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
  
  # Create frontend config file with test mode settings
  cat > /var/www/html/frontend_config.php << EOF
<?php
// Configuration for three-tier architecture - TEST MODE
\$app_tier_endpoint = "http://localhost";
\$redis_host = "localhost";
\$redis_port = 6379;
\$debug_mode = true;

// Check if Redis extension is loaded
if (!extension_loaded('redis')) {
    error_log('Redis extension is not loaded. Falling back to file-based sessions.');
    // Fall back to file-based sessions
    ini_set('session.save_handler', 'files');
    ini_set('session.save_path', '/var/lib/php/sessions');
} else {
    try {
        // Initialize Redis for session management
        ini_set('session.save_handler', 'files');
        ini_set('session.save_path', '/var/lib/php/sessions');
        error_log('Using file-based sessions in test mode');
    } catch (Exception \$e) {
        error_log('Session setup error: ' . \$e->getMessage() . '. Using file-based sessions.');
        ini_set('session.save_handler', 'files');
        ini_set('session.save_path', '/var/lib/php/sessions');
    }
}
?>
EOF
else
  # Create frontend config file for Redis and App Tier connection
  cat > /var/www/html/frontend_config.php << EOF
<?php
// Configuration for three-tier architecture
\$app_tier_endpoint = "${APP_TIER_ENDPOINT}";
\$redis_host = "${REDIS_HOST}";
\$redis_port = 6379;
\$debug_mode = true;

// Log the configuration
error_log("Configuration loaded - app_tier_endpoint: " . \$app_tier_endpoint . ", redis_host: " . \$redis_host);

// Check if Redis extension is loaded
if (!extension_loaded('redis')) {
    error_log('Redis extension is not loaded. Falling back to file-based sessions.');
    // Fall back to file-based sessions
    ini_set('session.save_handler', 'files');
    ini_set('session.save_path', '/var/lib/php/sessions');
} else {
    try {
        // Test Redis connection before using it
        \$redis_test = new Redis();
        \$connected = @\$redis_test->connect(\$redis_host, \$redis_port, 2); // 2 second timeout
        if (\$connected) {
            // Initialize Redis for session management
            ini_set('session.save_handler', 'redis');
            ini_set('session.save_path', "tcp://\$redis_host:\$redis_port");
            error_log('Successfully connected to Redis for session management');
        } else {
            error_log('Failed to connect to Redis. Falling back to file-based sessions.');
            ini_set('session.save_handler', 'files');
            ini_set('session.save_path', '/var/lib/php/sessions');
        }
    } catch (Exception \$e) {
        error_log('Redis connection error: ' . \$e->getMessage() . '. Falling back to file-based sessions.');
        ini_set('session.save_handler', 'files');
        ini_set('session.save_path', '/var/lib/php/sessions');
    }
}
?>
EOF
fi

# Create a test file to verify the web server is working
cat > /var/www/html/web_test.php << EOF
<?php
// Include required files
require_once "frontend_config.php";

// Output configuration for debugging
echo "<h1>Web Server Configuration</h1>";
echo "<pre>";
echo "App Tier Endpoint: " . \$app_tier_endpoint . "\n";
echo "Redis Host: " . \$redis_host . "\n";
echo "Redis Port: " . \$redis_port . "\n";
echo "Redis Extension Loaded: " . (extension_loaded('redis') ? 'Yes' : 'No') . "\n";
echo "PHP Version: " . phpversion() . "\n";
echo "Server Time: " . date('Y-m-d H:i:s') . "\n";
echo "</pre>";

// Test Redis connection
echo "<h2>Redis Connection Test</h2>";
if (extension_loaded('redis')) {
    try {
        \$redis = new Redis();
        \$connected = @\$redis->connect(\$redis_host, \$redis_port, 2);
        if (\$connected) {
            echo "<p style='color:green'>Successfully connected to Redis</p>";
        } else {
            echo "<p style='color:red'>Failed to connect to Redis</p>";
        }
    } catch (Exception \$e) {
        echo "<p style='color:red'>Error: " . \$e->getMessage() . "</p>";
    }
} else {
    echo "<p style='color:red'>Redis extension not loaded</p>";
}

// Test App Tier connection
echo "<h2>App Tier Connection Test</h2>";
try {
    \$ch = curl_init(\$app_tier_endpoint . "/backend_api.php?test=1");
    curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt(\$ch, CURLOPT_TIMEOUT, 5);
    \$result = curl_exec(\$ch);
    \$http_code = curl_getinfo(\$ch, CURLINFO_HTTP_CODE);
    curl_close(\$ch);
    
    if (\$http_code == 200) {
        echo "<p style='color:green'>Successfully connected to App Tier</p>";
        echo "<pre>" . htmlspecialchars(\$result) . "</pre>";
    } else {
        echo "<p style='color:red'>Failed to connect to App Tier (HTTP code: \$http_code)</p>";
    }
} catch (Exception \$e) {
    echo "<p style='color:red'>Error: " . \$e->getMessage() . "</p>";
}
?>
EOF

# Set proper permissions
chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

# Configure Apache to allow .htaccess files
sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf

# Restart Apache to apply changes
systemctl restart httpd

# Log completion
echo "Web server setup completed" > /var/log/user-data-success.log
