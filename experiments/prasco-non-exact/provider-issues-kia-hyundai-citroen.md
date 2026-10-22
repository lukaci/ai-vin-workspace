# slax-partslink: problemi sulle tavole Kia, Hyundai e Citroen

Provider: slax-partslink (`$SLAX_PARTSLINK_HOST`, nel nostro ambiente di test `https://plink2.aivin.it`). Chiamate eseguite il 2026-10-18; la API key è sostituita da `$SLAX_PARTSLINK_API_KEY`.
Nelle risposte di `/units` il campo `images` (base64) è stato rimosso e le liste lunghe sono ridotte alle righe rilevanti (per Citroen alle prime 3: lì conta lo status code), con il totale indicato.

Riepilogo:

| marca | VIN | problema | effetto |
|---|---|---|---|
| Kia | `KNABE511AHT349990` | `/units` restituisce 1-2 righe per tavola; mancano pezzi che `/search` colloca proprio in quella tavola | il pezzo non si trova navigando il catalogo |
| Hyundai | `KMHAB51GP3U290004` | in `/units` il campo `number` contiene il PNC (es. `82404`) invece del codice ricambio (`8240402010`) | la tavola e il pezzo sono giusti, ma il confronto con il codice OE fallisce |
| Citroen | `VF7JM8HZC97419102` | il formato dei codici tavola è cambiato (`Illustration 011007 7 433 01A` → `011007 7 433 01A`); i codici vecchi danno 404 su `/units` | i livelli dell'albero salvati in cache prima del cambio portano a 404 |

## Kia — VIN `KNABE511AHT349990`: tavole troncate

Schema: `/search` con il codice OE trova il pezzo e indica la tavola (`attributes.illustration`, nel formato `<main_group> | <visible_block>`); `/units` sulla stessa tavola non contiene quel pezzo e restituisce solo una o due righe.

### Caso 1 — calotta retrovisore sinistro (OE `876131Y100`)

**1a. Ricerca per codice OE**

```bash
curl -s -X POST "$SLAX_PARTSLINK_HOST/search" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $SLAX_PARTSLINK_API_KEY" \
  -d '{"vin": "KNABE511AHT349990", "ricerca": "876131Y100"}'
```

Request body:

```json
{
  "vin": "KNABE511AHT349990",
  "ricerca": "876131Y100"
}
```

Response (HTTP 200):

```json
{
  "vin": "KNABE511AHT349990",
  "search": "876131Y100",
  "units": [
    {
      "name": "SCALP-O/S RR VIEW MIRROR,LH",
      "number": "876131Y100",
      "attributes": {
        "illustration": "TR | 86-876 .1"
      },
      "key": "876131Y100|TR | 86-876 .1"
    }
  ]
}
```

Il pezzo `SCALP-O/S RR VIEW MIRROR,LH` sta nella tavola `TR | 86-876 .1`.

**1b. Tavola indicata dalla ricerca**

```bash
curl -s -X POST "$SLAX_PARTSLINK_HOST/units" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $SLAX_PARTSLINK_API_KEY" \
  -d '{"vin": "KNABE511AHT349990", "main_group": "TR", "visible_block": "86-876 .1"}'
```

Request body:

```json
{
  "vin": "KNABE511AHT349990",
  "main_group": "TR",
  "visible_block": "86-876 .1"
}
```

Response (HTTP 200):

```json
{
  "vin": "KNABE511AHT349990",
  "unit": {
    "name": "",
    "code": "86-876 .1",
    "tags": "",
    "parts": [
      {
        "name": "NUT-FLANGE",
        "number": "13395 06001",
        "area_code": "1339CC",
        "attributes": {
          "pnc": "1339CC",
          "qty": "3",
          "pezzo": "3",
          "production_date": "Jan 1, 2015 - Jan 13, 2017",
          "restriction": "DRIVE TYPE: DRIVE TYPE - LHD , COLOR - BODY COLOR , PASS'S SIDE - LEVER-CONV , not ELECTRIC FOLD'G CONTROL , not SIDE REPEATER LAMP (O/S MRR) , not O/S RR VIEW ..."
        }
      },
      {
        "name": "NUT-FLANGE",
        "number": "13395 06001",
        "area_code": "1339CC",
        "attributes": {
          "pnc": "1339CC",
          "qty": "3",
          "pezzo": "3",
          "production_date": "Jan 1, 2015 - ...",
          "restriction": "DRIVE TYPE: DRIVE TYPE - LHD , COLOR - BODY COLOR , PASS'S SIDE - LEVER-CONV or COLOR - BODY COLOR , PASS'S SIDE - LEVER-CONV or DRIVE TYPE: DRIVE TYPE - LHD , ..."
        }
      }
    ]
  }
}
```

**Atteso**: la tavola dello specchio esterno (`MIRROR-OUTSIDE REAR VIEW`) con calotta, vetro, specchio completo... e il pezzo `876131Y100`. **Ottenuto**: 2 righe, entrambe `NUT-FLANGE`.

### Caso 2 — condensatore (OE `976061Y000`)

**2a. Ricerca per codice OE**

```bash
curl -s -X POST "$SLAX_PARTSLINK_HOST/search" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $SLAX_PARTSLINK_API_KEY" \
  -d '{"vin": "KNABE511AHT349990", "ricerca": "976061Y000"}'
```

Request body:

```json
{
  "vin": "KNABE511AHT349990",
  "ricerca": "976061Y000"
}
```

Response (HTTP 200):

```json
{
  "vin": "KNABE511AHT349990",
  "search": "976061Y000",
  "units": [
    {
      "name": "CONDENSER ASSY-COOLER",
      "number": "976061Y000",
      "attributes": {
        "illustration": "EN | 25-253 .1"
      },
      "key": "976061Y000|EN | 25-253 .1"
    },
    {
      "name": "CONDENSER ASSY-COOLER",
      "number": "976061Y000",
      "attributes": {
        "illustration": "EN | 25-253 .2"
      },
      "key": "976061Y000|EN | 25-253 .2"
    }
  ]
}
```

Il pezzo `CONDENSER ASSY-COOLER` sta nelle tavole `EN | 25-253 .1` e `.2`.

**2b. Tavola indicata dalla ricerca**

```bash
curl -s -X POST "$SLAX_PARTSLINK_HOST/units" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $SLAX_PARTSLINK_API_KEY" \
  -d '{"vin": "KNABE511AHT349990", "main_group": "EN", "visible_block": "25-253 .1"}'
```

Request body:

```json
{
  "vin": "KNABE511AHT349990",
  "main_group": "EN",
  "visible_block": "25-253 .1"
}
```

Response (HTTP 200):

```json
{
  "vin": "KNABE511AHT349990",
  "unit": {
    "name": "",
    "code": "25-253 .1",
    "tags": "",
    "parts": [
      {
        "name": "SCREW-TAPPING",
        "number": "10188 05163",
        "area_code": "1018AD",
        "attributes": {
          "pnc": "1018AD",
          "qty": "24",
          "pezzo": "24",
          "production_date": "May 23, 2016 - ...",
          "restriction": "FR COOLER - MANUAL A/CON"
        }
      }
    ]
  }
}
```

**Atteso**: la tavola `ENGINE COOLING SYSTEM` con radiatore, condensatore, ventola... e il pezzo `976061Y000`. **Ottenuto**: 1 riga, `SCREW-TAPPING`.

### Caso 3 — paraurti anteriore (tavola `FRONT BUMPER`)

**3. Tavola del paraurti anteriore**

```bash
curl -s -X POST "$SLAX_PARTSLINK_HOST/units" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $SLAX_PARTSLINK_API_KEY" \
  -d '{"vin": "KNABE511AHT349990", "main_group": "TR", "visible_block": "86-865 .1"}'
```

Request body:

```json
{
  "vin": "KNABE511AHT349990",
  "main_group": "TR",
  "visible_block": "86-865 .1"
}
```

Response (HTTP 200):

```json
{
  "vin": "KNABE511AHT349990",
  "unit": {
    "name": "",
    "code": "86-865 .1",
    "tags": "",
    "parts": [
      {
        "name": "BULB-HALOGEN",
        "number": "18647 27009",
        "area_code": "18647",
        "attributes": {
          "pnc": "18647",
          "qty": "1",
          "pezzo": "1",
          "production_date": "Jan 1, 2015 - ...",
          "restriction": "CONVENTIONAL - PROJECTION"
        }
      }
    ]
  }
}
```

La tavola `TR / 86-865 .1` si chiama `FRONT BUMPER` nel livello `TR` del veicolo. **Atteso**: copertura paraurti, rinforzo, griglie, staffe... **Ottenuto**: 1 riga, `BULB-HALOGEN`. Nota: in questo caso `/search` sull'OE Prasco del paraurti (`865111Y300`) risponde `not_found`, quindi non c'è un riscontro dalla ricerca come nei casi 1 e 2.

Osservazione: le righe restituite hanno `attributes.restriction` (vincoli di applicabilità). Un'ipotesi da verificare lato provider è un filtro di applicabilità sul VIN che scarta quasi tutte le righe.

## Hyundai — VIN `KMHAB51GP3U290004`: PNC al posto del codice ricambio

Schema: `/search` con il codice OE trova il pezzo con `number` = codice ricambio; `/units` sulla stessa tavola contiene il pezzo (stesso nome), ma con `number` = PNC (uguale ad `area_code` e `attributes.pnc`), quindi il codice ricambio non compare.

### Caso 1 — alzacristallo anteriore destro elettrico (OE `8240402010`)

**1a. Ricerca per codice OE**

```bash
curl -s -X POST "$SLAX_PARTSLINK_HOST/search" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $SLAX_PARTSLINK_API_KEY" \
  -d '{"vin": "KMHAB51GP3U290004", "ricerca": "8240402010"}'
```

Request body:

```json
{
  "vin": "KMHAB51GP3U290004",
  "ricerca": "8240402010"
}
```

Response (HTTP 200):

```json
{
  "vin": "KMHAB51GP3U290004",
  "search": "8240402010",
  "units": [
    {
      "name": "REGULATOR ASSY-FR DR P/WDO RH",
      "number": "8240402010",
      "attributes": {
        "illustration": "TR | 81-824 .1"
      },
      "key": "8240402010|TR | 81-824 .1"
    }
  ]
}
```

**1b. Tavola indicata dalla ricerca**

```bash
curl -s -X POST "$SLAX_PARTSLINK_HOST/units" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $SLAX_PARTSLINK_API_KEY" \
  -d '{"vin": "KMHAB51GP3U290004", "main_group": "TR", "visible_block": "81-824 .1"}'
```

Request body:

```json
{
  "vin": "KMHAB51GP3U290004",
  "main_group": "TR",
  "visible_block": "81-824 .1"
}
```

Response (HTTP 200):

```json
{
  "vin": "KMHAB51GP3U290004",
  "unit": {
    "name": "",
    "code": "81-824 .1",
    "tags": "",
    "parts": [
      {
        "name": "REGULATOR ASSY-FR DR WDO LH",
        "number": "82401",
        "area_code": "82401",
        "attributes": {
          "pnc": "82401"
        }
      },
      {
        "name": "REGULATOR ASSY-FR DR WDO RH",
        "number": "82402",
        "area_code": "82402",
        "attributes": {
          "pnc": "82402"
        }
      },
      {
        "name": "REGULATOR ASSY-FR DR P/WDO LH",
        "number": "82403",
        "area_code": "82403",
        "attributes": {
          "pnc": "82403"
        }
      },
      {
        "name": "REGULATOR ASSY-FR DR P/WDO RH",
        "number": "82404",
        "area_code": "82404",
        "attributes": {
          "pnc": "82404"
        }
      },
      {
        "name": "HANDLE ASSY-DOOR WINDOW REGULATOR",
        "number": "82630",
        "area_code": "82630",
        "attributes": {
          "pnc": "82630"
        }
      },
      {
        "name": "CLIP-DOOR REGULATOR HANDLE",
        "number": "82643B",
        "area_code": "82643B",
        "attributes": {
          "pnc": "82643B"
        }
      },
      {
        "name": "MOTOR ASSY-POWER WINDOW REG,LH",
        "number": "98800",
        "area_code": "98800",
        "attributes": {
          "pnc": "98800"
        }
      },
      {
        "name": "MOTOR ASSY-POWER WINDOW REG,RH",
        "number": "98900",
        "area_code": "98900",
        "attributes": {
          "pnc": "98900"
        }
      },
      "... altre 9 righe omesse (totale 17)"
    ]
  }
}
```

**Atteso**: `REGULATOR ASSY-FR DR P/WDO RH` con `number` = `8240402010` (e il motore `MOTOR ASSY-POWER WINDOW REG,RH` = `9882002100`, che `/search` colloca nella stessa tavola). **Ottenuto**: `number` = `82404` e `98900`, cioè i PNC.

### Caso 2 — radiatore (OE `2531002100`)

**2a. Ricerca per codice OE**

```bash
curl -s -X POST "$SLAX_PARTSLINK_HOST/search" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $SLAX_PARTSLINK_API_KEY" \
  -d '{"vin": "KMHAB51GP3U290004", "ricerca": "2531002100"}'
```

Request body:

```json
{
  "vin": "KMHAB51GP3U290004",
  "ricerca": "2531002100"
}
```

Response (HTTP 200):

```json
{
  "vin": "KMHAB51GP3U290004",
  "search": "2531002100",
  "units": [
    {
      "name": "RADIATOR ASSY",
      "number": "2531002100",
      "attributes": {
        "illustration": "EN | 25-253 .1"
      },
      "key": "2531002100|EN | 25-253 .1"
    }
  ]
}
```

**2b. Tavola indicata dalla ricerca**

```bash
curl -s -X POST "$SLAX_PARTSLINK_HOST/units" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $SLAX_PARTSLINK_API_KEY" \
  -d '{"vin": "KMHAB51GP3U290004", "main_group": "EN", "visible_block": "25-253 .1"}'
```

Request body:

```json
{
  "vin": "KMHAB51GP3U290004",
  "main_group": "EN",
  "visible_block": "25-253 .1"
}
```

Response (HTTP 200):

```json
{
  "vin": "KMHAB51GP3U290004",
  "unit": {
    "name": "",
    "code": "25-253 .1",
    "tags": "",
    "parts": [
      {
        "name": "FAN-COOLING",
        "number": "25231",
        "area_code": "25231",
        "attributes": {
          "pnc": "25231"
        }
      },
      {
        "name": "RADIATOR ASSY",
        "number": "25310",
        "area_code": "25310",
        "attributes": {
          "pnc": "25310"
        }
      },
      {
        "name": "SHROUD-RADIATOR",
        "number": "25350",
        "area_code": "25350",
        "attributes": {
          "pnc": "25350"
        }
      },
      "... altre 21 righe omesse (totale 24)"
    ]
  }
}
```

**Atteso**: `RADIATOR ASSY` con `number` = `2531002100`. **Ottenuto**: `number` = `25310` (PNC); lo stesso per tutte le 24 righe della tavola.

Nota: per altri VIN Hyundai (e per Kia) le righe hanno il codice ricambio corretto in `number` e il PNC solo in `area_code`/`attributes.pnc`: il problema riguarda solo alcuni veicoli.

## Citroen — VIN `VF7JM8HZC97419102`: codici tavola cambiati, i vecchi danno 404

Schema: il livello `1 | 0` salvato in cache in passato ha codici `Illustration <codice>` e nomi `Description <nome>`; oggi `/paths` restituisce `<codice>` e `<nome>`. `/units` con il codice vecchio, che in passato funzionava, oggi risponde 404; con il codice nuovo risponde 200. Chi ha in cache i livelli vecchi (come la nostra cache S3) non riesce più a leggere le tavole.

### Livello `1 | 0`: prima e adesso

**Prima**

Risposta salvata in cache S3 (`slax-partslink_citroen_vf7jm8hzc97419102_1_7c_0_level`), ottenuta in passato dallo stesso provider:

```json
{
  "vin": "VF7JM8HZC97419102",
  "partial_paths": [
    {
      "code_path": [
        "Illustration 011006 6 175 01A"
      ],
      "name_path": [
        "Description FRONT BUMPER"
      ],
      "is_leaf": true
    },
    {
      "code_path": [
        "Illustration 011007 7 410 10A"
      ],
      "name_path": [
        "Description FRONT FRAME"
      ],
      "is_leaf": true
    },
    {
      "code_path": [
        "Illustration 011007 7 435 01A"
      ],
      "name_path": [
        "Description FRONT WING"
      ],
      "is_leaf": true
    },
    {
      "code_path": [
        "Illustration 011007 8 520 01A"
      ],
      "name_path": [
        "Description BADGES - ADSHESIVE DECALS"
      ],
      "is_leaf": true
    },
    {
      "code_path": [
        "Illustration 011007 7 433 01A"
      ],
      "name_path": [
        "Description BONNET"
      ],
      "is_leaf": true
    },
    "... altri 7 elementi"
  ]
}
```

**Adesso**

```bash
curl -s -X POST "$SLAX_PARTSLINK_HOST/paths" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $SLAX_PARTSLINK_API_KEY" \
  -d '{"vin": "VF7JM8HZC97419102", "main_group": "1 | 0"}'
```

Request body:

```json
{
  "vin": "VF7JM8HZC97419102",
  "main_group": "1 | 0"
}
```

Response (HTTP 200):

```json
{
  "vin": "VF7JM8HZC97419102",
  "partial_paths": [
    {
      "code_path": [
        "011006 6 175 01A"
      ],
      "name_path": [
        "FRONT BUMPER"
      ],
      "is_leaf": true
    },
    {
      "code_path": [
        "011007 7 410 10A"
      ],
      "name_path": [
        "FRONT FRAME"
      ],
      "is_leaf": true
    },
    {
      "code_path": [
        "011007 7 435 01A"
      ],
      "name_path": [
        "FRONT WING"
      ],
      "is_leaf": true
    },
    {
      "code_path": [
        "011007 8 520 01A"
      ],
      "name_path": [
        "BADGES - ADSHESIVE DECALS"
      ],
      "is_leaf": true
    },
    {
      "code_path": [
        "011007 7 433 01A"
      ],
      "name_path": [
        "BONNET"
      ],
      "is_leaf": true
    },
    "... altri 7 elementi"
  ]
}
```

### Caso 1 — cofano (`011007 7 433 01A`, `BONNET`)

**1a. Codice vecchio, preso dal livello in cache**

```bash
curl -s -X POST "$SLAX_PARTSLINK_HOST/units" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $SLAX_PARTSLINK_API_KEY" \
  -d '{"vin": "VF7JM8HZC97419102", "main_group": "1 | 0", "visible_block": "Illustration 011007 7 433 01A"}'
```

Request body:

```json
{
  "vin": "VF7JM8HZC97419102",
  "main_group": "1 | 0",
  "visible_block": "Illustration 011007 7 433 01A"
}
```

Response (HTTP 404):

```json
{
  "error": "Visible block 'Illustration 011007 7 433 01A' non trovato in illustrazioni React"
}
```

**1b. Codice nuovo**

```bash
curl -s -X POST "$SLAX_PARTSLINK_HOST/units" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $SLAX_PARTSLINK_API_KEY" \
  -d '{"vin": "VF7JM8HZC97419102", "main_group": "1 | 0", "visible_block": "011007 7 433 01A"}'
```

Request body:

```json
{
  "vin": "VF7JM8HZC97419102",
  "main_group": "1 | 0",
  "visible_block": "011007 7 433 01A"
}
```

Response (HTTP 200):

```json
{
  "vin": "VF7JM8HZC97419102",
  "unit": {
    "name": "011007 7 433 01A, BONNET",
    "code": "011007 7 433 01A",
    "parts": [
      {
        "name": "BONNET",
        "number": "7901 K2",
        "area_code": "01",
        "attributes": {
          "nota": "ASS",
          "quantità": "01",
          "pezzo": "7901 K2",
          "indicazione_modello": "2ND FRONT WINDOW 2007 ... - Date of production 02/Jul/2007 (OPR 11193)"
        }
      },
      {
        "name": "BONNET HINGE",
        "number": "7912 73",
        "area_code": "02",
        "attributes": {
          "nota": "Left",
          "quantità": "01",
          "pezzo": "7912 73",
          "indicazione_modello": ""
        }
      },
      {
        "name": "BONNET HINGE",
        "number": "7913 36",
        "area_code": "02",
        "attributes": {
          "nota": "Right",
          "quantità": "01",
          "pezzo": "7913 36",
          "indicazione_modello": ""
        }
      },
      "... altre 20 righe omesse (totale 23)"
    ]
  }
}
```

### Caso 2 — parafango anteriore (`011007 7 435 01A`, `FRONT WING`)

**2a. Prima: codice vecchio, risposta valida salvata in cache**

Risposta salvata in cache S3 (`slax-partslink_citroen_vf7jm8hzc97419102_1_7c_0_illustration_011007_7_435_01a_units`), ottenuta in passato dallo stesso provider:

```json
{
  "vin": "VF7JM8HZC97419102",
  "unit": {
    "name": "011007 7 435 01A, FRONT WING, A:IF NECESSARY FOR THE EARTH FIXINGS TAKE THE<BR>RETAINING PLATES PART NO 654724<BR>B:HOLE IN BODY SILL<BR>C:WITHOUT HOLE IN BODY SILL",
    "code": "Illustration 011007 7 435 01A",
    "parts": [
      {
        "name": "FRONT WING",
        "number": "7840 R1",
        "area_code": "01",
        "attributes": {
          "nota": "Left ASS",
          "quantità": "01",
          "pezzo": "7840 R1",
          "indicazione_modello": "Date of production 08/Nov/2004 (OPR 10227) - ... SEE C"
        }
      },
      {
        "name": "FRONT WING",
        "number": "7840 R2",
        "area_code": "01",
        "attributes": {
          "nota": "Left ASS",
          "quantità": "01",
          "pezzo": "7840 R2",
          "indicazione_modello": "Date of production 08/Nov/2004 (OPR 10227) - ... SEE B"
        }
      },
      {
        "name": "FRONT WING",
        "number": "7841 T4",
        "area_code": "01",
        "attributes": {
          "nota": "Right ASS",
          "quantità": "01",
          "pezzo": "7841 T4",
          "indicazione_modello": "ASSEMBLY WITH REAR SPOILER Date of production 08/Nov/2004 (OPR 10227) - ... not GT VTR / VTS"
        }
      },
      "... altre 30 righe omesse (totale 33)"
    ]
  }
}
```

In passato la stessa richiesta con `visible_block` = `Illustration 011007 7 435 01A` restituiva la tavola (33 righe, `code` = `Illustration 011007 7 435 01A`).

**2b. Adesso: stesso codice vecchio**

```bash
curl -s -X POST "$SLAX_PARTSLINK_HOST/units" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $SLAX_PARTSLINK_API_KEY" \
  -d '{"vin": "VF7JM8HZC97419102", "main_group": "1 | 0", "visible_block": "Illustration 011007 7 435 01A"}'
```

Request body:

```json
{
  "vin": "VF7JM8HZC97419102",
  "main_group": "1 | 0",
  "visible_block": "Illustration 011007 7 435 01A"
}
```

Response (HTTP 404):

```json
{
  "error": "Visible block 'Illustration 011007 7 435 01A' non trovato in illustrazioni React"
}
```

**2c. Adesso: codice nuovo**

```bash
curl -s -X POST "$SLAX_PARTSLINK_HOST/units" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $SLAX_PARTSLINK_API_KEY" \
  -d '{"vin": "VF7JM8HZC97419102", "main_group": "1 | 0", "visible_block": "011007 7 435 01A"}'
```

Request body:

```json
{
  "vin": "VF7JM8HZC97419102",
  "main_group": "1 | 0",
  "visible_block": "011007 7 435 01A"
}
```

Response (HTTP 200):

```json
{
  "vin": "VF7JM8HZC97419102",
  "unit": {
    "name": "011007 7 435 01A, FRONT WING, A:IF NECESSARY FOR THE EARTH FIXINGS TAKE THE<BR>RETAINING PLATES PART NO 654724<BR>B:HOLE IN BODY SILL<BR>C:WITHOUT HOLE IN BODY SILL",
    "code": "011007 7 435 01A",
    "parts": [
      {
        "name": "FRONT WING",
        "number": "7840 R1",
        "area_code": "01",
        "attributes": {
          "nota": "Left ASS",
          "quantità": "01",
          "pezzo": "7840 R1",
          "indicazione_modello": "Date of production 08/Nov/2004 (OPR 10227) - ... SEE C"
        }
      },
      {
        "name": "FRONT WING",
        "number": "7840 R2",
        "area_code": "01",
        "attributes": {
          "nota": "Left ASS",
          "quantità": "01",
          "pezzo": "7840 R2",
          "indicazione_modello": "Date of production 08/Nov/2004 (OPR 10227) - ... SEE B"
        }
      },
      {
        "name": "FRONT WING",
        "number": "7841 T4",
        "area_code": "01",
        "attributes": {
          "nota": "Right ASS",
          "quantità": "01",
          "pezzo": "7841 T4",
          "indicazione_modello": "ASSEMBLY WITH REAR SPOILER Date of production 08/Nov/2004 (OPR 10227) - ... not GT VTR / VTS"
        }
      },
      "... altre 30 righe omesse (totale 33)"
    ]
  }
}
```

Stesso contenuto di prima (33 righe); cambia solo `code` (`011007 7 435 01A`).

Possibili soluzioni: il provider accetta anche il formato vecchio (togliendo il prefisso `Illustration ` da `visible_block`), oppure invalidiamo la cache S3 di slax-partslink per `citroen`, `peugeot` e `ds` (livelli e tavole salvati prima del cambio).
