# OpenClaw — Nasazení pro klienta

Kompletní návod jak nasadit OpenClaw na čistý VPS server.

## Požadavky

| Co | Minimum | Doporučeno |
|----|---------|------------|
| **RAM** | 2 GB | 4 GB |
| **Disk** | 20 GB SSD | 40 GB NVMe |
| **OS** | Ubuntu 22.04+ / Debian 12+ | Ubuntu 24.04 LTS |
| **Přístup** | SSH (root nebo sudo) | |

**Doporučený VPS:** Hetzner CX23 (4 GB RAM, 40 GB NVMe, €3,49/měsíc)

## Co budete potřebovat

1. **Anthropic API klíč** — získáte na [console.anthropic.com](https://console.anthropic.com/settings/keys)
2. **Telefon s WhatsApp** (volitelné) — pro propojení s WhatsApp

---

## Instalace

### Krok 1: Připojte se na server

```bash
ssh root@<IP-adresa-serveru>
```

### Krok 2: Nainstalujte Docker (pokud nemáte)

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

Odhlaste se a přihlaste znovu (aby se projevila skupina `docker`).

### Krok 3: Stáhněte OpenClaw

```bash
git clone https://github.com/<your-repo>/openclaw.git
cd openclaw
```

### Krok 4: Spusťte instalaci

```bash
bash setup-client.sh
```

Skript vás provede nastavením:
- Zadáte Anthropic API klíč
- Volitelně přidáte příjmení kontaktů (pro lepší PII ochranu)
- Automaticky se sestaví Docker image
- Projdete onboardingem
- Volitelně propojíte WhatsApp (QR kód v terminálu)

### Krok 5: Hotovo!

Po dokončení uvidíte:
- **WebUI adresu** — otevřete v prohlížeči
- **Gateway token** — pro autentizaci
- **Užitečné příkazy** — logy, restart, stop

---

## Běžné operace

### Zobrazení logů

```bash
docker compose logs -f
```

### Restart

```bash
docker compose restart
```

### Zastavení

```bash
docker compose down
```

### Aktualizace

```bash
bash update-client.sh
```

### Připojení WhatsApp (dodatečně)

```bash
docker compose run --rm openclaw-cli channels login
```

V telefonu: WhatsApp → Nastavení → Propojená zařízení → Propojit zařízení → naskenujte QR kód.

---

## PII anonymizace

OpenClaw automaticky anonymizuje osobní údaje před odesláním do AI (Anthropic API):

- **Jména** — česká křestní jména + příjmení (vlastní i s příponovým rozpoznáváním)
- **Adresy** — celé české adresy (ulice, číslo, PSČ, město)
- **Telefony** — české formáty (+420...)
- **E-maily** — všechny e-mailové adresy
- **Rodná čísla** — formát XX/XXXX
- **IČO, DIČ** — firemní identifikátory
- **IBAN, platební karty** — bankovní údaje

### Přidání vlastních příjmení

Upravte soubor `presidio-proxy/surnames.txt` (jeden záznam na řádek, malými písmeny):

```
novák
nováková
dvořák
```

Po úpravě restartujte: `docker compose restart presidio-proxy`

### Dočasné vypnutí anonymizace

Napište zprávu začínající `/noanon`:

```
/noanon Jak se jmenuje můj doktor?
```

Tato zpráva projde bez anonymizace. Další zprávy budou opět chráněny.

---

## Řešení problémů

### Kontejnery neběží

```bash
docker compose ps          # stav kontejnerů
docker compose logs        # chybové hlášky
```

### PII proxy neodpovídá

```bash
docker compose logs presidio-proxy
curl http://localhost:3001/health
```

### WhatsApp se odpojí

```bash
docker compose run --rm openclaw-cli channels login
```

### Nedostatek paměti

Zkontrolujte RAM: `free -h`. OpenClaw potřebuje minimálně 2 GB volné RAM.

### Aktualizace selhala

```bash
cd ~/openclaw
git stash                  # uloží lokální změny
git pull
git stash pop              # vrátí lokální změny
bash update-client.sh
```

---

## Bezpečnost

- Gateway je chráněn tokenem — sdílejte ho pouze důvěryhodným zařízením
- PII proxy běží lokálně — žádná osobní data neopouští server v čitelné formě
- Docker kontejnery běží jako non-root uživatel
- Doporučeno: nastavte firewall (UFW) a povolte pouze porty 22 (SSH) a 18789 (gateway)

```bash
sudo ufw allow 22/tcp
sudo ufw allow 18789/tcp
sudo ufw enable
```
