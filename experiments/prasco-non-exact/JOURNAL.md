# Ottimizzazione su "Strategie-dizionari-non-exact-11-10.xlsx"

Diario dei cicli di ottimizzazione: cosa cambia a ogni ciclo, come si misura, risultati.

## Lettura del file del collega

- Test: applicability (VIN + descrizione Prasco + OE dal cross SKU→OE), 4998 casi **non exact**; misura "posto giusto" (il pezzo trovato è del tipo/lato giusto).
- A (oggi, solo descrizione): 60.2%. Ripetere la domanda (B): 65.8% → la variabilità dell'LLM vale ~5 punti.
- Aggiungere una "frase" alternativa (O = nome AIVIN per marca+tipo, P = con posizione, D = vinsearch): ~+5 punti l'una; la frase migliore per marca+tipo (D): 71.6%; tutte (E): 72.8%; seconda chiamata con tutte le frasi solo sui falliti (F): 73.7%.
- Cioè: il guadagno viene dal **dare al navigatore la terminologia del catalogo** (sinonimi) per quel tipo di pezzo, meglio se specifica per marca.
- Famiglie peggiori: cornice 7%, riparo 7.5%, cantonale 12%, lucediurna 12.5%, supporto 13%, traversa 17%, vaschetta 28%, pannello 32%, intercooler 33%, rinforzo 45%, maniglia 48%, fendinebbia 50%.
- Marche peggiori: Kia 1.3%, Hyundai 19.5%, Fiat 37%, Nissan 39%, Alfa 42%, Land Rover 46%, Lancia 51%, Mercedes 52%.

## Metodo

- **Ground truth oggettivo**: nella cache S3 ci sono le ricerche FTS per OE fatte durante il test; quelle con esito positivo danno (VIN, SKU, descrizione, OE presente nel catalogo del veicolo). 5100 OE trovati su 201 VIN (`data/fts_searches.json`, script `data/build_gt.py`).
- **Campione** `data/sample-gt-v1.jsonl`: 88 casi stratificati per marca (pesati verso le marche deboli) e famiglia, max 3 per VIN (`data/build_sample.py`, seed fisso).
- **Misura**: find-part con la sola descrizione (come strategia A), senza FTS e senza cache dei percorsi (bucket `searches_*` disattivati):
  - `unit_hit` = la tavola selezionata contiene l'OE ("posto giusto" oggettivo, metrica principale);
  - `part_hit` = la parte selezionata è l'OE; `top3_unit_hit` = una delle prime 3 tavole selezionate contiene l'OE; `bag_hit` = una tavola visitata contiene l'OE (= exact in applicability).
- Harness: `ai-vin-service/test-cli/eval-find-part-sample.ts` (cache overlay: legge `.s3/cache` in sola lettura, scrive solo in `ai-vin-service/tmp/eval-cache`); riepilogo `summarize.py`.
- Rumore: LLM a temperatura 0 ma non deterministico; differenze di 2-3 casi su 88 non sono significative.

## Modifiche al codice (non strutturali)

- `ai-vin-service`: prompt di normalizzazione esterno, `AIVIN_NORMALIZE_PROMPT_FILE` (chiave S3 o path locale, come `AIVIN_HINTS_FILE`), template con `{{partName}}`; letto all'avvio, fallback al prompt built-in se assente/illeggibile/senza placeholder; nel log md5 e dimensione. Output parsato come oggi (riga 1 normalizzata = chiave cache, riga opzionale `context:` accodata alla ricerca).
- `bootstrapFunctions(config, { cache })`: cache iniettabile (usata dall'harness).

## Cicli

### Ciclo 0 — baseline (`runs/c0.jsonl`)
- Config: prompt built-in (`standard`), hints attuali (`configs/hints-c0.json` = copia di `.s3/hints/hints.json`).
- Nota metrica: in c0/c1 `unit_hit` è calcolato sulle sole parti selezionate (= pezzo esatto); harness corretto da c0b in poi (tavola completa dalle visitate). In pratica cambia poco: quando la tavola è giusta il ranker sceglie quasi sempre anche l'OE.
- Risultato: pezzo esatto 38/84 (45.2%), bag 45/84; 4 errori persistenti (404 del provider su `/units`, vedi sotto). Kia 0/6, Hyundai 0/5.
- Osservazioni sulla normalizzazione built-in: attributi a volte nel nome (`bumper rear with primer without moulding holes ... model classic - rear`), informazioni perse (`MANIGLIA ...-INTERNA` → `handle`, `PIASTRA SPECCHIO` → `mirror plate`, `COPRIMOTORE-INFERIORE` → `engine cover lower`). Gli hints esistenti non scattano mai (riguardano ricambi di manutenzione).

### Ciclo 1 — prompt v1 (`runs/c1.jsonl`)
- Variato: prompt di normalizzazione esterno `configs/normalize-prompt-v1.md` (glossario Prasco IT→EN catalogo, posizioni italiane, riga 1 compatta, sinonimi + varianti nella riga `context:`).
- Codice: 404 su `/units` slax tollerato (salta solo quella tavola).
- Risultato: pezzo esatto 47/88 (53.4%) vs 45.2%: +9 / −3. Guadagni: frontale (Jeep, Mercedes, Mini), intercooler Nissan, copri gancio traino Opel, fendinebbia Ford/Seat, maniglia interna Mercedes. Perdite: alzacristallo Audi/Citroen (il sinonimo "window motor" porta verso l'elettrica), supporto faro VW.
- Kia/Hyundai ancora 0/11.

### Finding fuori dal perimetro prompt/hints
- **Kia: tavole troncate dal provider slax-partslink** (VIN KNA*): 1–8 righe per tavola in media, anche in chiamata live (es. `TR / 86-865 .1 FRONT BUMPER` → solo `bulb-halogen`; `BO / 60-624 .1` → solo `NUT`). Hyundai completo (18–31 righe). Spiega il 1.3% di Kia nel file del collega: va corretto lato provider.
- **Struttura catalogo per marca** (`data/catalog-structure-weak-brands.md`): Kia/Hyundai paraurti, specchi, passaruota sotto TRIM (non BODY), riparo sotto ENGINE > UNDER COVER; Fiat/Lancia cofano e maniglie sotto "DISPLAY UNITS AND WINDOWS", riparo sotto "TRAILER AND COVERS > FRAME GUARDS"; Mercedes specchi sotto "Driver's door", paraurti/griglia/cofano sotto "Detachable parts"; Nissan carrozzeria divisa tra J/K/M.
- **429 del provider** con 4 richieste concorrenti su percorsi non in cache: l'errore fa fallire l'intera find-part (nessun retry; vedi TODO "Gestione dei 429").

### Ciclo 0b — baseline ripetuta, metrica corretta (`runs/c0b.jsonl`)
- Stessa config di c0 (+ fix 404). Pezzo esatto 41/88 (46.6%), tavola 43/88 (48.9%), bag 46/88.
- **Rumore** tra c0 e c0b: ±3 casi (~3-4 punti) a parità di config.

### Ciclo 2 — prompt v1 + hints c1 (`runs/c2.jsonl`)
- Variato: `configs/hints-c1.json` = hints esistenti + 75 entry per Kia/Hyundai, Fiat/Lancia/Alfa/Abarth, Mercedes, Nissan (posizione delle famiglie nell'albero), una entry per alias di nome (es. bumper / bumper corner / bumper spoiler...) perché la ricerca hint è per similarità embedding (soglia 0.4) sul nome.
- Codice: hint cercati sul nome normalizzato (riga 1) invece che su nome + context; hint duplicati rimossi.
- Risultato: pezzo esatto 45/88 (51.1%) vs c1 47/88, bag 50 vs 48: nel rumore. Hints effettivamente iniettati (177 chiamate ranker con ≥1 hint). +1 Fiat rinforzo (grazie all'hint), −1 Mercedes maniglia interna (hint sbagliato: "Locking system" vale solo per le maniglie esterne).
- **Hyundai**: la navigazione è in realtà corretta in 4/5 casi (`lamp assy-day running light,lh`, `carrier assy-front end module`, `regulator assy-fr dr p/wdo rh`, `radiator assy`), ma il provider espone il **PNC** come numero parte (`92207`, `64101`...) invece dell'OE: il match OE non può riuscire. Altro problema lato provider.

### Ciclo 3 — prompt v2 + hints c2, due ripetizioni (`runs/c3.jsonl`, `runs/c3b.jsonl`)
- Variato: `configs/normalize-prompt-v2.md` (alzacristallo senza "window motor"; "crossrail" per rinforzo/traversa/frontale, termine Fiat; retronebbia → "rear bumper lamp"; telaio supporto motore → subframe/front crossrail); `configs/hints-c2.json` (maniglie Mercedes: esterne sotto "Locking system", interne sotto "Door paneling"; Kia/Hyundai retronebbia e catadiottri nel paraurti posteriore sotto TRIM).
- Risultato: pezzo esatto 45/88 e 46/88 (core senza Kia/Hyundai: 58.4% e 59.7%).

#### Riepilogo cicli (core = escluse Kia/Hyundai, limitate dal provider; 77 casi)
| run | config | pezzo esatto core | bag core |
|---|---|---|---|
| c0 | built-in + hints attuali | 52.1% (38/73, 4 errori) | 61.6% |
| c0b | idem (ripetizione) | 53.2% | 59.7% |
| c1 | prompt v1 | 61.0% | 62.3% |
| c2 | prompt v1 + hints c1 | 58.4% | 64.9% |
| c3 | prompt v2 + hints c2 | 58.4% | 63.6% |
| c3b | idem (ripetizione) | 59.7% | 64.9% |

Lettura: il prompt esterno vale **+6/+7 punti** stabili (4 run su 4 sopra la baseline); v2 vs v1 e gli hints non sono distinguibili dal rumore su questo campione (pochi casi per marca debole), gli hints però correggono casi mirati (Fiat rinforzo).

#### Fallimenti residui (falliti in entrambe le ripetizioni di c3)
- **Provider, cache PSA obsoleta** (Citroen/Peugeot): il provider ha cambiato formato dei codici tavola (`Illustration 011007 7 433 01A` / `Description BONNET` → `011007 7 433 01A` / `bonnet`); i livelli in cache S3 hanno il vecchio formato, quindi `/units` con il vecchio codice risponde 404. La navigazione arriva alla tavola giusta (Citroen cofano, maniglia; Peugeot cantonale) ma la tavola non si legge. **Succede anche in produzione** finché la cache PSA non viene invalidata.
- Varianti di tavola con lo stesso nome (`.1`/`.2`, `illust no. 1 of 2`) e scelta tra tavole sorelle: Toyota modanatura, VW specchio (scocca vs specchio completo), BMW specchio.
- Terminologia catalogo non coperta: Ford "cornice fendinebbia" = `Bracket - Fog Lamp`, Ford "cantonale" = `Moulding`, Peugeot "cantonale" = `REAR BUMPER OVERRIDER`, VW "supporto faro" = `Guide piece for headlamps`, Skoda "cornice griglia" = `Cover trim chrome`, BMW "passaruota parte anteriore" = `Cover, wheel housing, bottom`.
- Pezzi "kit" (kit riparazione proiettore Opel) e sensori PDC: casi rari.

### Validazione sui casi falliti del collega (`data/sample-casi-v1.jsonl`, `runs/casi-c0.jsonl`, `runs/casi-c3.jsonl`)
- 40 casi del foglio "Casi" (stato "misurato", esclusi Kia/Hyundai, una famiglia per caso), PSA con dati freschi (`--fresh-brands citroen,peugeot,ds`). Qui l'OE non è nel catalogo: giudizio "posto giusto" (tipo + lato) come nel file del collega, fatto da un agente su risultati anonimi e mescolati (`data/judge-casi-*.json`).
- Baseline (built-in): giusti 23/38, altro pezzo 11, nessuna risposta 4 (2 errori 429). Già la sola ripetizione recupera molti casi: coerente con la strategia B del collega (variabilità LLM).
- Finale (v2 + hints c2): giusti 25/39, altro pezzo 6, nessuna risposta 8 (1 errore). Meno pezzi sbagliati, più risposte vuote (soprattutto Fiat, tavole molto generiche: il ranker non trova un pezzo convincente).

### Ciclo 4 — prompt v3 + hints c2, PSA freschi (`runs/c4.jsonl`, baseline PSA `runs/c0-psa.jsonl`)
- Variato: `configs/normalize-prompt-v3.md` (sinonimi da terminologia catalogo vista nei fallimenti: cantonale → overrider / bumper moulding; cornice fendinebbia → fog lamp bracket / surround; cornice griglia → grille trim; supporto faro → headlamp guide piece; passaruota → wheel housing cover).
- Risultato: core pezzo/tavola 46/77 (59.7%), bag 50/77; i casi mirati dalla v3 (Ford cornice/cantonale, VW supporto faro, Skoda cornice griglia) restano falliti: il problema è nella scelta della tavola, non del nome. v3 non peggiora: tenuta per coerenza del glossario.
- Con dati PSA freschi la baseline PSA fa 7/9, il finale 6/9 (rumore): su PSA il beneficio del prompt non si vede.

## Conclusioni

| core (77 casi, PSA freschi) | baseline c0b | finale c4 |
|---|---|---|
| tavola giusta | 43 (55.8%) | 46 (59.7%) |
| pezzo esatto | 41 (53.2%) | 46 (59.7%) |
| OE in una tavola visitata | 46 (59.7%) | 50 (64.9%) |

- Prompt esterno: +4/+7 punti, stabili su 5 run; risultato coerente con il +5 delle singole "frasi" del collega. Il grosso è nella traduzione corretta del tipo di pezzo (maniglia interna/esterna, piastra specchio = mirror glass, coprimotore inferiore = undertray, frontale, traversa/crossrail) e nella riga 1 compatta e stabile (anche chiave cache più riutilizzabile).
- Hints per marca: neutri sul campione (pochi casi per marca), utili su casi mirati; a costo zero.
- I limiti più grandi sono lato **provider/cache**, non del prompt: Kia (tavole troncate), Hyundai (PNC invece del codice OE), PSA (cache S3 col vecchio formato codici → 404), 429 senza retry.

## Deploy proposto (lo fa l'utente: `.s3` è in sola lettura)

1. Caricare `configs/normalize-prompt-v3.md` nel bucket, es. chiave `hints/normalize-prompt.md`, e impostare `AIVIN_NORMALIZE_PROMPT_FILE=hints/normalize-prompt.md` nel servizio; al riavvio il log `LoadNormalizePrompt` riporta dimensione e md5 (senza variabile resta il prompt built-in: rollback immediato).
2. Backup di `hints/hints.json` (convenzione `hints.json.YYYYMMDD.HHMM.bck`) e upload di `configs/hints-c2.json` come `hints/hints.json`.
3. Nota: la riga 1 della normalizzazione cambia, quindi cambiano le chiavi dei bucket `searches_*`: la cache dei percorsi riparte da zero per le nuove chiavi (le vecchie restano inutilizzate).

## Prossimi passi suggeriti
- Invalidare in S3 la cache slax-partslink di `citroen`, `peugeot`, `ds` (livelli e tavole col vecchio formato `Illustration ...`), o far accettare al provider i codici vecchi.
- Segnalare al provider slax-partslink: tavole Kia troncate; Hyundai con PNC al posto del numero parte.
- Retry/backoff sui 429 (TODO esistente).
- Strategia F del collega (seconda chiamata solo se l'applicability non è exact): oggi in applicability si sa a runtime se il match non è exact, quindi una seconda find-part con una variante della ricerca (es. solo sinonimi del context) è un intervento piccolo; da misurare con questo harness.
- Allargare il campione (le differenze tra v1/v2/v3 e hints sono nel rumore di ±3 casi).
