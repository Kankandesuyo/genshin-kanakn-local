"""Recover normal-boss coordinates from the local scene dump, without guessing positions."""
import json
import re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
excel=root/'server/resources/ExcelBinOutput'
scripts=json.loads((root/'server/resources/ScriptSceneData/flat.luas.scenes.full_globals.lua.json').read_text('utf-8-sig'))['scriptObjectList']
rows=json.loads((excel/'InvestigationMonsterConfigData.json').read_text('utf-8-sig'))
result=[];missing=[]
for row in rows:
    if row.get('monsterCategory')!='Boss' or row.get('resinCost')!=40:continue
    for group in row.get('groupIdList',[]):
        scene=5 if 155000000<=group<166000000 else 6 if 166000000<=group<170000000 else 3
        dump=scripts.get(f'{scene}/scene{scene}_group{group}.lua',{})
        monsters=dump.get('monsters',[])
        if not isinstance(monsters,list):monsters=[]
        matches=[m for m in monsters if m.get('monster_id') in row.get('monsterIdList',[]) and isinstance(m.get('pos'),list)]
        if not matches:
            lua=root/f'server/resources/Scripts/Scene/{scene}/scene{scene}_group{group}.lua'
            text=lua.read_text('utf-8-sig') if lua.exists() else ''
            for match in re.finditer(r'monster_id\s*=\s*(\d+)[^\n]*?pos\s*=\s*\{\s*x\s*=\s*([-\d.]+),\s*y\s*=\s*([-\d.]+),\s*z\s*=\s*([-\d.]+)',text):
                if int(match[1]) in row.get('monsterIdList',[]):matches.append({'monster_id':int(match[1]),'pos':[float(match[i]) for i in (2,3,4)]})
        if not matches:missing.append(group);continue
        m=matches[0];x,y,z=m['pos']
        result.append(dict(groupId=group,monsterId=m['monster_id'],x=x,y=y,z=z,sceneId=scene))
target=root/'server/resources/patch/world-boss-coords.json'
target.parent.mkdir(exist_ok=True)
target.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'Recovered {len(result)} normal-boss placements; missing script groups: {missing}')
