FROM debian:stretch
LABEL MAINTAINER="Daniel Pryor [pryorda.net]"

# Steps done in one RUN layer:
# - Install packages (openssh-portable-hpn)
# - OpenSSH needs /var/run/sshd to run
# - Remove generic host keys, entrypoint generates unique keys
RUN apt-get update && \
    apt-get -y install supervisor inotify-tools busybox-syslogd libssl1.0-dev zlib1g-dev autoconf build-essential git && \
    git clone https://github.com/rapier1/openssh-portable && \
    cd openssh-portable && git checkout tags/hpn-7_8_P1 && \
    mkdir -p /var/empty && \
    chown root:sys /var/empty && \
    chmod 755 /var/empty && \
    groupadd sshd && \
    useradd -g sshd -c 'sshd privsep' -d /var/empty -s /bin/false sshd && \
    autoreconf -fi && ./configure --with-privsep-user=sshd --with-privsep-path=/var/empty --sysconfdir=/etc/ssh && \
    make && make install && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/run/sshd && \
    rm -f /etc/ssh/ssh_host_*key*

COPY sshd_config /etc/ssh/sshd_config
COPY configurator.sh /
COPY entrypoint.sh /
EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]

