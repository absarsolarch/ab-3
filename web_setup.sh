#!/bin/bash
# Web Server Setup Script

# Create health check file early for load balancer checks
echo "OK" > /var/www/html/health.html

# Install required packages (using dnf instead of yum for Amazon Linux 2023)
dnf update -y
dnf install -y httpd php php-pdo php-json php-curl php-devel php-pgsql gcc make

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

# Get Redis endpoint from SSM Parameter Store with retry logic
MAX_RETRIES=5
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  REDIS_HOST=$(aws ssm get-parameter --name "/ab3/redis/endpoint" --query "Parameter.Value" --output text --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) 2>/dev/null)
  if [ $? -eq 0 ] && [ "$REDIS_HOST" != "None" ] && [ ! -z "$REDIS_HOST" ]; then
    break
  fi
  echo "Waiting for Redis endpoint to be available... (Attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
  RETRY_COUNT=$((RETRY_COUNT+1))
  sleep 30
done

# Get App Tier endpoint with retry logic
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  APP_TIER_ENDPOINT=$(aws ssm get-parameter --name "/ab3/app/endpoint" --query "Parameter.Value" --output text --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) 2>/dev/null)
  if [ $? -eq 0 ] && [ "$APP_TIER_ENDPOINT" != "None" ] && [ ! -z "$APP_TIER_ENDPOINT" ]; then
    break
  fi
  echo "Waiting for App Tier endpoint to be available... (Attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
  RETRY_COUNT=$((RETRY_COUNT+1))
  sleep 30
done

# Create frontend config file for Redis and App Tier connection
cat > /var/www/html/frontend_config.php << EOF
<?php
// Configuration for three-tier architecture
\$app_tier_endpoint = "${APP_TIER_ENDPOINT}";
\$redis_host = "${REDIS_HOST}";
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

# Set proper permissions
chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

# Configure Apache to allow .htaccess files
sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf

# Restart Apache to apply changes
systemctl restart httpd

# Log completion
echo "Web server setup completed" > /var/log/user-data-success.log
