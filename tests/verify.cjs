const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('assert');
const root=path.join(__dirname,'..'), html=fs.readFileSync(path.join(root,'index.html'),'utf8');let count=0;
function check(ok,label){assert.ok(ok,label);count++;console.log('PASS:',label)}
class E{constructor(){this.handlers={};this.classList={add(){},remove(){}};this.textContent='';this.open=false}addEventListener(k,f){(this.handlers[k]??=[]).push(f)}async fire(k,e={}){for(const f of this.handlers[k]||[])await f(e)}contains(t){return t===this}querySelector(){return summary}focus(){this.focused=true}click(){this.clicked=true}remove(){}scrollIntoView(){this.scrolled=true}}
const ids=Object.fromEntries([...html.matchAll(/\bid="([^"]+)"/g)].map(m=>[m[1],new E()]));
ids['standby-command'].textContent=html.match(/<pre id="standby-command">([\s\S]*?)<\/pre>/)[1];
const menu=new E(),summary=new E(),launchers=[...html.matchAll(/\bdata-launcher\b/g)].map(()=>new E()),links=Array.from({length:6},()=>new E());let created,copied='',selected=false,blob;
const doc=new E();doc.querySelector=s=>s==='.nav-downloads'?menu:ids[s.slice(1)];doc.querySelectorAll=s=>s==='[data-launcher]'?launchers:s==='.nav-download-menu a'?links:[];doc.createElement=()=>created=new E();doc.body={appendChild(){}};doc.createRange=()=>({selectNodeContents(){selected=true}});
const context={window:{getSelection:()=>({removeAllRanges(){},addRange(){}})},document:doc,navigator:{userAgent:'Windows',clipboard:{writeText:async t=>copied=t}},Blob,URL:{createObjectURL:b=>{blob=b;return 'blob:fixture'},revokeObjectURL(){}},setTimeout:()=>1,clearTimeout(){}};
vm.runInNewContext(fs.readFileSync(path.join(root,'launcher-data.js'),'utf8'),context);
vm.runInNewContext(fs.readFileSync(path.join(root,'app.js'),'utf8'),context);
(async()=>{
check(!html.includes('YOUR SESSION CHECKLIST'),'session checklist removed');
check(html.includes('STANDBY METHOD')&&ids['standby-command'].textContent.includes('SecurityProtocol'),'standby steps and complete command are present');
check(launchers.length===4,'all four launcher links use download handler');
for(const launcher of launchers){let prevented=false;await launcher.fire('click',{preventDefault(){prevented=true}});check(prevented&&created.download==='Start-DSS-Online.cmd'&&created.clicked,'launcher saves CMD instead of navigating to source');}
check(blob.type==='application/octet-stream','binary-download MIME type used');
const cmd=fs.readFileSync(path.join(root,'downloads/Start-DSS-Online.cmd'),'utf8').replace(/\r?\n/g,'\r\n');check(await blob.text()===cmd,'downloaded launcher matches real CMD exactly');
await ids['copy-command'].fire('click');check(copied.includes('-bor 3072')&&copied.includes('| iex'),'copy action includes both command lines');
context.navigator.clipboard.writeText=async()=>{throw Error('Clipboard denied')};await ids['copy-command'].fire('click');check(selected,'clipboard denial offers manual selection');
context.window.DSS_LAUNCHER='';await launchers[0].fire('click',{preventDefault(){}});check(ids['standby-command'].scrolled&&ids.toast.textContent.includes('standby'),'unavailable launcher directs user to fallback');
menu.open=true;await doc.fire('keydown',{key:'Escape'});check(!menu.open&&summary.focused,'Escape closes download menu');
const idList=[...html.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]);check(new Set(idList).size===idList.length,'HTML IDs unique');
for(const m of html.matchAll(/(?:href|src)="([^"]+)"/g)){if(!m[1].startsWith('#')&&!m[1].startsWith('https://'))assert.ok(fs.existsSync(path.join(root,m[1])),m[1]);}check(true,'local asset links resolve');
console.log('TOTAL PASS:',count);
})().catch(e=>{console.error(e);process.exitCode=1});
