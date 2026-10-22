# Handoff: ottimizzazione non-exact Prasco

Aggiornato il 2026-10-23. Sintesi della sessione di lavoro (18-23 ottobre 2026) per chi riprende: cosa è stato chiesto, cosa è stato deciso e perché, cosa resta aperto. I dettagli numerici sono in `JOURNAL.md`.

- Task: `TODO.md` del workspace, "[DOING] Ottimizzazione non-exact Prasco (file Strategie-dizionari-non-exact)".
- Codice: ai-vin-service, branch `feat/prasco-non-exact-normalization`, commit `53a3989` (53a3989199b58be7e792dd6789990f6b841d1172), da pushare.

## Richiesta e vincoli

- Usare i risultati del collega (`Strategie-dizionari-non-exact-11-10.xlsx`, nella root del workspace) per migliorare il sistema.
- Interventi **non strutturali**: ritoccare gli hints e il prompt di normalizzazione, eventualmente rendendo il prompt modificabile senza ricompilare (storage S3); segnalare a parte altri interventi rilevanti.
- Ciclo di ottimizzazione tracciato: ogni prova e ogni variazione registrata (`JOURNAL.md`).
- Niente test massivi: un campione rappresentativo.
- Agenti Sonnet o Haiku, con effort adeguato, per i lavori meno impegnativi, e poco parallelismo, per non esaurire i crediti.
- Il deploy su S3 lo fa l'utente (`.s3/` è montato in sola lettura); commit e push dell'utente, salvo richiesta esplicita.

## Cosa dice il file del collega

Applicability (VIN + descrizione Prasco + OE dal cross SKU→OE) su 4998 casi **non exact**, metrica "posto giusto" (tipo e lato del pezzo):
- solo descrizione 60.2%; ripetere la domanda 65.8%;
- aggiungere "frasi" alternative (nome AIVIN per marca+tipo, vinsearch): +5 l'una, la migliore per marca+tipo 71.6%, seconda chiamata con tutte le frasi solo sui falliti 73.7%.
- Lettura: il guadagno viene dal dare al navigatore la terminologia del catalogo. È la base del prompt con glossario e sinonimi.

## Come è stato misurato, e i limiti della misura

- **Ground truth oggettivo**: nella cache S3 ci sono le ricerche per codice OE (`/search`) fatte durante il test del collega; quelle riuscite dicono che l'OE esiste nel catalogo di quel VIN e in quale tavola. Campione di 88 casi (`data/sample-gt-v1.jsonl`), pesato verso marche e famiglie deboli.
- Misura: find-part con la sola descrizione, senza ricerca per codice e **senza cache dei percorsi** (`searches_*`); riuscito se la tavola scelta contiene uno qualsiasi degli OE dello SKU (il cross elenca anche le revisioni del codice).
- Limiti, tutti in difetto:
  - provider: Kia (tavole troncate) e Hyundai (PNC al posto del codice ricambio) danno falsi negativi, quindi sono esclusi dai numeri principali (77 casi); per Citroen/Peugeot vanno usati dati freschi (`--fresh-brands`);
  - codici sostitutivi non presenti nel cross;
  - rumore LLM: ±3 casi su 88 tra due run uguali;
  - è più severo del "posto giusto" del collega: ~12 dei 31 fallimenti finali sono tavole sorelle o varianti della tavola giusta;
  - popolazione diversa: casi in cui l'OE è nel catalogo, mentre quelli del collega sono i non exact. Per questo c'è una seconda verifica su 40 casi del suo foglio "Casi", giudicati da un agente su risultati anonimi (`data/judge-casi-*.json`).
  - In produzione la cache dei percorsi riusa i percorsi trovati in passato: i risultati reali dovrebbero essere più alti.

## Esito

- Prompt esterno con glossario Prasco IT→EN, posizioni italiane, riga 1 compatta (chiave cache) e sinonimi nella riga `context:`: da +4 a +7 punti, stabile su 5 run (tavola giusta 55.8% → 59.7%, pezzo esatto 53.2% → 59.7%). Sui casi del collega: 23/38 → 25/39 giusti, meno pezzi sbagliati, più risposte vuote (Fiat).
- Hints per marca (Kia/Hyundai, Fiat/Lancia/Alfa/Abarth, Mercedes, Nissan): neutri sul campione, utili su casi mirati.
- Perché resta intorno al 60%: in 21 fallimenti su 31 la tavola giusta **non viene mai visitata**. La navigazione scende livello per livello scegliendo i rami solo dai nomi, ne tiene pochi e non torna indietro; i cataloghi chiamano i pezzi in modo poco prevedibile (Ford `Cross Member Assy` per il rinforzo, `Bracket - Fog Lamp` per la cornice fendinebbia; Fiat `CROSSRAIL`; Mercedes `INTERNAL OPERATION`). Quando la tavola giusta viene aperta, il pezzo giusto viene quasi sempre scelto. Sinonimi aggiunti apposta (v3) non hanno recuperato questi casi: il limite è l'esplorazione, non il prompt.

## Problemi del provider (fuori dal perimetro prompt/hints)

Riproduzioni con curl in `provider-issues-kia-hyundai-citroen.md`:
- Kia: `/units` restituisce 1-2 righe per tavola (spiega l'1.3% di Kia nel file del collega);
- Hyundai: in `/units` `number` contiene il PNC (`82404`) invece del codice ricambio (`8240402010`);
- Citroen/Peugeot: codici tavola cambiati (`Illustration 011007 7 433 01A` → `011007 7 433 01A`), i vecchi danno 404; la cache S3 ha il formato vecchio, quindi succede anche in produzione finché non viene invalidata (`citroen`, `peugeot`, `ds`);
- 429 con poche richieste concorrenti, senza retry nel servizio.

## Aperto

1. Push del branch e merge in `dev`; deploy su S3 di `configs/normalize-prompt-v3.md` (+ `AIVIN_NORMALIZE_PROMPT_FILE`) e `configs/hints-c2.json` (con backup di `hints/hints.json`). Il cambio della riga 1 cambia le chiavi della cache dei percorsi.
2. Invalidare la cache S3 PSA; segnalare Kia e Hyundai al provider.
3. Prossimo passo proposto (non ancora iniziato): **dizionario per marca** "descrizione Prasco → tavola reale", ricavato dalle migliaia di casi exact già in cache S3 (`data/fts_searches.json` ne ha 5100 su 201 VIN), da usare come hints o come scorciatoia di navigazione; misurarlo con l'harness.
4. Alternative strutturali discusse, da valutare: esplorare più rami per livello e scegliere guardando anche le parti contenute nelle tavole; seconda passata in applicability quando il match non è exact (strategia F del collega); ricerca testuale del provider come scorciatoia, se esiste.

## File in questa cartella

- `JOURNAL.md`: diario dei cicli, sezione "Come riprendere" in cima.
- `configs/`: prompt v1-v3, hints c0 (= produzione al 2026-10-18), c1, c2.
- `data/`: ground truth (`fts_searches.json`, `cross.json`, script `build_gt.py`, `build_sample.py`), campioni, struttura catalogo delle marche deboli (`catalog-structure-weak-brands.md`), giudizio sui casi del collega.
- `runs/`: risultati per caso di ogni run (`c0`...`c4`, `casi-*`); `summarize.py` per riepiloghi e confronti.
- `provider-issues-kia-hyundai-citroen.md`: segnalazione per il provider.
