#!/bin/sh
printf "Please enter IP address for this server:"
read IP

printf "Please enter username for FTP:"
read FTP_USERNAME

printf "Please enter password for FTP:"
read FTP_PASSWORD

printf "Please enter your first name for Magento admin:"
read ADMIN_FIRSTNAME

printf "Please enter your last name for Magento admin:"
read ADMIN_LASTNAME

printf "Please enter your email for Magento admin:"
read ADMIN_EMAIL

printf "Please enter username for Magento admin:"
read ADMIN_USERNAME

printf "Please enter password for Magento admin:"
read ADMIN_PASSWORD

printf "Please enter password for MySQL root user:"
read MYSQL_PASSWORD

printf "Update packages\n"
sudo yum update -y

printf "Install NGINX, PHP 7.0 & MySql 5.6\n"
sudo yum install -y nginx php72 mysql56-server

printf "Install PHP extensions\n"
sudo yum install -y php72-mysqlnd php72-mcrypt php72-intl php72-mbstring php72-gzip php72-gd2 php72-zip php72-gd php72-xml php72-pdo php72-pecl-apcu php72-opcache php72-fpm php72-soap php72-bcmath
sudo yum install -y expect

printf "Install composer\n"
sudo curl -sS https://getcomposer.org/installer | sudo php
sudo mv composer.phar /usr/local/bin/composer

printf "Config nginx\n"
################### nginx configuration ###################
cat > ~/nginx.conf << EOL
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /var/run/nginx.pid;
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile    on;
    include     /etc/nginx/mime.types;
    include     /etc/nginx/conf.d/*.conf;
    index       index.php index.html index.htm;

    server {
        listen          80;
        server_name     localhost;
        set \$MAGE_ROOT  /var/www/html;
        include         /etc/nginx/default.d/*.conf;
    }

#   Settings for a TLS enabled server.
#    server {
#        listen                     443;
#        server_name                localhost;
#        set \$MAGE_ROOT            /var/www/html;
#        ssl_certificate            /etc/pki/nginx/server.crt;
#        ssl_certificate_key        /etc/pki/nginx/server.key;
#        ssl_session_cache          shared:SSL:1m;
#        ssl_session_timeout        10m;
#        ssl_protocols              TLSv1 TLSv1.1 TLSv1.2;
#        ssl_ciphers                'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:E$
#        ssl_dhparam                /etc/pki/nginx/dh.pem;
#        ssl_prefer_server_ciphers  on;
#        client_max_body_size       10m;
#        client_body_timeout        120s;
#        include /etc/nginx/default.d/*.conf;
#    }

}
EOL

cat > ~/magento.conf << EOL
root \$MAGE_ROOT/pub;
index index.php;
autoindex off;
charset UTF-8;
error_page 404 403 = /errors/404.php;

# PHP entry point for setup application
location ~* ^/setup(\$|/) {
    root \$MAGE_ROOT;
    location ~ ^/setup/index.php {
        fastcgi_pass   php-fpm;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
        include        fastcgi_params;
    }

    location ~ ^/setup/(?!pub/). {
        deny all;
    }

    location ~ ^/setup/pub/ {
        add_header X-Frame-Options "SAMEORIGIN";
    }
}

# PHP entry point for update application
location ~* ^/update(\$|/) {
    root \$MAGE_ROOT;

    location ~ ^/update/index.php {
        fastcgi_split_path_info ^(/update/index.php)(/.+)\$;
        fastcgi_pass   php-fpm;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
        fastcgi_param  PATH_INFO        \$fastcgi_path_info;
        include        fastcgi_params;
    }

    # Deny everything but index.php
    location ~ ^/update/(?!pub/). {
        deny all;
    }

    location ~ ^/update/pub/ {
        add_header X-Frame-Options "SAMEORIGIN";
    }
}

location / {
    try_files \$uri \$uri/ /index.php?\$args;
}

location /pub/ {
    location ~ ^/pub/media/(downloadable|customer|import|theme_customization/.*\.xml) {
        deny all;
    }
    alias \$MAGE_ROOT/pub/;
    add_header X-Frame-Options "SAMEORIGIN";
}

location /static/ {
    # Uncomment the following line in production mode
    # expires max;

    # Remove signature of the static files that is used to overcome the browser cache
    location ~ ^/static/version {
        rewrite ^/static/(version\d*/)?(.*)\$ /static/\$2 last;
    }

    location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2)\$ {
        add_header Cache-Control "public";
        add_header X-Frame-Options "SAMEORIGIN";
        expires +1y;

        if (!-f \$request_filename) {
            rewrite ^/static/(version\d*/)?(.*)\$ /static.php?resource=\$2 last;
        }
    }
    location ~* \.(zip|gz|gzip|bz2|csv|xml)\$ {
        add_header Cache-Control "no-store";
        add_header X-Frame-Options "SAMEORIGIN";
        expires    off;

        if (!-f \$request_filename) {
           rewrite ^/static/(version\d*/)?(.*)\$ /static.php?resource=\$2 last;
        }
    }
    if (!-f \$request_filename) {
        rewrite ^/static/(version\d*/)?(.*)\$ /static.php?resource=\$2 last;
    }
    add_header X-Frame-Options "SAMEORIGIN";
}

location /media/ {
    try_files \$uri \$uri/ /get.php?\$args;

    location ~ ^/media/theme_customization/.*\.xml {
        deny all;
    }

    location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2)\$ {
        add_header Cache-Control "public";
        add_header X-Frame-Options "SAMEORIGIN";
        expires +1y;
        try_files \$uri \$uri/ /get.php?\$args;
    }
    location ~* \.(zip|gz|gzip|bz2|csv|xml)\$ {
        add_header Cache-Control "no-store";
        add_header X-Frame-Options "SAMEORIGIN";
        expires    off;
        try_files \$uri \$uri/ /get.php?\$args;
    }
    add_header X-Frame-Options "SAMEORIGIN";
}

location /media/customer/ {
    deny all;
}

location /media/downloadable/ {
    deny all;
}

location /media/import/ {
    deny all;
}

# PHP entry point for main application
location ~ (index|get|static|report|404|503)\.php\$ {
    try_files \$uri =404;
    fastcgi_pass   php-fpm;
    fastcgi_buffers 1024 4k;

    fastcgi_read_timeout 600s;
    fastcgi_connect_timeout 600s;

    fastcgi_index  index.php;
    fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
    include        fastcgi_params;
}

gzip on;
gzip_disable "msie6";

gzip_comp_level 6;
gzip_min_length 1100;
gzip_buffers 16 8k;
gzip_proxied any;
gzip_types *;
gzip_vary on;

# Banned locations (only reached if the earlier PHP entry point regexes don't match)
location ~* (\.php\$|\.htaccess\$|\.git) {
    deny all;
}
EOL
################### end nginx configuration ###################
sudo rm -f /etc/nginx/nginx.conf
sudo cp -f ~/nginx.conf /etc/nginx/nginx.conf
sudo cp -f ~/magento.conf /etc/nginx/default.d/magento.conf

sudo sed -i "s/user = apache/user = nginx/g" /etc/php-fpm-7.0.d/www.conf
sudo sed -i "s/group = apache/group = nginx/g" /etc/php-fpm-7.0.d/www.conf

printf "Install vsftp\n"
sudo yum install -y vsftpd

printf "Config vsftp\n"
sudo sed -i "s/anonymous_enable=YES/anonymous_enable=NO/g" /etc/vsftpd/vsftpd.conf
sudo sed -i "s/#chroot_local_user=YES/chroot_local_user=YES/g" /etc/vsftpd/vsftpd.conf
echo -e "pasv_enable=YES" | sudo tee --append /etc/vsftpd/vsftpd.conf
echo -e "pasv_min_port=1024" | sudo tee --append /etc/vsftpd/vsftpd.conf
echo -e "pasv_max_port=1048" | sudo tee --append /etc/vsftpd/vsftpd.conf
echo -e "pasv_address=$IP" | sudo tee --append /etc/vsftpd/vsftpd.conf

printf "Start service \n"
sudo service nginx start
sudo service mysqld start
sudo service vsftpd start
sudo service php-fpm start

printf "Service auto start\n"
sudo chkconfig nginx on
sudo chkconfig mysqld on
sudo chkconfig vsftpd on
sudo chkconfig php-fpm on

printf "Setting mysql server\n"

SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root (enter for none):\"
send \"\r\"
expect \"Change the root password?\"
send \"y\r\"
expect \"New password:\"
send \"$MYSQL_PASSWORD\r\"
expect \"Re-enter new password:\"
send \"$MYSQL_PASSWORD\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")

echo "$SECURE_MYSQL"

printf "Create database for Magento\n"
mysql -u root -p$MYSQL_PASSWORD -e "CREATE DATABASE magento;"

printf "Set user group\n"
#sudo groupadd nginx
sudo usermod -a -G nginx ec2-user

printf "Adding FTP user...\n"
sudo useradd -g nginx -d /var/www/ -s /bin/bash -p $(echo $FTP_PASSWORD | openssl passwd -1 -stdin) $FTP_USERNAME

printf "Set user home directory\n"
sudo chown -R nginx:nginx /var/www

printf "Download Magento to home directory\n"
wget https://raw.githubusercontent.com/nothywu/magento-2-auto-deployment/master/Magento-CE-2.3.0-2018-11-27-10-18-29.tar.bz2

printf "Extract Magento to home directory\n"
sudo tar xjf Magento-CE-2.3.0-2018-11-27-10-18-29.tar.bz2 -C /var/www/html

printf "Set home directory permission\n"
sudo chmod -R 777 /var/www

printf "Install Magento\n"
cd /var/www/html
sudo php -f bin/magento setup:install --base-url=http://$IP/ --backend-frontname=admin --db-host=localhost --db-name=magento --db-user=root --db-password=$MYSQL_PASSWORD --admin-firstname=$ADMIN_FIRSTNAME --admin-lastname=$ADMIN_LASTNAME --admin-email=$ADMIN_EMAIL --admin-user=$ADMIN_USERNAME --admin-password=$ADMIN_PASSWORD --language=en_US --currency=AUD --timezone=Australia/Sydney --use-rewrites=1

printf "Set home directory permission\n"
sudo chmod -R 777 /var/www/html/
sudo chown -R nginx:nginx /var/lib/php/7.2/session/
sudo chmod -R 777 /var/lib/php/7.2/session/