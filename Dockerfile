FROM ubuntu:18.04
LABEL MAINTAINER="Daniel Pryor [pryorda.net]"

# Steps done in one RUN layer:
# - Build rsyslog
# - Install packages
# - OpenSSH needs /var/run/sshd to run
# - Remove generic host keys, entrypoint generates unique keys
RUN apt-get update && \
    apt-get -y install openssh-server supervisor inotify-tools busybox-syslogd && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/run/sshd && \
    rm -f /etc/ssh/ssh_host_*key*

COPY sshd_config /etc/ssh/sshd_config
COPY configurator.sh /
COPY entrypoint.sh /
EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]

