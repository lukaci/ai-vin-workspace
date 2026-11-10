# TODO

Ogni task: `**[STATO]** Titolo #tag`, sotto il testo (body). Nelle sezioni per priorità i task aperti, prima quelli `[DOING]`; un task completato passa a `**[DONE]**` e si sposta in fondo, nella sezione DONE.

- Stato:
  - `[TODO:HI]` priorità alta
  - `[TODO:MID]` priorità normale
  - `[TODO:LOW]` priorità bassa
  - `[TODO:EVAL]` da valutare
  - `[TODO:VERIFY]` da verificare
  - `[TODO:IMPROVE]` miglioramento da analizzare
  - `[DOING]` in corso: nel body branch, commit e riferimenti per riprendere
  - `[DONE]` completato
- Tag (capitolo di provenienza):
  - `#runtime` configurazione/runtime, non nel codice
  - `#general` generale
  - `#prasco` nuove richieste Prasco
  - `#low-pri` bassa priorità

## HI

**[TODO:HI]** Regole del file delle cache\
per i brand composti (es. 'alfa romeo') il meccanismo/naming convention che converte un nome file nel path con folder, non crea raggruppamenti per folder VIN

**[TODO:HI]** Dismissione gpt-4.1 e benchmark di non regressione #general\
gpt-4.1 sarà dismesso a gennaio, capire con 'luna' come performa, e valutare anche le decisions api
 - preparare un benchmark di non regressione buono, che valuti rapidità, numero di chiamate a provider, qualità

## MID

**[DOING]** Ottimizzazione non-exact Prasco (file Strategie-dizionari-non-exact) #prasco\
migliorare l'identificazione sui casi non exact del test del collega (`Strategie-dizionari-non-exact-11-10.xlsx`) con interventi non strutturali: prompt di normalizzazione, hints
 - aggiornato il 2026-10-23
 - branch ai-vin-service: `feat/prasco-non-exact-normalization`, commit `53a3989` (53a3989199b58be7e792dd6789990f6b841d1172), da pushare
   - prompt di normalizzazione esterno `AIVIN_NORMALIZE_PROMPT_FILE` (S3 o path locale, `{{partName}}`, fallback built-in)
   - hints cercati sul nome normalizzato, duplicati rimossi
   - slax-partslink: 404 su `/units` salta solo quella tavola
   - harness `test-cli/eval-find-part-sample.ts` (campione con OE noto, cache S3 in sola lettura)
 - diario, configurazioni e run: `experiments/prasco-non-exact/` (`JOURNAL.md`: sezione "Come riprendere"; `HANDOFF.md`: contesto e decisioni)
 - risultato: tavola giusta 55.8% → 59.7%, pezzo esatto 53.2% → 59.7% (77 casi, escluse Kia/Hyundai); limite principale: la navigazione non visita la tavola giusta (21 fallimenti su 31)
 - da fare:
   - push del branch, merge in `dev`
   - deploy su S3: `configs/normalize-prompt-v3.md` (es. `hints/normalize-prompt.md`) + `AIVIN_NORMALIZE_PROMPT_FILE`; backup di `hints/hints.json` e upload di `configs/hints-c2.json`
   - prossimo passo proposto: dizionario per marca (descrizione → tavola) ricavato dai casi exact in cache S3, misurato con l'harness
 - problemi del provider emersi (`experiments/prasco-non-exact/provider-issues-kia-hyundai-citroen.md`): Kia tavole troncate, Hyundai PNC al posto del codice ricambio, Citroen/Peugeot codici tavola cambiati (cache S3 da invalidare), 429 senza retry (vedi "Gestione dei 429")
 - collegati: "Tavola negli hints", "Categorie assemblygroup dichiarate", "Suggestions sospette negli excel di TEO", "Dismissione gpt-4.1 e benchmark di non regressione" (l'harness è riusabile)

**[DOING]** Cross Prasco SKU → OE #prasco\
utilizzare le 'cross' di Prasco, il tracciato è un csv/excel  SKU -> OE -> description
 - modificare API, per supportare quando la chiamata viene fatta passando part number esterni oppure OE
 - considerazione: le supersessions degli OE ci 'possono' essere, se nel file ci sono più righe con stesso SKU e diversi OE
 - restituiamo come ora, ci deve essere sia codice Prasco che OE
 - il tracciato è stato fornito, 
    item;oe;description
    170002;2GM941661C;INDICATORE DI DIREZIONE SINISTRO-LED
    1A8001149011;111941039;FARO VW
    1AH007600151;8628398;PROIETTORE SX
    ...
 - creare API per caricare il file con il tracciato
 - LOG delle richieste -> export periodico delle richieste, con descrizione, SKU Prasco originale, OE trovato -> SKU Prasco trovato
 - supportare Prasco: richiedono di passarci i cataloghi, dove c'è
 - aggiornato il 2026-11-08: upload e applicability per SKU fatti, mancano log/export delle richieste e cataloghi
 - ai-vin-app: sviluppo su `claude/serene-bell-9z1i42` (da `feat/dev/prasco` con `main` mergiato dentro, merge `f19e04f`), mergiato in `feat/dev/prasco` (`34c588e`), release 0.8.0 (`ef4cb51`; tag `v0.8.0` da pushare a mano)
   - `POST /api/v1/cross/upload` (multipart `file`): csv/txt/xlsx, colonne riconosciute per nome header (alias in `server/lib/cross/parse.ts`), codici normalizzati, convertito nell'xlsx letto all'avvio e salvato su `AIVIN_CROSS_FILE_PATH` (deve essere `.xlsx`); upload e file precedente archiviati in `cross-uploads/` accanto; sqlite locale sostituito a caldo
   - `POST /api/v1/part-applicability/cross` (+ `/async/part-applicability/cross`): API separata da `/part-applicability`; per riga SKU (`part_number` + `part_numbers`, union degli OE) oppure OE con `part_number_type: oe`; risposta con `cross` (`skus`: `{ sku, part_numbers }` per SKU richiesto, vuoto se non trovato; `part_numbers`: OE controllati; `description`), `cross.skus` con la stessa forma su `matched_part` e sulle parti delle suggestions; `metadata` di richiesta e righe restituiti com'erano (come in `feat/dev/prasco`); `/part-applicability` vecchia senza cross
   - senza descrizione in input, si usa la descrizione del tracciato; SKU non trovato e senza descrizione: riga non cercata (`cross.part_numbers` vuoto e niente `cross.description`)
   - OpenAPI `1.0.0-draft-14`, CHANGELOG 0.8.0
 - da verificare: con S3 reale (scrittura sul bucket e archivio), tracciato completo Prasco (dimensione, tempi di conversione)
 - ricerca solo per descrizione (SKU non nel tracciato, nessun OE): `ai-vin-service` rispondeva 404 senza OE, quindi niente suggestions; corretto in ai-vin-service 0.8.1 (`568d8ca`, release `e09fe5e`, in `dev` e `main`; tag `v0.8.1` da pushare a mano), da deployare; vale anche per la `/part-applicability` vecchia chiamata con la sola descrizione
 - nel merge di `main` in `feat/dev/prasco`: tenuti `metadata` della `/part-applicability` e docs su `/api/docs`; tutti gli endpoint riattivati (su `feat/dev/prasco` erano commentati); `feat/dev/prasco` era indietro di 21 commit (v0.2 → v0.7, compreso il breaking `AIVIN_USE_PLATE`)
 - collegati: "Cross: sincronizzazione tra istanze", "Cross nelle API di search e nelle altre API"

**[TODO:MID]** Prasco: disattivare le targhe #runtime\
prasco: disattivare le targhe

**[TODO:MID]** Prasco: disattivare assemblygroups #runtime\
prasco: disattivare assemblygroups

**[TODO:MID]** Categorie assemblygroup dichiarate esplicitamente #general\
dichiarare esplicitamente le categorie dell'assemblygroup passate ad ai-vin-service (part-list, tool assiemi), invece di concatenarle alla descrizione della parte
 - oggi l'espansione le tratta in modo non uniforme: scarta `bodywork`/`lighting`, tiene `service`/`thermal` nel nome normalizzato (ranker e chiave cache)
 - passarle come contesto con l'etichetta giusta (es. "Part category") a espansione e ranker, fuori dal nome normalizzato; decidere se entrano nella chiave cache
 - insieme agli hints: tavola, brand, attributi veicolo
 - benchmark prima/dopo, in particolare sui casi `SERVICE` (es. `REAR BRAKE PADS` BMW: kit "value line" vs unit freno posteriore)

**[TODO:MID]** Tavola negli hints #general\
possibilità di utilizzare la tavola negli hints
 - si ricongiunge con la possibilità di utilizzare anche il brand, attributi veicolo, codice della tavola
 - negli hints, ed anche in fase di normalizzazione del nome della parte

**[TODO:MID]** Nuova OpenAPI slax-partslink con errori e 429 #general\
importare nuovo openapi slax-partslink, con censiti errori e 429

**[TODO:MID]** Gestione dei 429 con passaggio al provider successivo #general\
gestione dei 429, se ne becco uno, vado al prossimo provider censito

**[TODO:MID]** Cross: sincronizzazione tra istanze #prasco\
debito tecnico: l'upload delle cross aggiorna il sqlite solo dell'istanza che riceve la chiamata (senza reload completo); con più istanze di ai-vin-app le altre restano col dato vecchio fino al loro reload
 - opzioni: reload periodico se cambia l'oggetto sul bucket (ETag/LastModified), notifica tra istanze, oppure storage condiviso al posto del sqlite locale

**[TODO:MID]** Cross: validazione e limiti dell'upload #prasco\
rafforzare la validazione del tracciato in `POST /api/v1/cross/upload` (ai-vin-app, `server/lib/cross/parse.ts`, `cross.ts`), prima che sostituisca le cross in uso
 - oggi c'è: dimensione massima 100MB (413), estensione (csv/txt/xlsx/xls), header con colonne SKU e OE (alias), righe senza SKU o OE e coppie duplicate scartate e contate, 400 se non resta nessuna riga valida
 - manca:
   - cap sul numero di righe (memoria/tempi della conversione in xlsx e del sqlite, misurare sul tracciato completo Prasco)
   - soglia sulle righe scartate (es. oltre il 5-10% senza SKU/OE → rifiuto, oggi passa in silenzio)
   - controllo sul calo rispetto alle cross in uso (es. file nuovo con molte meno righe/SKU del precedente → rifiuto o conferma esplicita, per non svuotare le cross con un file troncato)
   - formato dei codici: lunghezza massima, caratteri ammessi; lunghezza massima della descrizione
   - più OE "uguali" per lo stesso SKU dopo la normalizzazione (es. `A2088200161` / `2088200161`): oggi restano entrambi
   - eventuale modalità di sola verifica (dry run) che restituisce le statistiche senza salvare
 - collegati: "Cross Prasco SKU → OE"

**[TODO:MID]** Cross nelle API di search e nelle altre API #prasco\
dopo l'applicability, gestire SKU/OE delle cross anche nelle API di search (part-search, ...) e nelle altre API che ricevono o restituiscono codici ricambio

**[TODO:MID]** Licenze con abilitazione per singola API #prasco\
gestione licenze, con granularità abilitazione singole API
 - capire come gestire i front-end e le licenze per le filiali
 - licenze che funzionano con API key e metadati (da verificare in segnalazioni Pérasco, ma era ok, oggetto composto, secondo livello)
 - counter delle UdV secondo quanto scritto a contratto

**[TODO:MID]** Pannello di amministrazione #prasco\
pannello di amministrazione, gestione licenze, export schedulate e scaricamento/visualizzazione di esse, elenco caricamenti/scaricamenti...

**[TODO:MID]** Hints con libreria portabile #prasco\
gestire gli hints non più con libreria nativa ma con qualcosa di più portabile

## EVAL / VERIFY / IMPROVE

**[TODO:EVAL]** Pool di provider di fallback #general\
gestire prvider di fallback, che non è quelli round robin..ma è un altro 'pool' (o un array di pool di precedenza) -> trovarre la soluzione per governare le regole con cui chiamare un provider (classe di provider) e/o fallbackare su tri

**[TODO:EVAL]** Nuovo provider VINSEARCH di fallback #general\
creare nuovo provider, 'VINSEARCH' da usare come FALLBA (per test/training) tipo YQ ma free, intanto vi dico che sia https://vinsearch.elit.cz/en/search/vin/ZFA16900000747893 che https://vinsearch.rhiag.com/en/search/vin/ZFA16900000747893 interrogano diretti senza login laximo

**[TODO:VERIFY]** Utilità della cache bucket entry #general\
verificare il funzionamento della cache 'bucket entry', ora come ora non serve a molto

**[TODO:IMPROVE]** Suggestions sospette negli excel di TEO #prasco\
vedere gli excel csv di TEO
 - nei sospetti, ci sono le suggestions
 - sembra che sia sospette in quanto non c'entrano una mazza
 - effettivamente per come è fatto: quando c'è una exact match, restituisce la BAG di UNIT valutate fino a quel momento, senza andare a verificare altre cose...
  quindi il risultato è fuorviante (infatti, la 'c' dovrebbe dare suggestions solo se non è exact...)

## LOW

Nessun task aperto.

## DONE

**[DONE]** plate-to-vin chiamata per YV1XZ10C5M2000000 #general\
viene chiamata la plate-to-vin, per questo: YV1XZ10C5M2000000, è corretto? anche se nella part applicability?

**[DONE]** Log delle login #general\
loggare le login

**[DONE]** Applicability con description vuota #general\
nella applicability, se la description è vuota, bisogna troncare subito ed evitare di fare una search dei compatibili...

**[DONE]** Normalizzazione dei log #general\
in generare, normalizzare bene i logs

**[DONE]** Rimozione part_position dalle chiamate ad ai-vin-service #general\
rimuovere la part position dalle chiamate ai-vin-service.. crea un po' di entropia, e poi non è preciso, non ha molto senso
 - passo unico: tutto ciò che oggi va in `part_position` viene concatenato in fondo alla descrizione della parte (`part`)
   - posizione vera: l'espansione la normalizza già in "nome - posizione"
   - categorie dell'assemblygroup (part-list, tool assiemi): concatenate con virgola, senza trattino (es. "headlamp, bodywork, lighting"), per non occupare lo slot della posizione
     - verificato: l'espansione non è uniforme, scarta `bodywork`/`lighting` ma tiene `service`/`thermal` nel nome normalizzato (quindi nel ranker e nella chiave cache)
   - service: `part_position` rimossa da tipi, funzioni, prompt (espansione, ranker, eval) e chiave cache; in ingresso HTTP resta accettata come deprecata e unita a `part`
   - cache bucket ricerche (find-part/find-unit): si riparte da chiave pulita `searches_<provider>_<ns>_<brand>_<part>` (niente suffisso posizione, niente `_` finale), nessuna migrazione
   - app: tool chat FindPartTool e v1 `part-search` uniscono la posizione a `part`; `part_position` resta nell'OpenAPI pubblica come deprecata
   - accettato: piccola variazione possibile dell'espansione/ranker (LLM non deterministico)
 - non regressione (17 casi find-part/find-unit, VW + BMW, LLM reale, prima/dopo x2): compatibile; unica differenza di comportamento su `REAR BRAKE PADS` + `SERVICE` (BMW), dal kit "value line" alla unit del freno posteriore
 - dopo: vedi TODO categorie dichiarate

**[DONE]** Code nelle risposte delle API applicability #general\
aggiungere il 'code' nelle return delle API tipo applicability

**[DONE]** Mappare le altre API, non solo applicability #general\
sul ai-vin- mappare le varie API, non solo applicability

**[DONE]** Applicability: prima tavola valutata quando match none #general\
APPLICABILITY, RESTITUIRE tavola, quando è match none, la prima tavola che ha valutato e non l'ultima come fa ora

**[DONE]** Mapping WMI per i VIN unknown #general\
inserire iv 'wmi' mapping per i vin in 'unknowm' e migrare la cache

**[DONE]** Semantica di code_path e code tra provider ad albero e diretti #low-pri\
Valuta le differenze di semantica dei campi code_path e code per gli algoritmi ad albero e diretti (come yq): l'algoritmo ad albero, nel code path, contiene tutto il path full compreso il code della tavola finale, mentre su yq tutto tranne il codice della unit. Questo funziona fintanto che tutti i provider non ad albero rispettano questa convenzione... valutare se unificare, bisogna fare dei test di non regressione
