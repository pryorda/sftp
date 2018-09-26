#!/bin/bash

# Start syslog
/sbin/syslogd -n -O /dev/stdout &

# Configure users and keys
/configurator.sh "$@" &

# Start SSH Up.
exec /usr/sbin/sshd -D
