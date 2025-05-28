#!/bin/bash
# Web Server Setup Script

# Install required packages
yum update -y
yum install -y httpd php php-pdo php-json php-curl php-redis

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Get Redis endpoint from SSM Parameter Store
REDIS_HOST=$(aws ssm get-parameter --name "/ab3/redis/endpoint" --query "Parameter.Value" --output text --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region))
APP_TIER_ENDPOINT=$(aws ssm get-parameter --name "/ab3/app/endpoint" --query "Parameter.Value" --output text --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region))

# Create frontend config file for Redis and App Tier connection
cat > /var/www/html/frontend_config.php << EOF
<?php
// Configuration for three-tier architecture
\$app_tier_endpoint = "${APP_TIER_ENDPOINT}";
\$redis_host = "${REDIS_HOST}";
\$redis_port = 6379;
\$debug_mode = true;

// Initialize Redis for session management
ini_set('session.save_handler', 'redis');
ini_set('session.save_path', "tcp://\$redis_host:\$redis_port");
?>
EOF

# Set proper permissions
chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

# Configure Apache to allow .htaccess files
sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf

# Restart Apache to apply changes
systemctl restart httpd

# Create a health check file
echo "OK" > /var/www/html/health.html

# Log completion
echo "Web server setup completed" > /var/log/user-data-success.log
