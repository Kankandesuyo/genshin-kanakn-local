const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
function run(file,query){
  const elements=new Map();
  const el=()=>({children:[],textContent:'',hidden:false,disabled:false,value:'',appendChild(c){this.children.push(c)}});
  const document={getElementById(id){if(!elements.has(id))elements.set(id,el());return elements.get(id)},createElement:el};
  let assigned='';let refreshed=false;
  const location={href:'http://127.0.0.1:8088/gacha?'+query,search:'?'+query,origin:'http://127.0.0.1:8088',assign(url){assigned=url},reload(){refreshed=true}};
  const body=fs.readFileSync(file,'utf8');
  assert(!/<script[^>]+src=|<link[^>]+href=/i.test(body),'Page must work without external assets');
  vm.runInNewContext(body.match(/<script>([\s\S]*)<\/script>/)[1],{document,location,URL,URLSearchParams,Date,Number,Math});
  return {elements,get assigned(){return assigned},get refreshed(){return refreshed}};
}
for(const [type,count] of [[200,0],[301,10],[302,10],[500,0]]){
  const page=run(`logs/gacha-history-${type}.html`,`s=test-session&gachaType=${type}`);
  assert.equal(page.elements.get('rows').children.length,count);
  assert.equal(page.elements.get('empty').hidden,count>0);
  assert.equal(page.elements.get('prev').disabled,true);
  assert(page.elements.get('summary').textContent.includes('累计 '));
  const html=fs.readFileSync(`logs/gacha-history-${type}.html`,'utf8');
  const records=JSON.parse(html.split('const records=')[1].split(';')[0]);
  records.forEach((record,index)=>{
    const cells=page.elements.get('rows').children[index].children;
    assert.equal(cells.length,4);
    assert.equal(cells[2].textContent,record.stars===5?`${record.pullsToFive} 抽出金${record.fromFirstRecord?'（首条记录起）':''}`:'—');
  });
  if(count){assert.equal(page.elements.get('next').disabled,false);page.elements.get('next').onclick();assert.equal(new URL(page.assigned).searchParams.get('p'),'1')}
  page.elements.get('pool').value='500';page.elements.get('pool').onchange();
  assert.equal(new URL(page.assigned).searchParams.get('gachaType'),'500');
  assert.equal(new URL(page.assigned).searchParams.get('p'),'0');
  assert.equal(new URL(page.assigned).searchParams.get('s'),'test-session');
  page.elements.get('refresh').onclick();assert(page.refreshed);
}
for(const schedule of [9101,9102,9103,9104]){
  const page=run(`logs/gacha-details-${schedule}.html`,`s=test-session&scheduleId=${schedule}`);
  assert(page.elements.get('five').children.length>0);
  assert(page.elements.get('rates').textContent.includes('%'));
  page.elements.get('history').onclick();
  assert.equal(new URL(page.assigned).searchParams.get('s'),'test-session');
}
console.log('PASS: real history rendering, empty states, paging, pool switch, refresh, detail lists and authenticated navigation.');
