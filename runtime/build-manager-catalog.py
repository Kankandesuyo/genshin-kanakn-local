import json,re,sys
from pathlib import Path
root=Path(__file__).resolve().parent.parent
excel=root/'server/resources/ExcelBinOutput'
def read(name): return json.loads((excel/name).read_text(encoding='utf-8-sig'))
handbook=(root/'server/GM Handbook/GM Handbook - CHS.txt').read_text(encoding='utf-8-sig')
names={int(k):v.strip() for k,v in re.findall(r'^\s*(\d+)\s*:\s*(.+)$',handbook,re.M)}
furniture={r['avatarID']:r['furnitureID'] for r in read('HomeWorldNPCExcelConfigData.json') if 'avatarID' in r and 'furnitureID' in r}
codex={r['avatarId'] for r in read('AvatarCodexExcelConfigData.json')}
avatar_items={}
for item in read('MaterialExcelConfigData.json'):
    if item.get('materialType')!='MATERIAL_AVATAR': continue
    # Gift-box variants (3004 etc.) grant an avatar but are not valid wish display cards.
    if not item.get('icon','').startswith('UI_AvatarIcon_'): continue
    for use in item.get('itemUse',[]):
        if use.get('useOp')=='ITEM_USE_GAIN_AVATAR':
            avatar_items[int(use['useParam'][0])]=item['id']
avatars=[]
for row in read('AvatarExcelConfigData.json'):
    aid=row['id']
    if aid not in codex or aid not in avatar_items or row.get('useType')!='AVATAR_FORMAL': continue
    if row.get('qualityType') not in ('QUALITY_ORANGE','QUALITY_ORANGE_SP','QUALITY_PURPLE'): continue
    name={10000136:"米提亚",10000137:"瓦列里"}.get(aid) or names.get(furniture.get(aid,0)) or names.get(aid) or row.get('iconName','').replace('UI_AvatarIcon_','')
    avatars.append(dict(id=avatar_items[aid],avatarId=aid,name=name,stars=4 if row['qualityType']=='QUALITY_PURPLE' else 5))
avatars.sort(key=lambda a:a['id'])
weapon_names=json.loads((root/'runtime/weapon-names-zh.json').read_text(encoding='utf-8-sig'))
weapon_types={'WEAPON_SWORD_ONE_HAND':'单手剑','WEAPON_CLAYMORE':'双手剑','WEAPON_POLE':'长柄武器','WEAPON_CATALYST':'法器','WEAPON_BOW':'弓'}
weapons=[]
for w in read('WeaponExcelConfigData.json'):
    if w.get('rankLevel')!=5 or w.get('itemType')!='ITEM_WEAPON': continue
    official=weapon_names.get(str(w['id']))
    name=official or ('钓鱼竿（内部条目）' if w['id']==20001 else '名称待核实·'+weapon_types.get(w.get('weaponType'),'武器'))
    weapons.append(dict(id=w['id'],name=name,nameVerified=bool(official)))
catalog=dict(avatars=avatars,weapons=weapons)
(root/'runtime/manager-catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
if '--catalog-only' in sys.argv:
    print(json.dumps(dict(weapons=len(weapons),verifiedChineseNames=sum(w['nameVerified'] for w in weapons)),ensure_ascii=False))
    sys.exit(0)
path=root/'server/data/LocalBanners.json'
banners=json.loads(path.read_text(encoding='utf-8-sig'))
banners=[b for b in banners if b['scheduleId']!=9104]
banners.append(dict(comment='全角色混合池',scheduleId=9104,sortId=400,bannerType='CHRONICLE',prefabPath='GachaShowPanel_A019',costItemId=223,rateUpItems5=[a['id'] for a in avatars if a['stars']==5],rateUpItems4=[a['id'] for a in avatars if a['stars']==4],fallbackItems5Pool1=[a['id'] for a in avatars if a['stars']==5],fallbackItems5Pool2=[],fallbackItems4Pool1=[a['id'] for a in avatars if a['stars']==4],fallbackItems4Pool2=[]))
import runpy
runpy.run_path(str(root/'runtime/complete-four-star-pools.py'))['complete'](banners)
path.write_text(json.dumps(banners,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(dict(avatars=len(avatars),fiveStar=sum(a['stars']==5 for a in avatars),fourStar=sum(a['stars']==4 for a in avatars),weapons=len(weapons)),ensure_ascii=False))
