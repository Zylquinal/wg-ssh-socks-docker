# WireGuard - SOCKS - SSH Docker

This Docker image runs:
1. A **WireGuard VPN server**
2. An **outbound SSH client** that creates a **SOCKS5 proxy** via remote SSH

## Requirements
- Docker Engine (or compatible runtime) supporting `--cap-add=NET_ADMIN` (required by WireGuard).
- A remote SSH server you can authenticate to (for the SOCKS proxy).

---

## Environment Variables

| Variable                | Default       | Description                                                                                                 |
|-------------------------|---------------|-------------------------------------------------------------------------------------------------------------|
| **WireGuard**           |               |                                                                                                             |
| `WG_PORT`               | `51820`       | UDP port for WireGuard to listen on.                                                                        |
| `WG_INTERFACE_IP`       | `10.8.0.1/24` | IP address/subnet for the server’s WireGuard interface.                                                     |
| `WG_SERVER_PRIVATE_KEY` | *(empty)*     | If empty, a new private key is generated at runtime. If set, uses the provided key.                         |
| `WG_PEER_PUBLIC_KEY`    | *(empty)*     | Optional. If set, a `[Peer]` block is appended to `wg0.conf`.                                               |
| `WG_PEER_ALLOWED_IPS`   | `10.8.0.2/32` | Used in the `[Peer]` block if `WG_PEER_PUBLIC_KEY` is set.                                                  |
| **SSH SOCKS**           |               |                                                                                                             |
| `SSH_REMOTE_HOST`       | *(empty)*     | **Required**. Hostname or IP of the remote SSH server for the SOCKS proxy.                                  |
| `SSH_REMOTE_PORT`       | `22`          | SSH server port.                                                                                            |
| `SSH_REMOTE_USER`       | *(empty)*     | **Required**. Username for SSH login.                                                                       |
| `SSH_AUTH_METHOD`       | `password`    | `password` or `privatekey` – how to authenticate to the SSH server.                                         |
| `SSH_PASSWORD`          | *(empty)*     | Used if `SSH_AUTH_METHOD=password`.                                                                         |
| `SSH_PRIVATE_KEY`       | *(empty)*     | Used if `SSH_AUTH_METHOD=privatekey`. Provide the full private key text (PEM).                              |
| `SSH_SOCKS_IP`          | `0.0.0.0`     | IP on which the SOCKS proxy will listen. If you only want it available to VPN clients, consider `10.8.0.1`. |
| `SSH_SOCKS_PORT`        | `1080`        | TCP port for the SOCKS proxy.                                                                               |

---

## Building

```bash
git clone https://github.com/zylquinal/wg-ssh-socks.git
cd wg-ssh-socks
docker build -t wg-ssh-socks .
```

> You may need to adjust `wg0.conf.template` if you want to hardcode specific settings.

---

## Running

1. **Key-Based SSH**:
```bash
docker run -d --name wg-socks \
  --cap-add=NET_ADMIN \
  -p 127.0.0.1:51820:51820/udp \
  -e SSH_REMOTE_HOST="host.com" \
  -e SSH_REMOTE_USER="root" \
  -e SSH_REMOTE_PORT="22" \
  -e SSH_AUTH_METHOD="privatekey" \
  -e SSH_PRIVATE_KEY="$(cat ~/.ssh/id_ed25519)" \
  wg-ssh-socks
```
- If peering config is not set, wireguard will not work but the SSH SOCKS proxy will be available.
- This will allow both SSH and WireGuard clients to connect to the SOCKS proxy.

2. **Add a WireGuard Peer**:
```bash
docker run -d --name wg-socks \
  --cap-add=NET_ADMIN \
  -p 127.0.0.1:51820:51820/udp \
  -p 1080:1080/tcp \
  -e WG_PEER_PUBLIC_KEY="abcd1234..." \
  -e WG_PEER_ALLOWED_IPS="10.8.0.2/32" \
  -e SSH_REMOTE_HOST="host.com" \
  -e SSH_REMOTE_USER="root" \
  -e SSH_PASSWORD="pass" \
  wg-ssh-socks
```
- This appends a `[Peer]` block for your WireGuard client’s public key, so the container is ready to accept that client.
- Both WireGuard and SOCKS proxy will be available to the client.

---

## Client Configuration

You must configure your **WireGuard client** to connect to this container’s WireGuard server. A minimal client config might look like:

```shell
wg genkey | tee client_private.key | wg pubkey > client_public.key
```

Then create a config file (e.g., `client.conf`):
```

```ini
[Interface]
PrivateKey = <YOUR_CLIENT_PRIVATE_KEY>
Address = 10.8.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = <SERVER_PUBKEY_SHOWN_IN_DOCKER_LOGS>
Endpoint = <SERVER_PUBLIC_IP>:51820
AllowedIPs = 0.0.0.0/0 # Exclude your ssh server IP
PersistentKeepalive = 25
```
- **`<SERVER_PUBLIC_IP>`** is the IP/domain where you run the Docker container.
- **`<SERVER_PUBKEY_SHOWN_IN_DOCKER_LOGS>`** is the line printed during container startup (the public key derived from the server’s private key).

> You may need to exclude your ssh server IP using [this](https://www.procustodibus.com/blog/2021/03/wireguard-allowedips-calculator/)

---

## Examples

### 1. SOCKS For WireGuard Clients Only
If you want the SOCKS proxy **only** available to clients connected via WireGuard, do:
- `SSH_SOCKS_IP=10.8.0.1` (the container’s WireGuard IP).
- **Do not** publish port `1080` on the host (`no -p 1080:1080/tcp`).  
  Then only clients who have a 10.8.0.x address (i.e., connected over WireGuard) can reach the SOCKS proxy at `10.8.0.1:1080`.

### 2. Provide Your Own WireGuard Private Key
```bash
-e WG_SERVER_PRIVATE_KEY="SOME_BASE64_WG_KEY"
```
If you want consistent keys across container restarts.