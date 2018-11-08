FROM debian:stretch
LABEL MAINTAINER="Daniel Pryor [dpryor@pryorda.net]"
LABEL VERSION="v0.1.5"

# Steps done in one RUN layer:
# - Install packages
# - OpenSSH needs /var/run/sshd to run
# - Remove generic host keys, entrypoint generates unique keys
RUN apt-get update && \
    apt-get -y install --no-install-recommends openssh-server supervisor inotify-tools busybox-syslogd && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/run/sshd && \
    rm -f /etc/ssh/ssh_host_*key*

COPY sshd_config /etc/ssh/sshd_config
COPY configurator.sh /
COPY entrypoint.sh /
EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
