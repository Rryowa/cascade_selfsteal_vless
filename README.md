# Guide to setup Selfsteal / self-steal VLESS connection via remnawave protected by NetBird.

You need 3 VPS instances, 1x(1cpu, 2gb ram), 2x(1cpu, 1gb ram).
2gb ram for Panel,other two for nodes.
(No you cant use panel and domain on same node [it will be the hell for debugging and stability])

Create panel domain, sub domain, selfsteal domain for reality masking, point them to VPS where script executed.
 
```sh
ssh <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/remnawave.sh) @ install
```

Once installed, the following CLI commands are available:
- `remnawave <command>`: Manage panel (up, down, restart, logs, backup, restore, etc.).
- `remnanode <command>`: Manage nodes (update core, status, xray_log_out, etc.).
- `selfsteal <command>`: Manage Reality masking and templates.
  
1. Log in to your Panel at provided url
2. Add Node (Name, IP Address, Port)
3. SSH into the FIRST Node
4. Install node with same port:
```sh
bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/remnanode.sh) @ install
```
5. Install Selfsteal NGINX (Caddy sucks):
```sh
bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/selfsteal.sh) @ install --nginx

selfsteal template install filecloud
```
6. Verify Node is Green in GUI
7. Create Config for FIRST node (EU):
```json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "EU_EXIT",
      "port": 443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "flow": "xtls-rprx-vision",
        "clients": [],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "xver": 1,
          "target": "/dev/shm/nginx.sock",
          "shortIds": [
            "abc123"
          ],
          "publicKey": "GENERATE IN REMNAWAVE GUI",
          "privateKey": "GENERATE IN REMNAWAVE GUI",
          "serverNames": [
            "DOMAIN FOR SELFSTEAL"
          ]
        }
      }
    },
    {
      "tag": "BRIDGE_IN",
      "port": 50001,
      "listen": "'0.0.0.0' but setup at least shadowsocks encryption OR 'IP from NetBird dashboard'",
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      },
      "streamSettings": {
        "network": "raw",
        "security": "none"
      }
    }
  ],
  "outbounds": [
    {
      "tag": "DIRECT",
      "protocol": "freedom"
    },
    {
      "tag": "BLOCK",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "rules": [
      {
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "BLOCK"
      },
      {
        "domain": [
          "geosite:private"
        ],
        "outboundTag": "BLOCK"
      },
      {
        "protocol": [
          "bittorrent"
        ],
        "outboundTag": "BLOCK"
      },
      {
        "ip": [
          "geoip:ru"
        ],
        "outboundTag": "BLOCK"
      },
      {
        "domain": [
          "geosite:category-ru"
        ],
        "outboundTag": "BLOCK"
      }
    ]
  }
}
```


8. Assign Node to a config
9. Verify Node is Green in GUI
10. Create a internal 'EU Squad', assign to inbound
11. Create host, assign to inboud
12. Repeat steps 3-11 for ENTRY node (RU), config:
```json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "RU_ENTRY",
      "port": 443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "flow": "xtls-rprx-vision",
        "clients": [],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "xver": 1,
          "target": "/dev/shm/nginx.sock",
          "shortIds": [
            "abc123"
          ],
          "publicKey": "GENERATE IN PANEL",
          "privateKey": "GENERATE IN PANEL",
          "serverNames": [
            "ANOTHER SELFSTEAL DOMAIN"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "DIRECT",
      "protocol": "freedom"
    },
    {
      "tag": "BLOCK",
      "protocol": "blackhole"
    },
    {
      "tag": "TUNNEL_EU",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "port": 50001,
            "users": [
              {
                "id": "INSERT VLESS ID FROM USER",
                "encryption": "none"
              }
            ],
            "address": "'NODE IP' OR 'IP from NetBird dashboard'",
          }
        ]
      },
      "streamSettings": {
        "network": "raw",
        "security": "none"
      }
    }
  ],
  "routing": {
    "rules": [
      {
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "BLOCK"
      },
      {
        "domain": [
          "geosite:private"
        ],
        "outboundTag": "BLOCK"
      },
      {
        "protocol": [
          "bittorrent"
        ],
        "outboundTag": "BLOCK"
      },
      {
        "ip": [
          "geoip:ru"
        ],
        "outboundTag": "DIRECT"
      },
      {
        "domain": [
          "geosite:category-ru"
        ],
        "outboundTag": "DIRECT"
      },
      {
        "inboundTag": [
          "RU_ENTRY"
        ],
        "outboundTag": "TUNNEL_EU"
      }
    ]
  }
}
```

13. The port 50001 will only open if there is an active user assigned to that specific inbound.
In the edit modal, look for the Inbounds section.
You will see EU_EXIT is checked (enabled), but your new BRIDGE_IN is unchecked.
Check the box next to BRIDGE_IN to enable it for this specific node.

14. Set up the NetBird Network
    1. Get a Setup Key:
      * Go to the NetBird Dashboard (https://app.netbird.io/) and sign up/log in (it's free for up to 100 devices).
      * Navigate to the Setup Keys section.
      * Create a new "Reusable" setup key and copy it.
    
    2. Install NetBird on both VPS nodes:
     Run this exact command on both your Entry (RU) and Exit (EU) servers, replacing YOUR-SETUP-KEY with the key you just copied:
     ```sh
     bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/netbird.sh) install --key YOUR-SETUP-KEY
     ```
     Note: This script will automatically install NetBird, connect to your network

15. Now we need to tell Xray to use these new, private IPs instead of the public internet.
The RU node needs to send traffic to the EU node.
BRIDGE_IN inbound 'listen' must point to the EU NETBIRD IP
TUNNEL_EU outbound 'address' must point to the EU NETBIRD IP

You can check ip's in netbird dashboard

16. Also EU exit node will be red until you connect panel to netbird and change ip of eu node to  netbird's one (port is the same)
