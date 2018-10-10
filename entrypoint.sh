#!/bin/bash

# Start syslog
/sbin/syslogd -n -O /dev/stdout &

# Configure users and keys
/configurator.sh "$@" & 

while [ ! -f "/etc/ssh/ssh_host_ed25519_key" ] && [ ! -f "/etc/ssh/ssh_host_rsa_key" ] 
do
  echo "Waiting for keys to be created" ; sleep 2
done

# Start SSH Up.
exec /usr/local/sbin/sshd -D
