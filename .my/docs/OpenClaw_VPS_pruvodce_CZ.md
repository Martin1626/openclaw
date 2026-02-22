# Nejlepší VPS pro OpenClaw v roce 2026: průvodce se zaměřením na bezpečnost

**Hetzner Cloud CX23 za €3,49/měsíc nabízí 2 vCPU, 4 GB RAM a 40 GB NVMe — tedy tři- až čtyřnásobek zdrojů oproti DigitalOcean nebo Vultr za poloviční cenu — což z něj činí jasného vítěze v kategorii hodnota za peníze pro provoz OpenClaw z České republiky.** Samotná hodnota však otázku nerozhoduje. Explozivní růst OpenClaw (přes 117 000 hvězdiček na GitHubu za pár týdnů) odhalil alarmující bezpečnostní mezery: sken přes Shodan nalezl **42 665 exponovaných instancí, z nichž 93,4 % mělo obejitou autentizaci**. Pro českého uživatele, který uvádí bezpečnost jako hlavní prioritu, musí volba poskytovatele vyvážit čistou hodnotu oproti vestavěným ochranám, souladu s GDPR a geografické blízkosti k Praze.

OpenClaw (dříve Clawdbot, poté Moltbot) je open-source autonomní AI agent, který propojuje více než 15 komunikačních platforem s LLM API prostřednictvím perzistentní Node.js služby na pozadí zvané Gateway. Virálním se stal na konci ledna 2026 po dvojím přejmenování kvůli problémům s ochrannými známkami. Agent zvládá příkazy shellu, správu souborů, automatizaci prohlížeče a více než 50 integrací — což znamená, že špatně nakonfigurovaná instance poskytuje útočníkům mimořádný přístup.

---

## OpenClaw potřebuje více RAM, než byste čekali

Přestože bývá popisován jako „lehký", skutečný minimální požadavek OpenClaw je **2 GB RAM** — Gateway havaruje během onboardingu a startu pod touto hranicí. Komunitní konsenzus, podpořený vlastním průvodcem nasazení od DigitalOcean, doporučuje **4 GB RAM** pro stabilní každodenní provoz. CPU je skutečně nenáročné (1–2 vCPU stačí), protože veškeré zpracování LLM probíhá vzdáleně přes API volání. Nároky na úložiště jsou skromné: **20–40 GB SSD** pokryje Docker image, SQLite databáze, logy konverzací a data skills.

| Prostředek | Minimum | Doporučeno | Poznámky |
|---|---|---|---|
| **RAM** | **2 GB** (tvrdý spodní limit) | **4 GB** | Pod 2 GB = havárie. Komunitní průvodci zdůrazňují, že RAM je klíčový |
| **CPU** | 1 vCPU | 2 vCPU | Není úzkým hrdlem — LLM volání jsou vzdálená |
| **Úložiště** | 20 GB SSD | 40 GB NVMe | Pro Docker, logy, SQLite, data skills |
| **Node.js** | v22+ (vynuceno) | Nejnovější LTS | Runtime Bun NENÍ doporučen |
| **Síť** | Stabilní odchozí HTTPS | Broadband | Gateway musí udržovat perzistentní WebSocket spojení |

To znamená, že plány nabízející pouze 1 GB RAM (cenová hladina $5–6 u DigitalOcean, Linode a Vultr) jsou pro produkční provoz OpenClaw rizikové. Realistickým minimem se stává tarif od 2 GB+, což výrazně přetváří cenové srovnání.

---

## Přímé srovnání 11 poskytovatelů

### Velcí cloudoví poskytovatelé

| Poskytovatel | Tarif | Cena/měsíc | vCPU | RAM | SSD | Přenos dat | Nejbližší DC k Praze |
|---|---|---|---|---|---|---|---|
| **Hetzner Cloud** | CX23 | **€3,49 (~$3,80)** | 2 | **4 GB** | 40 GB NVMe | **20 TB** | Norimberk (~300 km) |
| **DigitalOcean** | Basic $12 | $12 | 1 | 2 GB | 50 GB | 2 TB | Frankfurt (~500 km) |
| **Linode (Akamai)** | Shared $10 | $10 | 1 | 2 GB | 50 GB | 2 TB | Frankfurt (~500 km) |
| **Vultr** | High Perf $12 | $12 | 1 | 2 GB | 50 GB NVMe | 3 TB | Varšava (~530 km) |

### Evropští rozpočtoví poskytovatelé

| Poskytovatel | Tarif | Cena/měsíc | vCPU | RAM | SSD | Přenos dat | Nejbližší DC k Praze |
|---|---|---|---|---|---|---|---|
| **Contabo** | VPS 10 | **€4,50 (~$5)** | **4** | **8 GB** | 75 GB NVMe | Neomezeno* | Norimberk (~300 km) |
| **IONOS** | VPS S | **$4** | 2 | 2 GB | **80 GB NVMe** | Neomezeno | Německo |
| **Netcup** | VPS 200 G10s | ~€3,50–4,50 | 2 | 2 GB | 40 GB SSD | 80 TB | **Vídeň (~250 km)** |
| **OVHcloud** | VPS-1 | €4,99 (~$5,50) | 1 | 2 GB | 40 GB NVMe | Neomezeno | **Varšava (~530 km)** |
| **Aruba Cloud** | VPS Small | ~€2,79–4,99 | 1 | 1–2 GB | 20–40 GB NVMe | Neomezeno | **Praha (0 km!)** |
| **Time4VPS** | Linux2 | ~€3,99 | 1 | 2 GB | 20 GB SSD | ~2 TB | Litva |
| **Scaleway** | DEV1-S | ~€10,50 celkem | 2 | 2 GB | 20 GB Block | Zahrnuto | Varšava (~530 km) |

**Poznámka k cenám:** Všechny ceny jsou uvedeny bez DPH. Čeští spotřebitelé platí dalších **21 % DPH**, pokud nenakupují jako firma s platným DIČ pro reverse-charge. Hetzner a další EU poskytovatelé účtují v EUR; američtí poskytovatelé v USD.

---

## Bezpečnostní funkce, na kterých u OpenClaw skutečně záleží

Bezpečnostní profil OpenClaw je výjimečně kritický, protože agent umí spouštět příkazy shellu, přistupovat k souborům a ovládat komunikační platformy. Kompromitovaná instance znamená plný přístup k systému. Zde je srovnání poskytovatelů z hlediska funkcí, které jsou nejdůležitější:

| Funkce | Hetzner | DigitalOcean | Vultr | Contabo | IONOS | Netcup | OVHcloud |
|---|---|---|---|---|---|---|---|
| **Cloud firewall** | ✅ Zdarma | ✅ Zdarma | ✅ Zdarma | ❌ Pouze DIY | ✅ Spravovaný | ✅ Základní | ✅ Zahrnuto |
| **DDoS ochrana** | ✅ Zdarma | ✅ Zdarma | ⚠️ Placený doplněk | ✅ Vždy zapnuto | ✅ Zahrnuto | ✅ Základní | ✅ Zdarma |
| **VPC / privátní síť** | ✅ | ✅ | ✅ VPC 2.0 | ❌ | Omezeno | ❌ | Omezeno |
| **SSH klíčová autentizace** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Automatické zálohy** | €0,70/měs | ~$2,40/měs | ~$2,40/měs | Placený doplněk | Placený doplněk | Omezeno | **Denní zdarma** |
| **Snapshoty** | €0,01/GB/měs | $0,06/GB/měs | $0,05/GB/měs | 3 zdarma | ❌ | ✅ | ✅ |
| **OpenClaw 1-click** | ❌ | **✅ Ano** | ❌ | ❌ | ❌ | ❌ | ❌ |
| **SLA dostupnosti** | Bez formální SLA | 99,99 % | 100 % | 99,9 % | 99,9 % | Best-effort | 99,9 % |
| **Síla GDPR** | **🟢 EU firma** | 🟡 US firma | 🟡 US firma | **🟢 EU firma** | **🟢 EU firma** | **🟢 EU firma** | **🟢 EU firma** |
| **2FA pro účet** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

**DigitalOcean je jediným poskytovatelem nabízejícím bezpečnostně hardenovaný 1-click image pro OpenClaw.** Tento image zahrnuje Docker izolaci, Caddy reverzní proxy s automatickým TLS, běh pod non-root uživatelem, autentizaci Gateway, párování zařízení a zpřísněná pravidla firewallu. Packer build skripty jsou veřejně auditovatelné. Nicméně nejlevnější použitelný Droplet pro tento image stojí **$12/měsíc** (tarif s 2 GB RAM) — třikrát více než Hetzner za slabší parametry.

**DDoS ochrana u Vultr je placený doplněk (~$10/měsíc)**, není zahrnuta zdarma. Toto je významný rozdíl, který eliminuje rozpočtovou atraktivitu Vultr pro uživatele zaměřené na bezpečnost.

---

## Proč Hetzner vítězí v poměru cena/výkon a GDPR souladu

Tarif Hetzner Cloud CX23 nabízí parametry, za které si konkurence účtuje $12–24/měsíc. Čísla hovoří sama za sebe: **4 GB RAM za €3,49** oproti 2 GB RAM za $10–12 u DigitalOcean nebo Linode. Pro českého uživatele tuto výhodu umocňují tři faktory.

**Geografická blízkost je důležitá.** Datacentra Hetzner v Norimberku a Falkensteinu se nacházejí přibližně 300 km od Prahy a poskytují **latenci pod 15 ms**. Blíže je pouze datacentrum Netcup ve Vídni (~250 km) a datacentrum Aruba Cloud přímo v Praze. Nízká latence udržuje WebSocket spojení Gateway responzivní při správě real-time komunikačních integrací.

**Jednoduchost z hlediska GDPR.** Hetzner je německá společnost se sídlem v Gunzenhausenu, provozující výhradně EU datacentra podle německých standardů ochrany dat (certifikace ISO 27001). Na rozdíl od DigitalOcean, Linode nebo Vultr — všechny se sídlem v USA a podléhající **americkému CLOUD Act** — Hetzner zcela eliminuje obavy z přeshraničního přenosu dat. Pro českého uživatele podléhajícího zákonu č. 110/2019 Sb. a dohledu ÚOOÚ je to cesta nejmenšího regulatorního odporu.

**Kompromisem je vlastní správa.** Hetzner neposkytuje 1-click OpenClaw image, žádné spravované služby, žádné marketplace aplikace a žádnou formální numerickou SLA dostupnosti. Podpora je pouze e-mailem. Server je nutné hardenovat vlastními silami. Pro uživatele se zkušenostmi se správou Linuxu je to irelevantní. Pro ty, kteří chtějí řešení na klíč, nabízí 1-click deploy od DigitalOcean za $12/měsíc pohodlí a předem zabezpečenou konfiguraci za příplatek.

---

## Hardenování OpenClaw na libovolném VPS: nezbytný checklist

Bez ohledu na poskytovatele musí každé nasazení OpenClaw řešit stejné bezpečnostní základy. Oněch **42 665 exponovaných instancí** nalezených na Shodanu existuje proto, že provozovatelé tyto kroky přeskočili.

**Uzamčení sítě je naprosto zásadní krok.** WebSocket řídicí rovina Gateway (port 18789) a ovládání prohlížeče (port 18791) nesmí být **nikdy** vystaveny veřejnému internetu. Obojí navažte pouze na `127.0.0.1`. Přístup by měl proudit výhradně přes SSH tunely (`ssh -N -L 18789:127.0.0.1:18789 user@vps`), Tailscale mesh VPN, nebo reverzní proxy s autentizací. Doporučená architektura:

```
Internet → Caddy/Nginx (TLS + autentizace) → Docker síť → OpenClaw kontejner (127.0.0.1:18789)
```

**Nezbytné kroky hardenování:**

- Nakonfigurujte UFW tak, aby odmítal veškerý příchozí provoz kromě SSH (vlastní port) a HTTPS (443). Toto vrstveně doplňte cloud firewallem poskytovatele pro obranu do hloubky.
- Zakažte SSH přihlašování jako root a autentizaci heslem. Používejte výhradně SSH klíče s monitoringem přes Fail2Ban (maxretry=3, bantime=3600).
- Spouštějte OpenClaw v Dockeru s `read_only: true`, `security_opt: [no-new-privileges:true]`, `cap_drop: [ALL]` a limity paměti/PID.
- Nikdy nemontujte `~/.ssh`, `~/.aws`, `/etc` ani `/var/run/docker.sock` do kontejneru.
- API klíče ukládejte přes `openclaw auth set` (systémová klíčenka) nebo Docker Secrets — nikdy v plaintextových konfiguračních souborech.
- Povolte `unattended-upgrades` pro automatické bezpečnostní záplaty OS.
- Zablokujte nebezpečné příkazy v denylistu nástrojů OpenClaw: `rm`, `chmod`, `sudo`, `wget`, `curl`, `docker`.
- Pravidelně spouštějte `openclaw doctor` pro detekci chybných konfigurací.

**Další hrozby k monitorování:** Na tržišti ClawHub byly objeveny škodlivé skills (reverse shelly maskované jako legitimní nástroje). Repozitář skills nemá dostatečnou kontrolu. Instalujte skills pouze z důvěryhodných zdrojů a před povolením auditujte jejich kód.

---

## Závěr: rozhodovací matice

Správný poskytovatel závisí na tom, které omezení optimalizujete:

| Priorita | Nejlepší volba | Důvod |
|---|---|---|
| **Nejlepší hodnota celkově** | **Hetzner CX23** (€3,49/měs) | 4 GB RAM + 2 vCPU + 40 GB NVMe za méně než €4. Bez konkurence. |
| **Maximální bezpečnost ihned po nasazení** | **DigitalOcean** ($12/měs) | Jediný poskytovatel s hardenovaným 1-click OpenClaw image. Příplatek se vyplatí, pokud chcete řešení na klíč. |
| **Nejlepší surové parametry** | **Contabo VPS 10** (~€4,50/měs) | 4 vCPU + 8 GB RAM je masivní předimenzování, ale stojí méně než 2GB plány konkurence. |
| **Nejblíže Praze** | **Aruba Cloud** (~€2,79–4,99/měs) | Jediný poskytovatel s datacentrem v České republice. Ale slabá reputace podpory. |
| **Nejlepší GDPR + blízkost** | **Netcup VPS 200** (~€3,50–4,50/měs) | Datacentrum ve Vídni je 250 km od Prahy. EU firma. Výborná komunitní reputace. |
| **Nejlepší zahrnuté funkce** | **OVHcloud VPS-1** (€4,99/měs) | Denní zálohy zdarma, neomezený provoz, anti-DDoS — žádné náklady za doplňky. |

Pro českého vývojáře provozujícího OpenClaw jako osobního AI agenta v rozpočtu **€5–15/měsíc** je nejsilnějším doporučením **Hetzner CX23 s ručním bezpečnostním hardenováním**. Poskytuje dvojnásobek RAM, které OpenClaw potřebuje (4 GB vs 2 GB minimum), geograficky leží blízko Prahy a operuje výhradně v rámci EU jurisdikce. Úspora oproti 1-click deployi od DigitalOcean (~€8/měsíc rozdíl) mnohonásobně pokryje 30 minut počátečního hardenování serveru. Pokud se ruční nastavení zdá náročné, hardenovaný image DigitalOcean za $12/měsíc je nejbezpečnější alternativa na klíč — jen s vědomím, že platíte třikrát více za čtvrtinu zdrojů.
