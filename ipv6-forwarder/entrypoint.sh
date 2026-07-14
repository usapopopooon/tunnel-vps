#!/bin/sh
set -eu

TARGET_IPV4="${TARGET_IPV4:?Set TARGET_IPV4}"
TCP_PORTS="${TCP_PORTS:-}"
UDP_PORTS="${UDP_PORTS:-}"

ports() {
  echo "$1" | tr ',' ' '
}

pids=""

for port in $(ports "$TCP_PORTS"); do
  echo "Proxying IPv6 TCP/$port to $TARGET_IPV4:$port"
  socat "TCP6-LISTEN:$port,ipv6only=1,reuseaddr,fork" "TCP4:$TARGET_IPV4:$port" &
  pids="$pids $!"
done

for port in $(ports "$UDP_PORTS"); do
  echo "Proxying IPv6 UDP/$port to $TARGET_IPV4:$port"
  socat "UDP6-RECVFROM:$port,ipv6only=1,reuseaddr,fork" "UDP4-SENDTO:$TARGET_IPV4:$port" &
  pids="$pids $!"
done

if [ -z "$pids" ]; then
  echo "No TCP_PORTS or UDP_PORTS configured" >&2
  exit 1
fi

trap 'kill $pids 2>/dev/null || true; wait $pids 2>/dev/null || true' INT TERM EXIT

for pid in $pids; do
  wait "$pid"
done
