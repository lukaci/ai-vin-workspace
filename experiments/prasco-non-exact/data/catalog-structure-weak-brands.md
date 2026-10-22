# Catalog structure seen in cache (slax-partslink) - weak brands

Source: `.s3/cache/slax-partslink/<brand>/<vin>/*_vehicle` and `*_level` (units/parts barely used: cached units only hold one or two screws/bolts, not useful for placement).
Hierarchy depth in cache is always 2 levels: top group -> subgroup/unit (leaf). Leaves are what a navigator must pick.

## Kia (VIN u5ypc815afl748139; also u5ypc815afl684004 same shape)
Top groups: BODY (BO), CHASSIS (CH), ELECTRIC (EL), ENGINE (EN), TRANSMISSION (MI), TRIM (TR).

| Family | Path |
|---|---|
| Front bumper / rear bumper | TRIM > FRONT BUMPER (86-865) / REAR BUMPER (86-866) |
| Bumper reinforcement/beam | not seen (likely inside the bumper leaf) |
| Radiator grille | not seen in Kia VIN (Hyundai has TRIM > RADIATOR GRILLE 86-863); probably also TRIM, maybe inside FRONT BUMPER |
| Exterior mirror | TRIM > MIRROR-OUTSIDE REAR VIEW (86-876) |
| Headlamp | ELECTRIC > HEAD LAMP (91-921) |
| Tail lamp | ELECTRIC > REAR COMBINATION LAMP (91-924); BODY SIDE LAMP (91-923), HIGH MOUNTED STOP LAMP |
| Fog lamp | not seen (probably in HEAD LAMP / FRONT BUMPER) |
| Wheel arch liner | TRIM > WHEEL GAURD (86-868) [typo] |
| Engine undertray | ENGINE > UNDER COVER (29-291) |
| Door handle | not seen as own leaf: FRONT/REAR DOOR TRIM (81-823/833) or PANEL-FRONT DOOR (BODY); locks in TRIM > FRONT DOOR LOCKING |
| Fender / bonnet | BODY > FENDER & HOOD PANEL (60-660), FENDER APRON & RADIATOR SUPPORT PANEL (60-640); TRIM > HOOD TRIM (81-810) |
| Radiator / cooling fan | ENGINE > ENGINE COOLING SYSTEM (25-253) (single leaf, no word radiator/fan); intercooler: ENGINE > TURBOCHARGER & INTERCOOLER; oil cooler: ENGINE > OIL COOLING |
| Condenser | not seen (ELECTRIC > AIRCON SYSTEM-COOLER LINE 97-976 is the only AC leaf) |
| Window regulator | TRIM > FRONT/REAR DOOR WINDOW REGULATOR & GLASS (81-824/834) |
| Mouldings | TRIM > FRONT/REAR DOOR MOULDING, BODY SIDE MOULDING (86-877), BACK PANEL MOULDING (86-873), REAR WINDOW GLASS & MOULDING |
| Tow hook cover | not seen |

Surprises: bumpers/mirror/wheel guard/grille/emblem all under TRIM (86-8xx), not BODY; BODY holds only sheet metal panels. Under cover under ENGINE. Lamps under ELECTRIC. "TRANSMISSION" top group code is MI. ENGINE leaves carry suffix " - ENGINE CAPACITY: 1700 CC - U2" and codes with D/A letters. Duplicate leaves (".1", ".2" same name). Typo "WHEEL GAURD". Abbrev: RR, MTM/ATM. Nothing named radiator.

## Hyundai (VIN kmhjn81bp8u832861; kmhab51gp3u290004 same shape)
Top groups: BODY, CHASSIS, ELECTRIC, ENGINE, TRANSMISSION, TRIM (same as Kia).

| Family | Path |
|---|---|
| Bumpers | TRIM > FRONT BUMPER (86-865), REAR BUMPER (86-866) |
| Radiator grille | TRIM > RADIATOR GRILLE (86-863) |
| Exterior mirror | TRIM > REAR VIEW MIRROR (86-876) (name differs from Kia, no "outside/exterior") |
| Headlamp / tail lamp | ELECTRIC > HEAD LAMP (91-921) / REAR COMBINATION LAMP (91-924); BODY SIDE LAMP (91-923) |
| Fog lamp | not seen |
| Wheel arch liner | TRIM > WHEEL GAURD (86-868) [typo] |
| Undertray | ENGINE > UNDER COVER (29-291) |
| Door handle | not seen as leaf (FRONT/REAR DOOR TRIM, DOOR LOCKING) |
| Fender / bonnet | BODY > FENDER & HOOD PANEL (60-660), FENDER APRON & RADIATOR SUPPORT PANEL (60-640); TRIM > HOOD TRIM |
| Radiator / fan | ENGINE > ENGINE COOLING SYSTEM (25-253); condenser/AC: ELECTRIC > AIRCON SYSTEM-COOLER LINE (97-976) |
| Window regulator | TRIM > FRONT/REAR DOOR WINDOW REGULATOR & GLASS |
| Mouldings | TRIM > FRONT/REAR DOOR MOULDING, BODY SIDE MOULDING, BACK PANEL MOULDING, ROOF GARNISH & RR SPOILER |
| Tow hook cover | not seen |

Surprises: same TRIM placement as Kia. Leaf names differ slightly from Kia (REAR VIEW MIRROR vs MIRROR-OUTSIDE REAR VIEW; FRONT AXLE HUB vs FRONT AXLE; "TAIL GATE" under BODY 60-690 vs 60-737). Hyundai adds RADIATOR GRILLE leaf, Kia sample lacks it. Engine leaves have suffix " - ENGINE CAPACITY: 2000 CC - BETA"; transmission leaves " - TRANSAXLE: MANUAL T/M - 5 SPEED 2WD". Typo "WHEEL GAURD".

## Fiat (VINs zfa19900000625860 detailed; zfa18800001190066 coarse)
Top groups (3-digit codes, English names): 100 ENGINE AND SUSPENSION; 101 CRANKCASE AND CYLINDERS HEAD; 102 FUEL INJECTION SYSTEM; 103 LUBRIFICATION SYSTEM [typo]; 104 COOLING SYSTEM; 181 CLUTCH; 212 GEARBOX; 274 BRIDGE AND AXLE SHAFTS; 331 BRAKES; 381 TRAILER AND COVERS; 412 STEERING; 443 SUSPENSION AND WHEELS; 501 CLIMATE CONTROL; 551 ENGINE IGNITION SYSTEM; 552 ENGINE STARTING EQUIPMENT; 553 GENERATOR; 554 LIGHTING; 555 APPARATUS AND ELECTRIC CONTROLS; 681 TOOLS; 700 BODYSHELL AND PLATES; 701 DISPLAY UNITS AND WINDOWS; 705 INTERNAL TRIM; 706 SEATS; 707 BODY EXTERIOR TRIMS.
Leaf names are "<5-digit code> , <GROUP NAME> - <description>"; code is "xxxxx-0yy".

| Family | Path |
|---|---|
| Front/rear bumper | 707 BODY EXTERIOR TRIMS > 70726 FRONT BUMPER (+ FRONT BUMPER CLAMPS) / 70727 REAR BUMPER (+ CLAMPS, REAR PLATE CLAMPS) |
| Bumper reinforcement | 700 BODYSHELL AND PLATES > 70002-010 "FRONT END AND REAR CROSSRAIL"; 70004-040 REAR CRASH BOX (not named bumper) |
| Radiator grille | 707 > 70722 RADIATOR GRILL (seen in second VIN and Lancia; not in detailed VIN list; possibly under 70717 AIR INTAKES AND LIDS) |
| Exterior mirror | 707 > 70740 REARVIEW MIRRORS (REAR VIEW MIRROR / WING MIRRORS) |
| Headlamp | 554 LIGHTING > 55401-010 OUTER LIGHTING - FRONT HEADLIGHT (also duplicated under 555) |
| Tail lamp / fog | 554 > 55401-030 TAIL LAMP, 55401-040 REVERSE FOG TAIL LAMP; front fog not seen |
| Wheel arch liner | 707 > 70723 PROTECTION ITEMS - WHEEL CARRIAGE COVER ("wheel carriage" = wheel house); 700 > 70004-020 WHEEL CARRIAGE |
| Undertray | 381 TRAILER AND COVERS > 38115-010 FRAME GUARDS - ENGINE UNDERSIDE GUARD; also 101 > 10102-010 "OIL CAP AND FLOOR PANEL COVER" |
| Door handle | 701 DISPLAY UNITS AND WINDOWS > 70129-060 SIDE FRONT DOORS - FRONT DOOR HANDLE; 70136 SIDE REAR DOORS; interior: 705 > 70525-020 HANDLE GRIPS |
| Fender | 700 > 70018-010 BODYSHELL, PANELS (FRONT PART) - FRONT MUDGUARD |
| Bonnet/hood | 701 > 70101-010 ENGINE COMPARTMENT LID (bonnet; BACK DOOR - BONNET LOCK is actually tailgate lock); 705 > 70522-010 bonnet padding |
| Radiator | 104 COOLING SYSTEM > 10401-010 RADIATOR (+ RADIATOR PIPING, "FUEL TANK EXPANSION" = expansion tank) |
| Cooling fan | 104 > 10409-010 FAN AND FAN DRIVE - "HEATER FAN" |
| Condenser | 501 CLIMATE CONTROL > 50101-030 VENTILATION AND HEATING - CONDENSOR [typo] |
| Intercooler | 102 > 10247-010 HEAT EXCHANGER PIPELINE - HEAT EXCHANGER |
| Window regulator | 701 > 70129-040 FRONT ELECTRIC WINDOW; 70129-030 FRONT WINDOW AND CHANNEL |
| Mouldings | 707 > 70712 OUTER TRIM MOULDINGS (ROOF AREA / PILLAR AREA / DOOR AREA); 381 > 38115-020 SIDE RUBBING STRIPS; 443 > 44316-020 WHEEL SILL MOULDING |
| Tow hook cover | not seen (maybe in bumper clamps) |

Surprises: no BODY/TRIM wording: bonnet, door handles, windows all under "DISPLAY UNITS AND WINDOWS" (701); undertray under "TRAILER AND COVERS" (381 FRAME GUARDS); fender = "MUDGUARD"; wheelhouse liner = "WHEEL CARRIAGE COVER"; lamps under "LIGHTING" (554) and duplicated under 555; "cooling fan" leaf named "HEATER FAN"; typos LUBRIFICATION, GURADS, CIELING, CONDENSOR, ACCESORY, PADDINGs. Granularity depends on VIN: detailed VIN has multiple leaves per family (e.g. 55401-010/030/040), second VIN (zfa188...) has coarse leaves "OUTER LIGHTING - OUTER LIGHTING", "FRAME GUARDS - FRAME GUARDS", "SIDE FRONT DOORS - SIDE FRONT DOORS" (repeated 5 times), so leaf text carries no discriminating info there.

## Lancia (VIN zla84300003190507; same 707 structure for zla84400001028878)
Top groups: identical to Fiat (same 24 groups, same English names, same typos).
Leaf format "<code>/<nn> = <5 digit>, <GROUP> - <description>", description mostly repeats the group name (coarse).

| Family | Path |
|---|---|
| Bumpers | 707 BODY EXTERIOR TRIMS > 70726/10 FRONT BUMPER, 70727/10 REAR BUMPER |
| Radiator grille | 707 > 70722/10 RADIATOR GRILL |
| Exterior mirror | 707 > 70740/00 REARVIEW MIRRORS |
| Headlamp / tail lamp / fog | 554 LIGHTING > 55401/10 OUTER LIGHTING - OUTER LIGHTING (single leaf for all exterior lamps) |
| Wheel arch liner | 707 > 70723/10 PROTECTION ITEMS |
| Undertray | 381 TRAILER AND COVERS > 38115/00 FRAME GUARDS |
| Door handle | 701 > 70129/10 SIDE FRONT DOORS (no handle leaf) |
| Fender | 700 > 70018/00 BODYSHELL, PANELS (FRONT PART) |
| Bonnet | 701 > 70101/00 ENGINE COMPARTMENT LID |
| Radiator / fan | 104 COOLING SYSTEM > 10401/00 RADIATOR AND PIPING; 10409/00 FAN AND FAN DRIVE |
| Condenser | 501 CLIMATE CONTROL > 50101/00 HEAT AND VENTILATION SYSTEM (no condenser word) |
| Window regulator | not seen (701 > SIDE FRONT DOORS) |
| Mouldings | 707 > 70712/10 EXTERNAL MOLDINGS AND GASKETS |
| Tow hook cover | not seen |

Surprises: only the 2-level group>unit tree with almost no discriminating text; semantic ranking must rely on group names ("FRAME GUARDS", "PROTECTION ITEMS", "SIDE FRONT DOORS"). "MOLDINGS" vs Fiat "MOULDINGS".

## Mercedes-Benz (VINs wdd2052041f273241 [W205], wdc1569081j414565 [W156])
Top groups = numeric group codes (21..99) with names: 21 Major assembly detachable parts; 24 Engine suspension; 25 Clutch; 26 Gearshift system; 27 Automatic MB transmission; 29 Pedal assembly; 30 Regulation; 32 Springs, suspension and hydraulic components; 33 Front axle; 35 Rear axle; 40 Wheels; 41 Propeller shaft; 42 Brake system; 46 Steering; 47 Fuel system; 49 Exhaust system; 50 Radiator; 52 Chassis sheet metal parts / air intake; 54 Electrical equipment and instruments; 58 Tools and accessories; 60 Body - in - white; 61 Substructure; 62 Front - end assembly, front panel; 63 Side walls; 64 Rear end; 65 Roof; 67 Window system; 68 Trim; 69 Trim and lining; 72 Driver's door; 73 Rear doors; 74 Rear - end door; 78 Sliding sunroof; 82 Electrical system; 83 Heating and ventilation; 84 Case and container; 86 Windshield washer system, emergency equipment; 88 Detachable parts; 91 Driver's seat; 92 Rear seat; 98 Accessories; 99 Special equipment.
Leaves are 3-digit codes with short names (no repeated group name). Names differ between VINs (translations differ: "Engine hood" vs "ENGINE HOOD", "Radiator grille" vs "RADIATOR GRILL", "Windshield wiper" vs "PANE WIPER", capitalisation).

| Family | Path |
|---|---|
| Front/rear bumper | 88 Detachable parts > 030 Front bumper / 075 Rear bumper |
| Bumper reinforcement | 62 Front-end assembly > 060 "Front reinforcement and radiator support"; 64 Rear end |
| Radiator grille | 88 > 135 Radiator grille |
| Bonnet | 88 > 120 Engine hood |
| Fender | 88 > 015 Front fender; 63 Side walls > 045 Rear fender |
| Exterior mirror | 72 Driver's door > 331/332 Outside mirror, left/right (rear doors: not present); also 99 Special equipment > 140 Outside mirror; 98 Accessories > 300 Mirror; do NOT confuse with 69 > 018 "inside rearview mirror" |
| Headlamp | 82 Electrical system > 175 Front illumination (NOT "Lighting"); dynamic range control in 33 Front axle > 035 / 35 Rear axle > 080 |
| Tail lamp | 82 > 220 Rear illumination |
| Fog lamp | not seen (probably within 175 Front illumination) |
| Wheel arch liner | 62 > 030 "Wheel well, front axle carrier" (W156: "WHEELHOUSE,FRONT SUBFRAME"), 090 "Engine compartment partition wall, wheel well detachable parts" |
| Undertray | 21 Major assembly detachable parts > 300 Shielding and damping to engine, transmission, front axle differential; 49 Exhaust system > 300 Shields; 52 Chassis sheet metal parts/air intake > 045 Soundproofing |
| Door handle | 72/73 > 030 Locking system |
| Window regulator | 72 > 045 Window lifter (W156: WINDOW REGULATOR); 73 > 045 |
| Radiator / cooling | 50 Radiator > 015 Cooler, mount and cover; 200 Charge air cooling (intercooler); 160 Oil cooler; fan: 50 > 190 Air pump, water pump and detachable parts (not "fan") |
| Condenser | 83 Heating and ventilation > 195 Refrigerant line routing / 190 Refrigerant compressor; (condenser itself may be in 50 > 015 "Cooler") |
| Mouldings | 69 Trim and lining > 060 Exterior detachable parts / "OUTSIDE ATTACHMENT PARTS"; 98 > 020 Exterior detachable parts |
| Tow hook cover | not seen (88 Front/Rear bumper probable; 99 > 125 Trailer hitch) |

Surprises: group 88 "Detachable parts" holds bumpers, grille, hood, fender (nothing named body/exterior); group named "Radiator" is cooling; lamps are under "Electrical system" as "illumination"; mirror under door group; "Driver's door" group holds the front-door family; group 98/99 contain duplicates of mirror/exterior parts (accessory traps); undertray concept spread across 21/49/52 "shielding/shields/soundproofing"; 69 has "inside rearview mirror" and 60 Body-in-white returns no leaves.

## Nissan (VINs sjntbaj12u1391023 [Note/Micra-like], sjntaaj12u1032266)
Top groups (letter codes): A ENGINE MECHANICAL; B FUEL & ENGINE CONTROL; C EXHAUST & COOLING; D ENGINE ELECTRICAL; E BODY ELECTRICAL; F POWER TRAIN; G AXLE & SUSPENSION; H BRAKE; I STEERING; J BODY(FRONT,ROOF & FLOOR); K BODY(SIDE & REAR); L SEAT & SEAT BELT; M BODY(BACK DOOR & REAR BODY); N MISCELLANEOUS.
Leaf names: "<nnn> | <X> <nnn> = NAME (date-range MODEL)" e.g. `620 | A 002 = FRONT BUMPER (2022-05 - 2024-04 5DOOR)`; date ranges and body codes vary per VIN.

| Family | Path |
|---|---|
| Front bumper | J BODY(FRONT,ROOF & FLOOR) > 620 FRONT BUMPER |
| Rear bumper | K BODY(SIDE & REAR) > 850 REAR BUMPER |
| Radiator grille | J > 623 FRONT GRILLE |
| Bumper reinforcement | J > 625 FRONT APRON & RADIATOR CORE SUPPORT (not named) |
| Exterior mirror | not clearly seen: N MISCELLANEOUS > 963 REAR VIEW MIRROR (probably interior; exterior may be inside door groups K 800/805) |
| Headlamp | E BODY ELECTRICAL > 260 HEADLAMP |
| Fog lamp | E > 263 FOG,DAYTIME RUNNING & DRIVING LAMP |
| Tail lamp | E > 265 REAR COMBINATION LAMP; 268 HIGH MOUNTING STOP LAMP |
| Wheel arch liner | K > 780 REAR FENDER PROTECTOR (front liner: not seen, maybe J 630 FRONT FENDER & FITTING) |
| Undertray | not seen (J > 750 ENGINE ROOM? only floor) |
| Door handle | K > 805 FRONT DOOR LOCK & HANDLE, 825 REAR DOOR LOCK & HANDLE, M > 905 BACK DOOR LOCK & HANDLE |
| Fender | J > 630 FRONT FENDER & FITTING; K > 780 REAR FENDER & FITTING |
| Bonnet | J > 650 HOOD PANEL,HINGE & FITTING; 640 HOOD LEDGE & FITTING; 656 HOOD LOCK CONTROL |
| Radiator | C EXHAUST & COOLING > 214 RADIATOR (+ PAGE 2) |
| Cooling fan | C > 210 WATER PUMP, COOLING FAN & THERMOSTAT |
| Intercooler | A ENGINE MECHANICAL > 144 INTERCOOLER & PIPING; oil cooler C > 213 |
| Condenser | not seen (E > 270 HEATER-FR, 290 "PAG 1..5" = A/C refrigerant piping/compressor) |
| Window regulator | K > 803 FRONT DOOR WINDOW & REGULATOR, 823 REAR DOOR WINDOW & REGULATOR |
| Mouldings | K > 766 BODY SIDE MOULDING |
| Tow hook cover | not seen |

Surprises: bodywork is split across J (front/roof/floor), K (side & rear, includes rear bumper!), M, N; rear bumper is in K, front bumper in J; lamps and AC are in "BODY ELECTRICAL"; radiator is under "EXHAUST & COOLING"; code-only names (E483002Y, E488003A, E4920029, "PAG 1", "PG1/PG2", "MR15-EPWR", "QI2W SUSPENSION", "HT SUSPENSION"); generic names "ENGINE ROOM", "BODY", "ROOM", "FRAME", "TRIM", "MEMBER" repeated in several groups; leaf text embeds date range/model suffix; abbreviations (INST, FR, F/STD, BAT, E-PWR, HFO, IHX, 4WD, MCVT, MT).
