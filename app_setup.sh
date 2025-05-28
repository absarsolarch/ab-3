#!/bin/bash
# App Server Setup Script

# Install required packages
yum update -y
yum install -y httpd php php-pdo php-pgsql php-json php-redis php-curl

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Get configuration from SSM Parameter Store
DB_HOST=$(aws ssm get-parameter --name "/ab3/db/host" --with-decryption --query "Parameter.Value" --output text --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region))
DB_NAME=$(aws ssm get-parameter --name "/ab3/db/name" --with-decryption --query "Parameter.Value" --output text --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region))
DB_USER=$(aws ssm get-parameter --name "/ab3/db/user" --with-decryption --query "Parameter.Value" --output text --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region))
DB_PASSWORD=$(aws ssm get-parameter --name "/ab3/db/password" --with-decryption --query "Parameter.Value" --output text --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region))
REDIS_HOST=$(aws ssm get-parameter --name "/ab3/redis/endpoint" --query "Parameter.Value" --output text --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region))

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

// Use Redis for session management
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
echo "App server setup completed" > /var/log/user-data-success.log
