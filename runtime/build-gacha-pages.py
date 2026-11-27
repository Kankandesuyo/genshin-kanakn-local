"""Build offline wish pages for the existing authenticated game HTTP routes."""
import json
import base64
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / 'server/data/gacha'
catalog = json.loads((root / 'runtime/manager-catalog.json').read_text('utf-8-sig'))
mapping_source = (out / 'mappings.js').read_text('utf-8-sig').split('// LOCAL_GACHA_PORTRAITS')[0].strip().rstrip(';')
mapping = json.loads(mapping_source.split('=', 1)[1].strip().rstrip(';'))['zh-cn']
names = {k: [v[0].split(' ([N/A]')[0], 5 if v[1] == 'yellow' else 4 if v[1] == 'purple' else 3] for k, v in mapping.items() if isinstance(v, list)}
for group in ('avatars', 'weapons'):
    for item in catalog[group]:
        names[str(item['id'])] = [item['name'], item.get('stars', 5)]
for key, value in json.loads((root / 'runtime/weapon-names-zh.json').read_text('utf-8-sig')).items():
    names.setdefault(key, [value, 3])[0] = value
common_weapons = {
    11301:'冷刃',11302:'黎明神剑',11303:'旅行剑',11304:'暗铁剑',11305:'吃虎鱼刀',11306:'飞天御剑',
    12301:'铁影阔剑',12302:'沐浴龙血的剑',12303:'白铁大剑',12305:'以理服人',12306:'飞天大御剑',
    13301:'白缨枪',13302:'钺矛',13303:'黑缨枪',14301:'魔导绪论',14302:'讨龙英杰谭',
    14303:'异世界行记',14304:'翡玉法球',14305:'甲级宝珏',15301:'鸦羽弓',15302:'神射手之誓',
    15303:'反曲弓',15304:'弹弓',15305:'信使'
}
for key, value in common_weapons.items():
    names[str(key)] = [value, 3]
for key, value in {1003:'琴',1016:'迪卢克'}.items():
    names[str(key)] = [value, 5]

head = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>本地服祈愿</title><style>
*{box-sizing:border-box}body{margin:0;background:#f5f1e8;color:#343d50;font:18px/1.6 "Microsoft YaHei",sans-serif;padding:24px}main{max-width:1000px;margin:auto}h1{font-size:28px;margin:0 0 8px}p{margin:8px 0 16px}.muted{color:#667085;font-size:15px}select,button{font:inherit;padding:8px 16px;border:1px solid #b8b2a7;border-radius:8px;background:#fff;color:#343d50}button{cursor:pointer}button:disabled{opacity:.4;cursor:default}nav{display:flex;gap:14px;align-items:center;flex-wrap:wrap;margin:18px 0}table{border-collapse:collapse;background:white;width:100%}th,td{text-align:left;padding:12px;border-bottom:1px solid #e5e1d9}th{background:#e9e3d6}.s5{color:#976314;font-weight:bold}.s4{color:#77519e}.s3{color:#3d6a92}.panel{background:#fff;border:1px solid #ddd6c9;border-radius:10px;padding:16px;margin:16px 0}.items{display:flex;flex-wrap:wrap;gap:8px}.item{padding:5px 12px;background:#f5f1e8;border-radius:6px}a{color:#4566a3}#empty{padding:28px;text-align:center;background:white}h2{font-size:21px}footer{margin-top:18px;font-size:14px;color:#667085}</style><main>'''
shared = 'const itemNames=' + json.dumps(names, ensure_ascii=False).replace('<', '\\u003c') + ';\n' + '''
function describe(id){return itemNames[String(id)] || ['物品 '+id,0]}
const params=new URLSearchParams(location.search);
function go(changes){const next=new URL(location.href);for(const [k,v] of Object.entries(changes))next.searchParams.set(k,v);location.assign(next.href)}
'''
records = head + '''<h1>祈愿历史记录</h1><p class="muted">真实抽取结果，按时间从新到旧显示，每页 10 条。更换卡池可查看对应记录。</p>
<nav><label>卡池 <select id="pool"><option value="200">常驻池</option><option value="301">自选角色 UP 池</option><option value="302">自选武器 UP 池</option><option value="500">全角色混合池</option></select></label><button id="refresh">刷新记录</button></nav>
<div class="panel"><h2 id="poolName"></h2><div id="summary"></div><p class="muted">角色池、武器池、常驻池和混合池各自独立统计。出金抽数包含出五星的这一抽，跨页连续计算；首个五星从该池首条已保存记录开始计数。</p></div>
<table><thead><tr><th>获得物品</th><th>星级</th><th>出金抽数</th><th>抽取时间</th></tr></thead><tbody id="rows"></tbody></table><div id="empty" hidden>此卡池还没有抽取记录。</div>
<nav><button id="prev">上一页</button><span id="page"></span><button id="next">下一页</button></nav><footer>十连抽会分别保存为十条记录。统计基于已有历史，不是下一次出金的预测。</footer></main><script>'''+ shared + '''
const records='{{REPLACE_RECORDS}}';
const maxPage='{{REPLACE_MAXPAGE}}';
const summary='{{REPLACE_SUMMARY}}';
const page=Math.max(0,Number(params.get('p'))||0);
const type=params.get('gachaType')||'301';
const pool=document.getElementById('pool');pool.value=type;
document.getElementById('poolName').textContent=({'200':'常驻池','301':'角色 UP 池','302':'武器 UP 池','500':'全角色混合池'})[type]||'当前卡池';
document.getElementById('summary').textContent=`累计 ${summary.total||0} 抽 · 五星 ${summary.fiveStars||0} 个 · ${summary.fiveStars?'距上次出金':'从首条记录起'}已抽 ${summary.sinceLastFive||0} 抽`;
pool.onchange=()=>go({gachaType:pool.value,p:0});
document.getElementById('refresh').onclick=()=>location.reload();
const rows=document.getElementById('rows');
for(const record of records){const info=describe(record.item);const stars=record.stars||info[1];const tr=document.createElement('tr');
const interval=stars===5?`${record.pullsToFive} 抽出金${record.fromFirstRecord?'（首条记录起）':''}`:'—';
for(const value of [info[0],stars?stars+' 星':'—',interval,new Date(record.time).toLocaleString('zh-CN',{hour12:false})]){const td=document.createElement('td');td.textContent=value;tr.appendChild(td)}tr.className='s'+stars;rows.appendChild(tr)}
document.getElementById('empty').hidden=records.length!==0;
document.getElementById('page').textContent=maxPage?`第 ${page+1} / ${maxPage} 页`:'暂无记录';
document.getElementById('prev').disabled=page===0;
document.getElementById('next').disabled=page+1>=maxPage;
document.getElementById('prev').onclick=()=>go({p:page-1});
document.getElementById('next').onclick=()=>go({p:page+1});
</script></html>'''
details = head + '''<h1>祈愿概率与可获得物品</h1><p class="muted">以下为此本地服实际规则。基础概率会随未出五星的抽数增加；并非每一抽都固定不变。</p><div class="panel"><h2 id="poolTitle"></h2><p id="rates"></p><p id="guarantee"></p><p class="muted">五星出现后，五星保底计数重新开始。十连抽按十次单抽依次计算；当五星和四星保底重合时，优先获得五星。</p><button id="history">查看此卡池历史记录</button></div>
<section class="panel"><h2>可获得五星</h2><div class="items" id="five"></div></section><section class="panel"><h2>可获得四星</h2><div class="items" id="four"></div></section><section class="panel"><h2>可获得三星</h2><div class="items" id="three"></div></section><footer>名单来自当前卡池实际配置。卡面图片与抽取内容分别配置，图片并不代表完整物品名单。</footer></main><script>'''+shared+'''
const pools={9101:['常驻池',200,'五星概率从第 1 抽的 0.75% 逐步升至第 73 抽的 1.5%，之后继续提高，最多 90 抽出五星。四星基础概率 5.1%。','常驻池没有限定 UP 保证。'],9102:['自选角色 UP 池',301,'五星基础概率 0.8%，前 73 抽保持不变，从第 74 抽起提高，最多 90 抽出五星。四星基础概率 5.1%。','非大保底时，五星基础 UP 命中率为 50%；捕获明光会随连续偏离次数提高命中率。抽到非 UP 五星后，下个五星保证为 UP。'],9103:['自选武器 UP 池',302,'五星基础概率 1%，前 62 抽保持不变，从第 63 抽起提高，最多 80 抽出五星。四星基础概率 6%。','五星基础 UP 命中率为 75%；抽到非 UP 五星后，下个五星保证为 UP。定轨还受所选武器和命定值影响。'],9104:['全角色混合池',500,'五星基础概率 1%，前 62 抽保持不变，从第 63 抽起提高，最多 80 抽出五星。四星基础概率 6%。','五星和四星角色名单见下方。基础概率指星级概率，不是某个指定角色的概率。']};
const data=pools[params.get('scheduleId')]||['当前卡池',301,'请以服务器配置为准。',''];
document.getElementById('poolTitle').textContent=data[0];document.getElementById('rates').textContent=data[2];document.getElementById('guarantee').textContent=data[3];
for(const [target,ids,stars] of [['five',{{FIVE_STARS}},5],['four',{{FOUR_STARS}},4],['three',{{THREE_STARS}},3]]){const el=document.getElementById(target);for(const id of ids){const span=document.createElement('span');span.className='item s'+stars;span.textContent=describe(id)[0];el.appendChild(span)}if(!ids.length)el.textContent='无';}
document.getElementById('history').onclick=()=>{const next=new URL('/gacha',location.origin);next.searchParams.set('s',params.get('s')||'');next.searchParams.set('gachaType',data[1]);location.assign(next.href)};
</script></html>'''
out.mkdir(exist_ok=True)
portraits = {p.stem:'data:image/png;base64,'+base64.b64encode(p.read_bytes()).decode('ascii')
             for p in (root / 'runtime/gacha-icons').glob('*.png') if p.read_bytes().startswith(b'\x89PNG')}
(out / 'mappings.js').write_text(mapping_source+';\n// LOCAL_GACHA_PORTRAITS\nwindow.gachaPortraits='+json.dumps(portraits)+';\n',encoding='utf-8')
records = (root / 'runtime/gacha-records-template.html').read_text('utf-8').replace(
    '__ITEM_NAMES__', json.dumps(names, ensure_ascii=False).replace('<', '\\u003c'))
for name, body in [('records.html', records), ('details.html', details)]:
    (out / name).write_text(body, encoding='utf-8')
print('Built history and probability pages with',len(names),'item names.')
