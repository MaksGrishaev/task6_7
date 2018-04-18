#!/bin/bash

source `dirname $0`"/vm2.config"
HOSTNAME="vm2"

ip addr add $INT_IP dev $INTERNAL_IF && ip link set $INTERNAL_IF up
ip ro add default via $GW_IP dev $INTERNAL_IF
INT_IP=$(ifconfig $INTERNAL_IF | grep 'inet addr' | cut -d: -f2 | awk '{print $1}')

echo "nameserver 8.8.8.8" >> /etc/resolv.conf

ip link add link $INTERNAL_IF name $INTERNAL_IF.$VLAN type vlan id $VLAN
ip addr add $APACHE_VLAN_IP dev $INTERNAL_IF.$VLAN && ip link set $INTERNAL_IF.$VLAN up
APACHE_VLAN_IP=$(ifconfig $INTERNAL_IF.$VLAN | grep 'inet addr' | cut -d: -f2 | awk '{print $1}')

hostname $HOSTNAME
echo $INT_IP $HOSTNAME > /etc/hosts

if [ "$(dpkg -l apache2 | grep ii |wc -l)" = "0" ] ; then
        apt update && apt install apache2 -y
fi

rm -r /etc/apache2/sites-enabled/*

echo "
<VirtualHost *:80>
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/html
        ErrorLog \${APACHE_LOG_DIR}/error.log
        CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>" >> /etc/apache2/sites-available/$HOSTNAME.conf

ln -s /etc/apache2/sites-available/$HOSTNAME.conf /etc/apache2/sites-enabled/$HOSTNAME.conf

echo "Listen $APACHE_VLAN_IP:80" > /etc/apache2/ports.conf
sed -i "/# Global configuration/a \ServerName $HOSTNAME" /etc/apache2/apache2.conf

systemctl restart apache2

