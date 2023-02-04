#Tested with CentOS Stream 8 and 9
#Install CentOS using minimal ISO
#Use mirror
#mirror.centos.org/centos/8-stream/BaseOS/x86_64/os/
#Minimal installation with headless management

echo "This script will prompt you for some things. Press Enter to continue."

read -e -p "Enter domain name of this Wordpress site:  " domain_name

read -e -p "Name the Wordpress database:  " db_name

read -e -p "Provide a username for the Wordpress database:  " db_user

read -e -p "Provide a password for the database user:  " db_pass
# install necessary software
dnf install epel-release -y
dnf upgrade -y
dnf module enable php:7.4 -y
dnf install snapd policycoreutils-python-utils tar httpd mod_ssl mariadb-server mariadb make php php-common php-devel php-pear php-fpm php-gd php-json php-mbstring php-mysqlnd php-pdo php-xml php-pecl-zip GraphicsMagick GraphicsMagick-devel GraphicsMagick-perl -y

# enable imagick php extension
echo "extension=imagick.so" > /etc/php.d/20-imagick.ini

# enable services
systemctl enable --now httpd mariadb snapd

#setup snap and install certbot
ln -s /var/lib/snapd/snap /snap
snap install core
snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot

# add virtual host to apache

echo "
LoadModule ssl_module modules/mod_ssl.so
<VirtualHost *:80>
    DocumentRoot "/var/www/html"
    ServerName $domain_name
</VirtualHost>
" >> /etc/httpd/conf/httpd.conf

# configure PHP

sed -i '/memory_limit/s/= .*/= 256M/' /etc/php.ini
sed -i '/max_execution_time/s/= .*/= 600/' /etc/php.ini
sed -i '/post_max_size/s/= .*/= 120M/' /etc/php.ini
sed -i '/upload_max_filesize/s/= .*/= 100M/' /etc/php.ini
echo extension=imagick.so >> /etc/php.ini

# create database and creds
mysql -u root -e "CREATE DATABASE ${db_name}; GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost' IDENTIFIED BY '$db_pass';"

# download latest Wordpress and extract to docroot

curl -L https://wordpress.org/latest.tar.gz --output ~/wordpress.tar.gz
tar -xzf ~/wordpress.tar.gz -C /var/www/html/
mv /var/www/html/wordpress/* /var/www/html/
rm -rf /var/www/html/wordpress

# create wp-config
cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
sed -i "s/database_name_here/$db_name/g" /var/www/html/wp-config.php
sed -i "s/username_here/$db_user/g" /var/www/html/wp-config.php
sed -i "s/password_here/$db_pass/g" /var/www/html/wp-config.php

chown -R apache /var/www/html
chgrp -R apache /var/www/html
chmod -R 750 /var/www/html

# selinux on docroot
setsebool -P httpd_can_network_connect 1
setsebool -P httpd_can_sendmail 1
setsebool -P httpd_execmem on
semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html(/.*)?"
restorecon -Rv /var/www/html

# enable ports
firewall-cmd -q --add-port 80/tcp --add-port 443/tcp --zone=public --permanent
firewall-cmd -q --reload

# setup ssl with certbot
certbot --agree-tos --apache --register-unsafely-without-email --domains "$domain_name"

echo "If there were no errors, you may now set up your Wordpress site at https://$domain_name."
echo "If you experience errors, please notify routetehpacketz via GitHub."
