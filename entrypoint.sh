#!/usr/bin/env bash
set -e

if [ ! -f /etc/wireguard/server_private_key ]; then
  mkdir -p /etc/wireguard
  chmod 700 /etc/wireguard
fi

WG_SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server_private_key 2>/dev/null || echo "")
SERVER_PUBKEY=""

if [ -z "$WG_SERVER_PRIVATE_KEY" ] || [ "$WG_SERVER_PRIVATE_KEY" = "" ]; then
  WG_SERVER_PRIVATE_KEY="$(wg genkey)"
  SERVER_PUBKEY="$(echo "$WG_SERVER_PRIVATE_KEY" | wg pubkey)"
  echo "$WG_SERVER_PRIVATE_KEY" > /etc/wireguard/server_private_key
  echo "Generated a new WireGuard server private key."
else
  SERVER_PUBKEY="$(echo "$WG_SERVER_PRIVATE_KEY" | wg pubkey)"
  echo "Using existing WireGuard server private key."
fi

cp /etc/wireguard/wg0.conf.template /etc/wireguard/wg0.conf

sed -i "s|{{WG_SERVER_PRIVATE_KEY}}|${WG_SERVER_PRIVATE_KEY}|g" /etc/wireguard/wg0.conf
sed -i "s|{{WG_INTERFACE_IP}}|${WG_INTERFACE_IP}|g" /etc/wireguard/wg0.conf
sed -i "s|{{WG_PORT}}|${WG_PORT}|g" /etc/wireguard/wg0.conf

if [ -n "$WG_PEER_PUBLIC_KEY" ]; then
  cat >> /etc/wireguard/wg0.conf <<EOF

[Peer]
PublicKey = $WG_PEER_PUBLIC_KEY
AllowedIPs = $WG_PEER_ALLOWED_IPS
EOF
fi

wg-quick up wg0
echo "WireGuard server public key: $SERVER_PUBKEY"
echo "WireGuard listening on UDP port $WG_PORT."

if [ -z "$SSH_REMOTE_HOST" ] || [ -z "$SSH_REMOTE_USER" ]; then
  echo "ERROR: Must set SSH_REMOTE_HOST and SSH_REMOTE_USER for the SSH-based SOCKS proxy."
  exit 1
fi

if [ "$SSH_AUTH_METHOD" = "privatekey" ]; then
  mkdir -p /tmp/sshkey
  KEYFILE="/tmp/sshkey/id_rsa"
  echo "$SSH_PRIVATE_KEY" > "$KEYFILE"
  chmod 600 "$KEYFILE"

  ssh_cmd="autossh -M 0 -N -o StrictHostKeyChecking=no -i $KEYFILE -D 127.0.0.1:$SSH_SOCKS_PORT -p $SSH_REMOTE_PORT $SSH_REMOTE_USER@$SSH_REMOTE_HOST"
  eval "$ssh_cmd" &
fi

if [ "$SSH_AUTH_METHOD" = "password" ]; then
  if [ -z "$SSH_PASSWORD" ]; then
    echo "ERROR: SSH_PASSWORD must be set."
    exit 1
  fi

  ssh_cmd="sshpass -p '$SSH_PASSWORD' autossh -M 0 -N -o StrictHostKeyChecking=no -D 127.0.0.1:$SSH_SOCKS_PORT -p $SSH_REMOTE_PORT $SSH_REMOTE_USER@$SSH_REMOTE_HOST"
  eval "$ssh_cmd" &
fi

REDSOCKS_CONFIG="/etc/redsocks.conf"
REDSOCKS_PORT="${REDSOCKS_PORT:-12345}"

cat > "$REDSOCKS_CONFIG" <<EOF
base {
  log_debug = off;
  log_info = off;
  daemon = off;
  log = stderr;
  redirector = iptables;
}

redsocks {
  local_ip = 0.0.0.0;
  local_port = $REDSOCKS_PORT;
  ip = 127.0.0.1;
  port = $SSH_SOCKS_PORT;
  type = socks5;
}
EOF

echo "Starting redsocks on port $REDSOCKS_PORT, forwarding to 127.0.0.1:$SSH_SOCKS_PORT..."
redsocks -c "$REDSOCKS_CONFIG" &
sleep 1

iptables -t nat -N REDSOCKS 2>/dev/null || true

iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN

WG_SUBNET="$(echo "$WG_INTERFACE_IP" | cut -d'/' -f1)/24"
iptables -t nat -A REDSOCKS -d "$WG_SUBNET" -j RETURN

SSH_SERVER_IP="$SSH_REMOTE_HOST"

# If SSH_REMOTE_HOST is an IP, use it directly
if ! [[ "$SSH_REMOTE_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  SSH_SERVER_IP_LOOKUP=$(getent hosts "$SSH_REMOTE_HOST" | awk '{print $1}' | head -n1)
  if [ -n "$SSH_SERVER_IP_LOOKUP" ]; then
    SSH_SERVER_IP="$SSH_SERVER_IP_LOOKUP"
  fi
fi

if [[ "$SSH_SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Excluding SSH server IP from redsocks: $SSH_SERVER_IP"
  iptables -t nat -A REDSOCKS -d "$SSH_SERVER_IP" -j RETURN
fi

# Everything else => redirect to redsocks local port
iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-port "$REDSOCKS_PORT"

# Apply redsocks chain to traffic from wg0
iptables -t nat -A PREROUTING -i wg0 -p tcp -j REDSOCKS

echo "iptables configured to intercept TCP from wg0."

#Keep container alive
tail -f /dev/null
