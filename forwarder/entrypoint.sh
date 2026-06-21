#!/bin/sh
set -eu

UDP_PORTS="${UDP_PORTS:-14159}"
TCP_PORTS="${TCP_PORTS:-}"
HOME_WG_IP="${HOME_WG_IP:-10.13.13.2}"
VPS_WG_IP="${VPS_WG_IP:-10.13.13.1}"
WG_INTERFACE="${WG_INTERFACE:-wg0}"

ipt() {
  iptables -w "$@"
}

add_rule() {
  if ! ipt -C "$@" 2>/dev/null; then
    ipt -A "$@"
  fi
}

add_nat_rule() {
  if ! ipt -t nat -C "$@" 2>/dev/null; then
    ipt -t nat -A "$@"
  fi
}

del_rule() {
  ipt -D "$@" 2>/dev/null || true
}

del_nat_rule() {
  ipt -t nat -D "$@" 2>/dev/null || true
}

cleanup() {
  for proto in udp tcp; do
    ports="$(ports_for "$proto")"
    for port in $ports; do
      delete_forward "$proto" "$port"
    done
  done
}

trap cleanup INT TERM EXIT

ports_for() {
  case "$1" in
    udp) echo "$UDP_PORTS" | tr ',' ' ' ;;
    tcp) echo "$TCP_PORTS" | tr ',' ' ' ;;
    *) return 1 ;;
  esac
}

add_forward() {
  proto="$1"
  port="$2"

  add_nat_rule PREROUTING -p "$proto" --dport "$port" -j DNAT --to-destination "$HOME_WG_IP:$port"
  add_nat_rule POSTROUTING -p "$proto" -d "$HOME_WG_IP" --dport "$port" -j SNAT --to-source "$VPS_WG_IP"
  add_rule FORWARD -p "$proto" -d "$HOME_WG_IP" --dport "$port" -j ACCEPT
  add_rule FORWARD -p "$proto" -s "$HOME_WG_IP" --sport "$port" -j ACCEPT
}

delete_forward() {
  proto="$1"
  port="$2"

  del_nat_rule PREROUTING -p "$proto" --dport "$port" -j DNAT --to-destination "$HOME_WG_IP:$port"
  del_nat_rule POSTROUTING -p "$proto" -d "$HOME_WG_IP" --dport "$port" -j SNAT --to-source "$VPS_WG_IP"
  del_rule FORWARD -p "$proto" -d "$HOME_WG_IP" --dport "$port" -j ACCEPT
  del_rule FORWARD -p "$proto" -s "$HOME_WG_IP" --sport "$port" -j ACCEPT
}

for _ in $(seq 1 60); do
  if ip link show "$WG_INTERFACE" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! ip link show "$WG_INTERFACE" >/dev/null 2>&1; then
  echo "WireGuard interface $WG_INTERFACE was not found" >&2
  exit 1
fi

sysctl -w net.ipv4.ip_forward=1 >/dev/null

for proto in udp tcp; do
  ports="$(ports_for "$proto")"
  for port in $ports; do
    add_forward "$proto" "$port"
    echo "Forwarding $proto/$port on this VPS to $HOME_WG_IP:$port over $WG_INTERFACE"
  done
done

tail -f /dev/null &
wait $!
