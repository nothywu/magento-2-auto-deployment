#!/bin/sh
printf "Please enter IP address for this server:"
read IP

printf "Update packages\n"
sudo yum update -y

printf "Install NGINX, PHP 7.0 & MySql 5.6\n"
sudo yum install -y nginx php70 mysql56-server

printf "Install PHP extensions\n"
sudo yum install -y php70-mysqlnd php70-mcrypt php70-intl php70-mbstring php70-gzip php70-gd2 php70-zip php70-gd php70-xml php70-pdo php70-pecl-apcu php70-opcache php70-fpm

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

# Settings for a TLS enabled server.
#
#    server {
#        listen              443;
#        server_name         localhost;
#        set \$MAGE_ROOT      /var/www/html;
#        ssl_certificate     "/etc/pki/nginx/server.crt";
#        ssl_certificate_key "/etc/pki/nginx/private/server.key";
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
gzip_types
    text/plain
    text/css
    text/js
    text/xml
    text/javascript
    application/javascript
    application/x-javascript
    application/json
    application/xml
    application/xml+rss
    image/svg+xml;
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
sudo chkconfig php-fpm start

printf "Setting mysql server\n"
mysql_secure_installation <<EOF

y
oZakNGmcxHjto97x
oZakNGmcxHjto97x
y
n
n
y
EOF

printf "Create database for Magento\n"
mysql -u root -poZakNGmcxHjto97x -e "CREATE DATABASE magento;"

printf "Set user group\n"
sudo groupadd www
sudo usermod -a -G www ec2-user

printf "Adding FTP user...\n"
sudo adduser -G www magento
sudo passwd magento <<EOF
abcd2017
abcd2017
EOF

printf "Set user home directory\n"
sudo usermod -d /var/www/ magento
sudo chown -R root:www /var/www

printf "Download Magento to home directory\n"
wget http://www.wuzaixiang.com/dist/Magento-CE-2.1.8.tar.bz2

printf "Extract Magento to home directory\n"
sudo tar xjf Magento-CE-2.1.8.tar.bz2 -C /var/www/html

printf "Set home directory permission\n"
sudo chmod -R 777 /var/www

printf "Install Magento\n"
cd /var/www/html
sudo php -f bin/magento setup:install --base-url=http://$IP/ --backend-frontname=admin --db-host=localhost --db-name=magento --db-user=root --db-password=oZakNGmcxHjto97x --admin-firstname=Magento --admin-lastname=User --admin-email=admin@domain.com --admin-user=admin --admin-password=abcd2017 --language=en_US --currency=AUD --timezone=Australia/Sydney --use-rewrites=1

printf "Set home directory permission\n"
sudo chmod -R 777 /var/www/html/
