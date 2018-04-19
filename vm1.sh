#!/bin/bash
#
source `dirname $0`"/vm1.config"

HOSTNAME="vm1"
ssl_dir="/etc/ssl/certs/"

###     INTERFACES
# external
if [ "$EXT_IP" != "DHCP" ] ;
  then
        ip addr add $EXT_IP dev $EXTERNAL_IF
        ip ro add default via $EXT_GW dev $EXTERNAL_IF
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf
  else
        dhclient $EXTERNAL_IF
fi
EXT_IP=$(ifconfig $EXTERNAL_IF | grep 'inet addr' | cut -d: -f2 | awk '{print $1}')
# internal
ip addr add $INT_IP dev $INTERNAL_IF && ip link set $INTERNAL_IF up
# vlan over internal
modprobe 8021q
ip link add link $INTERNAL_IF name $INTERNAL_IF.$VLAN type vlan id $VLAN
ip addr add $VLAN_IP dev $INTERNAL_IF.$VLAN && ip link set $INTERNAL_IF.$VLAN up
#
###

hostname $HOSTNAME
echo $EXT_IP $HOSTNAME > /etc/hosts

###     NAT
echo 1 > /proc/sys/net/ipv4/ip_forward

iptables -F
iptables -F -t nat
iptables -t nat -A POSTROUTING -o $EXTERNAL_IF -j MASQUERADE
iptables -A FORWARD -i $INTERNAL_IF -j ACCEPT
service ufw restart
###


###     SSL
#CA
openssl genrsa -out /etc/ssl/private/root-ca.key 4096
openssl req -x509 -new -nodes -key /etc/ssl/private/root-ca.key -days 365 -out /etc/ssl/certs/root-ca.crt -subj "/C=UA/L=Kharkiv/O=HW/OU=task6_7/CN=root_cert"
#WEB
openssl genrsa -out /etc/ssl/private/web.key 4096
openssl req -new -key /etc/ssl/private/web.key -out /etc/ssl/certs/web.csr -subj "/C=UA/L=Kharkiv/O=HW/OU=task6_7/CN=$HOSTNAME" \
	-reqexts SAN -config <(cat /etc/ssl/openssl.cnf <(printf "\n[SAN]\nsubjectAltName=IP:$EXT_IP")) 

openssl x509 -req -days 365 -in /etc/ssl/certs/web.csr -CA /etc/ssl/certs/root-ca.crt -CAkey /etc/ssl/private/root-ca.key -CAcreateserial -out /etc/ssl/certs/web.crt \
	-extfile <(printf "subjectAltName=IP:$EXT_IP")

cat /etc/ssl/certs/root-ca.crt >> /etc/ssl/certs/web.crt
###

###     NGINX
if [ "$(dpkg -l nginx | grep ii |wc -l)" = "0" ] ; then
        apt update && apt install nginx -y
fi

rm -r /etc/nginx/sites-enabled/*
echo "  
upstream $HOSTNAME {
        server $EXT_IP:$NGINX_PORT;
}
server {
        listen $EXT_IP:$NGINX_PORT ssl;
        server_name $HOSTNAME;
        ssl on;
        ssl_certificate         /etc/ssl/certs/web.crt;
        ssl_certificate_key     /etc/ssl/private/web.key;

        location / {
                proxy_pass http://$APACHE_VLAN_IP;
		proxy_set_header Host \$host;
 		proxy_set_header X-Real-IP \$remote_addr;
 		proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
 		proxy_set_header X-Forwarded-Proto \$scheme;
        }
}" > /etc/nginx/sites-available/$HOSTNAME
ln -s /etc/nginx/sites-available/$HOSTNAME /etc/nginx/sites-enabled/$HOSTNAME
###

systemctl restart nginx

