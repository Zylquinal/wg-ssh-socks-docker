FROM alpine:3.18

RUN apk --no-cache add \
    wireguard-tools \
    iptables \
    openssh-client \
    redsocks \
    sshpass \
    ca-certificates \
    autossh

COPY wg0.conf.template /etc/wireguard/wg0.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV WG_PORT=51820 \
    WG_INTERFACE_IP=10.8.0.1/24 \
    WG_SERVER_PRIVATE_KEY="" \
    WG_PEER_PUBLIC_KEY="" \
    WG_PEER_ALLOWED_IPS="10.8.0.2/32" \
    SSH_REMOTE_HOST="" \
    SSH_REMOTE_PORT="22" \
    SSH_REMOTE_USER="" \
    SSH_AUTH_METHOD="password" \
    SSH_PASSWORD="" \
    SSH_PRIVATE_KEY="" \
    SSH_SOCKS_IP="0.0.0.0" \
    SSH_SOCKS_PORT="1080" \
    REDSOCKS_PORT="12345"

# Expose the WireGuard UDP port.
EXPOSE 51820/udp

ENTRYPOINT ["/entrypoint.sh"]
