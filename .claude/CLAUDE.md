# Workspace

Il progetto riguarda una soluzione in ambito Automotive. Obiettivo è quello di identificare le parti di ricambio con richieste da un linguaggio più naturale, associando la richiesta ad un identificativo di veiclolo, che di base è il VIN, ma può essere anche una targa (se c'è un servizio di conversione VIN -> targa).
Le fonti dati sono i providers, che tipicamente permettono di navigare il catalogo: l'albero delle parti.
A seconda del brand, gli alberi delle parti possono cambiare di molto, all'interno dello stesso brand, magari cross modello, variano meno o non variano come 'contenuto logico', ma i nomi dei nodi dell'albero non sono sempre completamente uguali, hanno sempre qualche differenza a parità di posizione.

## ai-vin-service

Servizio di più basso livello, le cui API non vengono esposte esternamente. Fornisce le funzionalità di identificazione base.
Gestisce i provider internamente.
Utilizza dei sistemi di persistenza/caching dei dati.
Utilizza LLM per navigare il catalogo di un provider configurato.

## ai-vin-app

Servizio dedicato ad esporre esternamente le funzionalità, offre autenticazione, espone una app SPA e delle API di 
servizio più elevato o uguale a quelle di ai-vin-service.

# Convenzioni

- Linguaggio Typescript, tipicamente Bun come runtime, Hono per esporre api.
- Ove possibile utilizzare async/await
- Ove possibile utilizzare 'for comprehension' e trasformazioni di più alto livello (map, filter, flatMap, groupBy, ...), se non esistono creare eventuali altri operatori.
- Ove possibile preferire 'undefined' e non 'null' per informazioni opzionali
- Utilizzare in maniera preferibile ma ponderata, le interfacce
- Ove possibile, in caso di integrazione API REST di servizi esterni, basarsi sulle specifiche OpenApi e generare i client tramite toolchain/generatori noti/open-source
- Prevedere logging ragionevole a livello 'info' per le funzioni principali e non cicli stretti. 
- Considerare i log come fonte di 'diagnostica' per te, in modo da poter verificare il funzionamento e debuggare.
