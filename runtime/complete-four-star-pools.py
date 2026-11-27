import json,shutil
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=root/'server/data/LocalBanners.json'
catalog=json.loads((root/'runtime/manager-catalog.json').read_text(encoding='utf-8-sig'))
chars=sorted({a['id'] for a in catalog['avatars'] if a['stars']==4})
weapons=sorted({w['id'] for w in json.loads((root/'server/resources/ExcelBinOutput/WeaponExcelConfigData.json').read_text(encoding='utf-8-sig')) if w.get('rankLevel')==4 and w.get('itemType')=='ITEM_WEAPON' and w.get('icon','').startswith('UI_EquipIcon_') and w.get('weaponType') in {'WEAPON_SWORD_ONE_HAND','WEAPON_CLAYMORE','WEAPON_POLE','WEAPON_CATALYST','WEAPON_BOW'}})
def complete(banners):
    for b in banners:
        kind=b['bannerType']
        b['removeC6FromPool']=False
        if kind=='CHRONICLE':b['autoStripRateUpFromFallback']=False
        b['fallbackItems4Pool1']=[] if kind=='WEAPON' else chars
        b['fallbackItems4Pool2']=weapons if kind in ('WEAPON','STANDARD') else []
    return banners
if __name__=='__main__':
    rows=json.loads(p.read_text(encoding='utf-8-sig'))
    backup=root/'logs/LocalBanners-before-full-four-stars.json'
    if not backup.exists():shutil.copy2(p,backup)
    complete(rows)
    assert 4137 in chars and len(weapons)>100
    for b in rows:
        eligible=set(b['fallbackItems4Pool1']+b['fallbackItems4Pool2']+b.get('rateUpItems4',[]))
        required=set(weapons if b['bannerType']=='WEAPON' else chars+weapons if b['bannerType']=='STANDARD' else chars)
        assert required<=eligible,(b['scheduleId'],required-eligible)
    p.write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
    report={'fourStarCharacters':len(chars),'fourStarWeapons':len(weapons),'banners':[{'scheduleId':b['scheduleId'],'characterFallback':len(b['fallbackItems4Pool1']),'weaponFallback':len(b['fallbackItems4Pool2']),'featuredFour':len(b.get('rateUpItems4',[]))}for b in rows]}
    (root/'logs/four-star-pool-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))
