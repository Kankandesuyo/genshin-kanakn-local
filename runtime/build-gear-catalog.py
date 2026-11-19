import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
read=lambda name:json.loads((root/'server/resources/ExcelBinOutput'/name).read_text('utf-8-sig'))
text=json.loads((root/'runtime/gear-text-all.json').read_text('utf-8-sig'))['zh-cn']
local=json.loads((root/'server/resources/TextMap/TextMapCHS.json').read_text('utf-8-sig'))
props={'FIGHT_PROP_HP':'生命值','FIGHT_PROP_HP_PERCENT':'生命值%','FIGHT_PROP_ATTACK':'攻击力','FIGHT_PROP_ATTACK_PERCENT':'攻击力%','FIGHT_PROP_DEFENSE':'防御力','FIGHT_PROP_DEFENSE_PERCENT':'防御力%','FIGHT_PROP_CRITICAL':'暴击率','FIGHT_PROP_CRITICAL_HURT':'暴击伤害','FIGHT_PROP_CHARGE_EFFICIENCY':'元素充能效率','FIGHT_PROP_ELEMENT_MASTERY':'元素精通','FIGHT_PROP_HEAL_ADD':'治疗加成','FIGHT_PROP_PHYSICAL_ADD_HURT':'物理伤害加成','FIGHT_PROP_FIRE_ADD_HURT':'火元素伤害','FIGHT_PROP_WATER_ADD_HURT':'水元素伤害','FIGHT_PROP_WIND_ADD_HURT':'风元素伤害','FIGHT_PROP_ELEC_ADD_HURT':'雷元素伤害','FIGHT_PROP_ICE_ADD_HURT':'冰元素伤害','FIGHT_PROP_ROCK_ADD_HURT':'岩元素伤害','FIGHT_PROP_GRASS_ADD_HURT':'草元素伤害'}
slots={'EQUIP_BRACER':'生之花','EQUIP_NECKLACE':'死之羽','EQUIP_SHOES':'时之沙','EQUIP_RING':'空之杯','EQUIP_DRESS':'理之冠'}
setnames={}
for row in read('EquipAffixExcelConfigData.json'):
    name=text.get(str(row.get('nameTextMapHash'))) or local.get(str(row.get('nameTextMapHash')))
    # This resource dump loses low hash bits on some uint32 text keys. Accept a nearby
    # localized key only when it has a unique candidate; ambiguous/missing names stay labelled.
    if not name:
        value=row.get('nameTextMapHash',0)
        candidates=[v for k,v in text.items() if k.isdigit() and abs(int(k)-value)<=1024]
        if len(candidates)==1:name=candidates[0]
    if name and any('\u4e00'<=c<='\u9fff' for c in name):setnames[row['id']]=name
affixes=read('ReliquaryAffixExcelConfigData.json');mains=read('ReliquaryMainPropExcelConfigData.json')
sets={};items=[]
for row in read('ReliquarySetExcelConfigData.json'):
    if row.get('rankLevel')!=5:continue
    sets[row['setId']]=setnames.get(row.get('EquipAffixId'),f"套装 {row['setId']}（名称待补充）")
# Verified against the set ID and all five UI_RelicIcon_15045_* local resources.
# https://gi.gachabase.net/artifacts/15045/celestial-gift/release/6.7.0/45767575?lang=chs
sets[15045]='天之美赐'
# Additional release-set names checked by stable set ID on Gachabase's 7.1 release pages.
sets.update({15043:'晨星与月的晓歌',15044:'风起之日',15046:'影中沉凝的幻灭',15047:'血红之证',15048:'炉火融炼之心'})
# Local 15000 has disableFilter=1 and no EquipAffixId; do not invent a release-set name.
sets[15000]='隐藏套装15000（无套装词缀）'
selected={}
for row in sorted(read('ReliquaryExcelConfigData.json'),key=lambda r:(r['id']%10!=4,r['id'])):
    if row.get('rankLevel')!=5 or row.get('setId') not in sets or row.get('maxLevel')!=21 or row.get('appendPropDepotId')!=501:continue
    key=(row['setId'],row['equipType'])
    if key in selected:continue
    selected[key]=True
    choices=[{'id':m['id'],'prop':m['propType'],'name':props.get(m['propType'],m['propType'])} for m in mains if m['propDepotId']==row['mainPropDepotId'] and m['propType'] in props]
    best={}
    for a in affixes:
        if a.get('depotId')!=row['appendPropDepotId'] or a.get('propType') not in props:continue
        if a['propType'] not in best or a['propValue']>best[a['propType']]['propValue']:best[a['propType']]=a
    subs=[dict(id=a['id'],prop=a['propType'],name=props[a['propType']],value=a['propValue'],percent=a['propType'] not in ('FIGHT_PROP_HP','FIGHT_PROP_ATTACK','FIGHT_PROP_DEFENSE','FIGHT_PROP_ELEMENT_MASTERY')) for a in best.values()]
    items.append(dict(id=row['id'],setId=row['setId'],slot=row['equipType'],slotName=slots[row['equipType']],mains=choices,subs=subs))
result=dict(sets=[dict(id=k,name=v) for k,v in sets.items() if any(i['setId']==k for i in items)],items=items)
(root/'runtime/gear-catalog.json').write_text(json.dumps(result,ensure_ascii=False),encoding='utf-8')
print('Gear catalog:',len(result['sets']),'sets,',len(items),'five-star pieces;',sum('待补充' in s['name'] for s in result['sets']),'names pending')
