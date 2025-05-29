#!/bin/bash
# App Server Setup Script

# Create health check file early for load balancer checks
echo "OK" > /var/www/html/health.html

# Install required packages (using dnf instead of yum for Amazon Linux 2023)
dnf update -y
dnf install -y httpd php php-pdo php-pgsql php-json php-curl php-devel gcc make

# Install PHP PEAR/PECL
dnf install -y php-pear

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

# Get configuration from SSM Parameter Store with retry logic
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

# Try to get DB host parameter
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Attempting to retrieve DB host (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
  DB_HOST=$(aws ssm get-parameter --name "/ab3/db/host" --query "Parameter.Value" --output text --region $REGION 2>/dev/null)
  
  # If that fails, try the alternative parameter name
  if [ $? -ne 0 ] || [ "$DB_HOST" == "None" ] || [ -z "$DB_HOST" ]; then
    echo "Trying alternative parameter name..."
    DB_HOST=$(aws ssm get-parameter --name "/ab3/db/endpoint" --query "Parameter.Value" --output text --region $REGION 2>/dev/null)
  fi
  
  if [ $? -eq 0 ] && [ "$DB_HOST" != "None" ] && [ ! -z "$DB_HOST" ]; then
    echo "Successfully retrieved DB host: $DB_HOST"
    break
  fi
  echo "Waiting for DB host to be available... (Attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
  RETRY_COUNT=$((RETRY_COUNT+1))
  sleep 30
done

# Try to get other parameters
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Attempting to retrieve DB parameters (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
  DB_NAME=$(aws ssm get-parameter --name "/ab3/db/name" --query "Parameter.Value" --output text --region $REGION 2>/dev/null)
  DB_USER=$(aws ssm get-parameter --name "/ab3/db/user" --query "Parameter.Value" --output text --region $REGION 2>/dev/null)
  DB_PASSWORD=$(aws ssm get-parameter --name "/ab3/db/password" --query "Parameter.Value" --output text --region $REGION 2>/dev/null)
  REDIS_HOST=$(aws ssm get-parameter --name "/ab3/redis/endpoint" --query "Parameter.Value" --output text --region $REGION 2>/dev/null)
  
  if [ "$DB_NAME" != "None" ] && [ ! -z "$DB_NAME" ] && \
     [ "$DB_USER" != "None" ] && [ ! -z "$DB_USER" ] && \
     [ "$DB_PASSWORD" != "None" ] && [ ! -z "$DB_PASSWORD" ] && \
     [ "$REDIS_HOST" != "None" ] && [ ! -z "$REDIS_HOST" ]; then
    echo "Successfully retrieved all parameters"
    echo "DB_NAME: $DB_NAME"
    echo "DB_USER: $DB_USER"
    echo "REDIS_HOST: $REDIS_HOST"
    break
  fi
  echo "Waiting for DB and Redis parameters to be available... (Attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
  RETRY_COUNT=$((RETRY_COUNT+1))
  sleep 30
done

# Check if we got all the parameters
if [ -z "$DB_HOST" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ] || [ -z "$REDIS_HOST" ]; then
  echo "ERROR: Failed to retrieve all required parameters from SSM" > /var/log/user-data-error.log
  echo "Using test mode configuration instead"
  
  # Create backend config file with test mode settings
  cat > /var/www/html/backend_config.php << EOF
<?php
// Database connection parameters - TEST MODE
\$host = "TEST_MODE";
\$dbname = "myappdb";
\$user = "app_user";
\$password = "password";
\$redis_host = "localhost";
\$redis_port = 6379;

// Debug mode - set to true to see detailed errors
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
  # Create backend config file with real parameters
  cat > /var/www/html/backend_config.php << EOF
<?php
// Database connection parameters
\$host = "${DB_HOST}";
\$dbname = "${DB_NAME}";
\$user = "${DB_USER}";
\$password = "${DB_PASSWORD}";
\$redis_host = "${REDIS_HOST}";
\$redis_port = 6379;

// Debug mode - set to true to see detailed errors
\$debug_mode = true;

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

# Create a test file to verify the app server is working
cat > /var/www/html/app_test.php << EOF
<?php
// Include required files
require_once "backend_config.php";

// Output configuration for debugging
echo "<h1>App Server Configuration</h1>";
echo "<pre>";
echo "Host: " . \$host . "\n";
echo "Database: " . \$dbname . "\n";
echo "User: " . \$user . "\n";
echo "Redis Host: " . \$redis_host . "\n";
echo "Redis Port: " . \$redis_port . "\n";
echo "Redis Extension Loaded: " . (extension_loaded('redis') ? 'Yes' : 'No') . "\n";
echo "PHP Version: " . phpversion() . "\n";
echo "Server Time: " . date('Y-m-d H:i:s') . "\n";
echo "</pre>";

// Test database connection
echo "<h2>Database Connection Test</h2>";
try {
    if (\$host === "TEST_MODE") {
        echo "<p>Running in test mode with Redis as storage backend</p>";
        if (extension_loaded('redis')) {
            \$redis = new Redis();
            \$connected = @\$redis->connect(\$redis_host, \$redis_port, 2);
            if (\$connected) {
                echo "<p style='color:green'>Successfully connected to Redis</p>";
            } else {
                echo "<p style='color:red'>Failed to connect to Redis</p>";
            }
        } else {
            echo "<p style='color:red'>Redis extension not loaded</p>";
        }
    } else {
        \$pdo = new PDO("pgsql:host=\$host;dbname=\$dbname", \$user, \$password);
        \$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        echo "<p style='color:green'>Successfully connected to PostgreSQL database</p>";
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
echo "App server setup completed" > /var/log/user-data-success.log
