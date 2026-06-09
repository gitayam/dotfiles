FROM alpine:3.21

RUN apk add --no-cache \
    bash \
    wireguard-tools \
    iptables \
    ip6tables \
    iproute2 \
    tcpdump \
    traceroute \
    curl \
    bind-tools

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD []
