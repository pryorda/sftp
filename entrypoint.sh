#!/bin/bash
# Generate unique ssh keys for this container, if needed
if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
  ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ''
fi
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
  ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ''
fi

# Start syslog for user logging
exec /sbin/syslogd -n -O /dev/stdout &

# Configure users and keys
exec /configurator.sh "$@" &

# Start SSH Up.
exec /usr/sbin/sshd -D
