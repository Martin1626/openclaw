# OpenClaw - Server Info

## Hetzner Cloud VPS

| Parametr | Hodnota |
|---|---|
| **IP adresa** | 46.225.142.130 |
| **SSH port** | 2222 |
| **Uživatel** | deploy |
| **SSH klíč** | `~/.ssh/id_ed25519_myclaw-hetzner` |
| **OS** | Ubuntu 22.04/24.04 |
| **RAM** | 3.7 GB |
| **Disk** | 38 GB SSD |
| **Tarif** | Hetzner CX23 |

## Připojení

```bash
# Pouze SSH shell (bez tunelů)
ssh myclaw

# SSH s tunely pro OpenClaw (port 18789 + 18790)
ssh openclaw

# Jen tunely na pozadí (bez shellu)
ssh -N openclaw
```

Po připojení přes `ssh openclaw` je webové rozhraní dostupné na:
**http://localhost:18789**

SSH konfigurace: `~/.ssh/config`

## Kontejnery na serveru

| Kontejner | Image | Port (localhost) | Účel |
|---|---|---|---|
| `myclaw` | myclaw-myclaw | 8080 | myClaw instance |
| `openclaw-openclaw-gateway-1` | openclaw:local | 18789, 18790 | OpenClaw Gateway |

## OpenClaw - cesty na serveru

| Co | Cesta |
|---|---|
| **Zdrojový kód (fork)** | `/home/deploy/openclaw/` |
| **Docker Compose** | `/home/deploy/openclaw/docker-compose.yml` |
| **Env konfigurace** | `/home/deploy/openclaw/.env` |
| **Gateway konfigurace** | `/home/deploy/.openclaw-gw/openclaw.json` |
| **Data (SQLite, logy)** | `/home/deploy/.openclaw-gw/` |
| **Workspace** | `/home/deploy/.openclaw-gw/workspace/` |

## OpenClaw - přístupové údaje

| Údaj | Hodnota |
|---|---|
| **Gateway token** | `e09827b725998431a32baeac1a2b7e639951dfea0714b428877c5b5fa19c4729` |
| **LLM provider** | Anthropic (Claude) |
| **API klíč** | Uložen v `.env` a `openclaw.json` na serveru |
| **Anthropic konzole** | https://console.anthropic.com |

## GitHub fork

| Údaj | Hodnota |
|---|---|
| **Fork URL** | https://github.com/Martin1626/openclaw |
| **Uživatel** | Martin1626 |
| **Upstream** | Oficiální OpenClaw repozitář |

Fork je plně pod vaší kontrolou - žádné změny z upstreamu se nepropagují automaticky.

## Správa OpenClaw (příkazy na serveru)

```bash
cd ~/openclaw

# Logy
docker compose logs -f openclaw-gateway

# Restart
docker compose restart openclaw-gateway

# Zastavení
docker compose down

# Spuštění
docker compose up -d openclaw-gateway

# Stav všech kontejnerů
docker ps
docker stats --no-stream
```

## Aktualizace OpenClaw

```bash
cd ~/openclaw

# 1. Stáhnout změny z VAŠEHO forku
git pull

# 2. (Volitelně) Stáhnout změny z upstreamu
git remote add upstream https://github.com/openclaw/openclaw.git   # jen poprvé
git fetch upstream
git diff main upstream/main          # prohlédnout změny PŘED mergem
git merge upstream/main              # pouze pokud chcete

# 3. Rebuild a restart
docker compose down
docker build -t openclaw:local -f Dockerfile .
docker compose up -d openclaw-gateway
```

## Záloha před aktualizací

```bash
docker compose down
tar czf ~/openclaw-backup-$(date +%Y%m%d).tar.gz \
  /home/deploy/.openclaw-gw/
```

## Bezpečnostní architektura

```
Váš počítač                          Hetzner VPS
+---------------+    SSH tunel     +----------------------------------+
| localhost:    | ===============> | sshd :2222                       |
|  18789 -------+--tunnel---------+-> 127.0.0.1:18789 -> [OpenClaw]  |
|  18790 -------+--tunnel---------+-> 127.0.0.1:18790 -> [OpenClaw]  |
|  8080  -------+--tunnel---------+-> 127.0.0.1:8080  -> [myClaw]    |
+---------------+                  |                                  |
                                   | Docker sítě (oddělené):          |
                                   |   openclaw_default: [OpenClaw]   |
                                   |   myclaw_default:   [myClaw]     |
                                   +----------------------------------+
```

- Všechny porty bindované pouze na `127.0.0.1` (ne veřejně)
- Kontejnery na oddělených Docker sítích (nevidí se navzájem)
- Přístup pouze přes SSH tunel s klíčem
- Gateway chráněný tokenem

## Datum instalace

2026-02-21
