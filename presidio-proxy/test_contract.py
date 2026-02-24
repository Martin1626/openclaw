"""Test PII detection on a full Czech contract document."""
import json
from proxy import detect_pii

text = """## VZOR – Smlouva o poskytování služeb (test anonymizace)

**Smluvní strany**

1. **Objednatel**
   Jméno a příjmení: **Jan Testák**
   Datum narození: **31. 2. 1999** (zjevně neplatné – test)
   Místo narození: **Testov**
   Státní občanství: **CZ**
   Adresa trvalého pobytu: **U Zkušebny 123/45, 110 00 Praha 1**
   Korespondenční adresa: **P. O. Box 999, 110 00 Praha 1**
   Telefon: **+420 700 000 001**
   E-mail: **jan.testak@example.com**
   Číslo OP: **TEST-OP-000000**
   Číslo pasu: **TEST-PAS-000000**
   Rodné číslo / ID: **TEST-RC-990231/0000**
   DIČ (pokud je): **CZTEST00000000**
   Bankovní spojení (IBAN): **CZ00 0000 0000 0000 0000 0000**
   Zdravotní pojišťovna: **TESTP 000**
   Kontaktní osoba pro případ nouze: **Petra Testová, +420 700 000 002, petra.testova@example.com**

2. **Poskytovatel**
   Obchodní firma: **TestServis s.r.o.**
   IČO: **00000000** (test)
   DIČ: **CZ00000000** (test)
   Sídlo: **Náměstí Anonymizace 1, 602 00 Brno**
   Zapsaná v OR: **Krajský soud v Testově, oddíl C, vložka 00000** (test)
   Zastoupená: **Mgr. Klára Fiktivní**, jednatelka
   Datum narození: **00. 00. 2000** (test)
   Adresa: **Falešná 99, 602 00 Brno**
   Telefon: **+420 700 000 003**
   E-mail: **k.fiktivni@example.com**
   Číslo OP: **TEST-OP-111111**
   Bankovní spojení (IBAN): **CZ00 1111 1111 1111 1111 1111**

Objednatel a Poskytovatel dále společně jen „**Strany**".

---

### 1. Předmět smlouvy

1. Poskytovatel se zavazuje pro Objednatele poskytnout službu: „Administrativní výpomoc a evidence dokumentů" (dále jen „Služby").
2. Objednatel se zavazuje Služby převzít a uhradit cenu dle článku 3.

### 2. Rozsah a místo plnění

1. Rozsah Služeb: **zpracování 10 testovacích dokumentů, označení metadaty, export do PDF**.
2. Místo plnění: **U Zkušebny 123/45, Praha 1** a/nebo vzdáleně (online).
3. Termín plnění: **od 1. 3. 2026 do 15. 3. 2026**.

### 3. Cena a platební podmínky

1. Cena: **2 500 Kč** bez DPH (test).
2. Splatnost: **7 dní** od doručení faktury.
3. Variabilní symbol: **20260001** (test).

### 4. Předání a převzetí

1. Výstup bude předán e-mailem na adresu: **jan.testak@example.com** a současně uložen do sdílené složky: **https://example.com/share/test** (test odkaz).
2. Objednatel potvrdí převzetí odpovědí e-mailem do **3 dnů**.

### 5. Důvěrnost a ochrana informací

1. Strany se zavazují zachovat mlčenlivost o všech neveřejných skutečnostech získaných při plnění této smlouvy.
2. Za důvěrné se považují zejména osobní údaje typu: **jméno, adresa, datum narození, identifikátory dokladů, kontakty, bankovní údaje** apod.

### 6. Zpracování osobních údajů (GDPR) – testovací ustanovení

1. Strany berou na vědomí, že dokument obsahuje **fiktivní osobní údaje** vložené za účelem testu anonymizace.
2. Pokud by se v praxi zpracovávaly reálné osobní údaje, Strany by uzavřely samostatnou smlouvu o zpracování osobních údajů dle čl. 28 GDPR.

### 7. Závěrečná ustanovení

1. Tato smlouva se řídí právem České republiky.
2. Smlouva je vyhotovena ve **2 stejnopisech**, každá Strana obdrží 1.
3. Strany prohlašují, že si smlouvu přečetly a souhlasí s jejím obsahem.

---

**V Praze dne:** 24. 2. 2026

Za Objednatele: ____________________
**Jan Testák**

Za Poskytovatele: ____________________
**Mgr. Klára Fiktivní**, jednatelka **TestServis s.r.o.**"""

result = detect_pii(text)

print("=" * 80)
print(f"NALEZENO {len(result)} ENTIT")
print("=" * 80)

by_type: dict[str, list[str]] = {}
for e in sorted(result, key=lambda x: x["start"]):
    t = e["entity_type"]
    val = text[e["start"]:e["end"]]
    by_type.setdefault(t, []).append(val)
    print(f"  {t:22s} | score={e['score']:.2f} | {val}")

print()
print("=" * 80)
print("SOUHRN PO TYPECH")
print("=" * 80)
for t, vals in sorted(by_type.items()):
    print(f"  {t}: {len(vals)}x")
    for v in vals:
        print(f"    - {v}")
