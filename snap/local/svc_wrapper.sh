#!/bin/bash

# `snapctl get services` returns a JSON array, example:
#{
#"n6801": {
#   "listen": 6801,
#   "vnc": "localhost:5901"
#},
#"n6802": {
#   "listen": 6802,
#   "vnc": "localhost:5902"
#},
#"n8443": {
#   "listen": 8443,
#   "vnc": "ubuntu.example.com:5903",
#   "cert": "~jsmith/snap/novnc/current/self.crt",
#   "key": "~jsmith/snap/novnc/current/self.key"
#},
#}
snapctl get services | jq -c '.[]' | while read service; do # for each service the user sepcified..
    # get the important data for the service (listen port, VNC host:port)
    listen_port="$(echo $service | jq --raw-output '.listen')"
    vnc_host_port="$(echo $service | jq --raw-output '.vnc')" # --raw-output removes any quotation marks from the output
    # get SSL cert and key path
	ssl_cert="$(echo $service | jq --raw-output '.cert')"
    ssl_key="$(echo $service | jq --raw-output '.key')"
    
    # check whether those values are valid
    expr "$listen_port" : '^[0-9]\+$' > /dev/null
    listen_port_valid=$?
    if [ ! $listen_port_valid ] || [ -z "$vnc_host_port" ] || [ "$vnc_host_port" == "null" ]; then
        # invalid values mean the service is disabled, do nothing except for printing a message (logged in /var/log/system or systemd journal)
        echo "novnc: not starting service ${service} with listen_port ${listen_port} and vnc_host_port ${vnc_host_port}"
    else
    	if [ -z "$ssl_cert" ] || [ -z "$ssl_key" ] || [ "$ssl_cert" == "null" ] || [ "$ssl_key" == "null" ]; then 
        	# start (and fork with '&') the service using the specified listen port and VNC host:port
        	$SNAP/novnc_proxy --listen $listen_port --vnc $vnc_host_port &
        else	
        	ssl_cert=$(eval echo "$ssl_cert")
        	ssl_key=$(eval echo "$ssl_key")
			if [ -s "$ssl_cert" ] && [ -s "$ssl_key" ]; then
				md5_cert="$(openssl x509 -noout -modulus -in $ssl_cert | openssl md5)"
				md5_key="$(openssl rsa -noout -modulus -in $ssl_key | openssl md5)"
				
				# check if cert and key match
				if [ "$md5_cert" == "$md5_key" ]; then
					$SNAP/novnc_proxy --listen $listen_port --vnc $vnc_host_port --cert $ssl_cert --key $ssl_key &
				else
					echo "novnc: invalid files ${ssl_cert} and ${ssl_key}. MD5 files not match."
					$SNAP/novnc_proxy --listen $listen_port --vnc $vnc_host_port &
				fi
			else
				[ ! -s "$ssl_cert" ] && echo "novnc: file ${ssl_cert} not exists or is empty"
				[ ! -s "$ssl_key" ] && echo "novnc: file ${ssl_key} not exists or is empty"	
				$SNAP/novnc_proxy --listen $listen_port --vnc $vnc_host_port &
			fi        	
        fi
    fi
done
