# TODO

Ogni task: `**[STATO]** Titolo #tag`, sotto il testo (body). Un task completato resta nella sua sezione, con stato `**[DONE]**`.

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

**[TODO:MID]** Prasco: disattivare le targhe #runtime\
prasco: disattivare le targhe

**[TODO:MID]** Prasco: disattivare assemblygroups #runtime\
prasco: disattivare assemblygroups

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

**[DONE]** Code nelle risposte delle API applicability #general\
aggiungere il 'code' nelle return delle API tipo applicability

**[DONE]** Mappare le altre API, non solo applicability #general\
sul ai-vin- mappare le varie API, non solo applicability

**[DONE]** Applicability: prima tavola valutata quando match none #general\
APPLICABILITY, RESTITUIRE tavola, quando è match none, la prima tavola che ha valutato e non l'ultima come fa ora

**[TODO:MID]** Nuova OpenAPI slax-partslink con errori e 429 #general\
importare nuovo openapi slax-partslink, con censiti errori e 429

**[TODO:MID]** Gestione dei 429 con passaggio al provider successivo #general\
gestione dei 429, se ne becco uno, vado al prossimo provider censito

**[DONE]** Mapping WMI per i VIN unknown #general\
inserire iv 'wmi' mapping per i vin in 'unknowm' e migrare la cache

**[TODO:MID]** Cross Prasco SKU → OE #prasco\
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

**[DONE]** Semantica di code_path e code tra provider ad albero e diretti #low-pri\
Valuta le differenze di semantica dei campi code_path e code per gli algoritmi ad albero e diretti (come yq): l'algoritmo ad albero, nel code path, contiene tutto il path full compreso il code della tavola finale, mentre su yq tutto tranne il codice della unit. Questo funziona fintanto che tutti i provider non ad albero rispettano questa convenzione... valutare se unificare, bisogna fare dei test di non regressione
