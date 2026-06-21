# VPS Port Relay

This project publishes home-hosted TCP and UDP services through a small VPS.
Clients connect to the VPS IPv4 address, while the actual services keep running
at home.

```text
clients -> VPS TCP/UDP <port> -> WireGuard -> home server TCP/UDP <port>
```

The VPS runs WireGuard plus a kernel-level port forwarder. The home server only
opens an outbound WireGuard connection, so no home IPv4 port forwarding is
required.

## Files

| File | Where to use it | Purpose |
| --- | --- | --- |
| `docker-compose.vps.yml` | VPS | WireGuard server and TCP/UDP relay |
| `docker-compose.home.yml` | Home server | WireGuard client |
| `.env.example` | Both | Shared defaults |

## VPS Setup

Recommended VPS OS:

1. Rocky Linux 9
2. Arch Linux
3. CentOS Stream

Rocky Linux 9 is the best default for this relay: stable server OS, current
enough kernel for WireGuard, and straightforward Docker support. Use Arch only
if Rocky is not available. Avoid older CentOS releases.

### Rocky Linux 9 Base Setup

Run these once on a fresh VPS:

```sh
sudo dnf -y update
sudo dnf -y install dnf-plugins-core git
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo modprobe wireguard || true
```

If `firewalld` is enabled:

```sh
sudo firewall-cmd --add-port=51820/udp --permanent
sudo firewall-cmd --add-port=14159/udp --permanent
# sudo firewall-cmd --add-port=8080/tcp --permanent
sudo firewall-cmd --reload
```

Also open WireGuard's UDP port and every relayed TCP/UDP port in the ConoHa
control panel if a security group/firewall is attached.

### Arch Linux Base Setup

Run these once on a fresh VPS:

```sh
sudo pacman -Syu --noconfirm
sudo pacman -S --noconfirm docker docker-compose git iptables-nft
sudo systemctl enable --now docker
sudo modprobe wireguard || true
```

1. Copy this directory to the VPS.
2. Create `.env`.

```sh
cp .env.example .env
```

3. Edit `.env`.

```text
VPS_PUBLIC_HOST=<ConoHa VPS public IPv4 or domain>
UDP_PORTS=14159
TCP_PORTS=
WG_PORT=51820
```

`UDP_PORTS` and `TCP_PORTS` accept a comma-separated or space-separated list.
For example:

```text
UDP_PORTS=14159,27015
TCP_PORTS=22,8080
```

4. Open `WG_PORT` as UDP and each relayed port with its matching protocol in the
   VPS firewall and provider security settings.

5. Start the VPS side.

```sh
docker compose -f docker-compose.vps.yml up -d --build
```

6. Copy the generated home peer config from the VPS.

```sh
cat data/wireguard/peer_home/peer_home.conf
```

## Home Setup

1. Copy this directory to the home server too, or just copy
   `docker-compose.home.yml` and `.env.example`.
2. Create the WireGuard client config directory.

```sh
mkdir -p data/home-wireguard/wg_confs
```

3. Save the VPS-generated peer config as:

```text
data/home-wireguard/wg_confs/wg0.conf
```

4. Start the home WireGuard client.

```sh
docker compose -f docker-compose.home.yml up -d
```

The existing services should keep publishing the same TCP/UDP ports on the home
host. Docker's normal port mapping binds the host port, so traffic arriving on
the WireGuard interface can reach it.

## DNS

Point your service domain to the VPS public IPv4 with an A record. Clients can
then connect to:

```text
example.your-domain.test:14159
```

## Checks

On the VPS:

```sh
docker compose -f docker-compose.vps.yml ps
docker logs tunnel-vps-wireguard
docker logs tunnel-vps-port-forwarder
```

On the home server:

```sh
docker compose -f docker-compose.home.yml ps
docker logs tunnel-home-wireguard
```

If clients cannot connect, confirm that the VPS firewall allows the configured
TCP/UDP ports and that the home services are running on those same ports.
