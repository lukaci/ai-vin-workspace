import os,json,csv,re,sys
from concurrent.futures import ThreadPoolExecutor
base='/home/lukaci/projects/ai-vin/.s3/cache/slax-partslink'
cross=json.load(open('cross.json'))
norm=lambda s: re.sub(r'[^0-9a-z]','',str(s).lower())
oe2sku={}
for sku,lst in cross.items():
    for oe,desc in lst: oe2sku.setdefault(norm(oe),[]).append((sku,desc))
rows=list(csv.DictReader(open('xlsx/Casi.csv')))
vins={r['telaio_vin'].lower():r['marca'] for r in rows}
brands=os.listdir(base)
vin2dir={}
for b in brands:
    for v in os.listdir(os.path.join(base,b)):
        if v in vins: vin2dir[v]=os.path.join(base,b,v)
print('vins',len(vins),'found',len(vin2dir),file=sys.stderr)
def scan(item):
    v,d=item; out=[]
    for f in os.listdir(d):
        if not f.endswith('_search'): continue
        try: j=json.load(open(os.path.join(d,f)))
        except Exception as e: continue
        q=j.get('search',''); units=j.get('units') or []
        hit=[u for u in units if norm(u.get('number',''))==norm(q)]
        out.append({'vin':v.upper(),'marca':vins[v],'oe':q,'found':bool(hit),
            'illustration':hit[0]['attributes'].get('illustration') if hit else None,
            'catalog_name':hit[0].get('name') if hit else None,
            'skus':oe2sku.get(norm(q),[])})
    return out
with ThreadPoolExecutor(16) as ex:
    res=[x for l in ex.map(scan,vin2dir.items()) for x in l]
json.dump(res,open('fts_searches.json','w'))
print(len(res), sum(r['found'] for r in res), sum(1 for r in res if r['found'] and r['skus']))
