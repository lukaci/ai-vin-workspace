import json,random,re,collections
random.seed(20261018)
r=json.load(open('fts_searches.json'))
cross=json.load(open('cross.json'))
norm=lambda s: re.sub(r'[^0-9a-z]','',str(s).lower())
FAM={'PASSARUOTA':'parafanghino','PARAFANGHINO':'parafanghino','RETROVISORE':'specchio','PIASTRA':'piastra','CALOTTA':'calotta',
 'PROIETT':'proiettore','PROIET':'proiettore','PROIETTORE':'proiettore','FARO':'proiettore','FANALE':'fanale','FAN.POST.':'fanale',
 'MECCANISMO':'alzacristallo','ALZACRISTALLO':'alzacristallo','COPRIMOTORE-INFERIORE':'riparo','COPRIMOTORE':'riparo','RIPARO':'riparo',
 'FENDI':'fendinebbia','FENDINEBBIA':'fendinebbia','RETRONEBBIA':'fanale','TERZA':'terzaluce','MOLLA':'mollagas','LUCE':'luce','SEDE':'cornice','MOSTRINA':'cornice'}
fam=lambda d: FAM.get(d.split()[0], d.split()[0].lower())
cand=collections.defaultdict(list)
seen=set()
for x in r:
    if not (x['found'] and x['skus']): continue
    sku,desc=x['skus'][0]
    key=(x['vin'],sku)
    if key in seen: continue
    seen.add(key)
    oes=sorted({norm(o) for o,_ in cross[sku]})
    cand[x['marca']].append({'id':f"{x['vin']}:{sku}",'vin':x['vin'],'part':desc,'oe':oes,'brand':x['marca'],'type':fam(desc),'sku':sku})
quota={'Ford':8,'Volkswagen':7,'Opel/Vauxhall':7,'Fiat':8,'Peugeot':5,'Audi':5,'Citroen':4,'Mercedes':6,'Toyota':4,'Lancia':4,
 'Hyundai':5,'Kia':6,'Seat':2,'Bmw':4,'Jeep':3,'Nissan':4,'Mini':2,'Suzuki':2,'Skoda':2}
sample=[]
for b,q in quota.items():
    lst=cand[b][:]; random.shuffle(lst)
    bytype=collections.defaultdict(list)
    for c in lst: bytype[c['type']].append(c)
    types=list(bytype); random.shuffle(types)
    picked=[]; vins=collections.Counter()
    while len(picked)<q and any(bytype.values()):
        for t in types:
            if bytype[t] and len(picked)<q:
                c=bytype[t].pop()
                if vins[c['vin']]>=3: continue
                picked.append(c); vins[c['vin']]+=1
    sample+=picked
print(len(sample), collections.Counter(c['type'] for c in sample).most_common())
with open('/home/lukaci/projects/ai-vin/experiments/prasco-non-exact/data/sample-gt-v1.jsonl','w') as f:
    for c in sample: f.write(json.dumps(c,ensure_ascii=False)+'\n')
