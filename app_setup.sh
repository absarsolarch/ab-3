#!/bin/bash
# App Server Setup Script

# Create health check file early for load balancer checks
echo "OK" > /var/www/html/health.html

# Install required packages (using dnf instead of yum for Amazon Linux 2023)
dnf update -y
dnf install -y httpd php php-pdo php-pgsql php-json php-curl php-devel gcc make

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

# Get configuration from SSM Parameter Store with retry logic
MAX_RETRIES=5
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  DB_HOST=$(aws ssm get-parameter --name "/ab3/db/host" --with-decryption --query "Parameter.Value" --output text --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) 2>/dev/null)
  if [ $? -eq 0 ] && [ "$DB_HOST" != "None" ] && [ ! -z "$DB_HOST" ]; then
    break
  fi
  echo "Waiting for DB host to be available... (Attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
  RETRY_COUNT=$((RETRY_COUNT+1))
  sleep 30
done

RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  DB_NAME=$(aws ssm get-parameter --name "/ab3/db/name" --with-decryption --query "Parameter.Value" --output text --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) 2>/dev/null)
  DB_USER=$(aws ssm get-parameter --name "/ab3/db/user" --with-decryption --query "Parameter.Value" --output text --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) 2>/dev/null)
  DB_PASSWORD=$(aws ssm get-parameter --name "/ab3/db/password" --with-decryption --query "Parameter.Value" --output text --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) 2>/dev/null)
  REDIS_HOST=$(aws ssm get-parameter --name "/ab3/redis/endpoint" --query "Parameter.Value" --output text --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) 2>/dev/null)
  
  if [ "$DB_NAME" != "None" ] && [ ! -z "$DB_NAME" ] && \
     [ "$DB_USER" != "None" ] && [ ! -z "$DB_USER" ] && \
     [ "$DB_PASSWORD" != "None" ] && [ ! -z "$DB_PASSWORD" ] && \
     [ "$REDIS_HOST" != "None" ] && [ ! -z "$REDIS_HOST" ]; then
    break
  fi
  echo "Waiting for DB and Redis parameters to be available... (Attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
  RETRY_COUNT=$((RETRY_COUNT+1))
  sleep 30
done

# Create backend config file
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

# Set proper permissions
chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

# Configure Apache to allow .htaccess files
sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf

# Restart Apache to apply changes
systemctl restart httpd

# Log completion
echo "App server setup completed" > /var/log/user-data-success.log
