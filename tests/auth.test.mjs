import {test} from 'node:test';import assert from 'node:assert/strict';import worker from '../dist/server/index.js';import {database} from './d1.mjs';
const origin='https://halla.test';
function client(db){let cookie='';return {get cookie(){return cookie},async request(path,method='GET',body,overrides={}){const headers={Cookie:cookie,...(method!=='GET'?{'Content-Type':'application/json',Origin:origin}:{}),...overrides};const r=await worker.fetch(new Request(origin+path,{method,headers,...(body!==undefined?{body:JSON.stringify(body)}:{})}),{DB:db});if(r.headers.has('Set-Cookie'))cookie=r.headers.get('Set-Cookie').split(';')[0];return r;}}}
const credentials=(employee,password='Private-test-123!')=>({employee,password,confirmPassword:password});
const work=keyword=>({version:2,works:[{id:crypto.randomUUID(),keyword,note:'',registeredAt:'2026-11-11',docs:[{id:crypto.randomUUID(),type:'pay',title:'지급 문서',line:1,approvals:[],post:[],note:'',finalized:false}]}],officials:[],settings:{line:1}});
test('registration, server ownership, concurrency, logout and password protection',async()=>{
 const db=database(),a=client(db),b=client(db),anonymous=client(db);
 assert.equal((await anonymous.request('/')).status,303);assert.equal((await anonymous.request('/api/bootstrap')).status,401);assert.equal((await anonymous.request('/api/state','PUT',{state:work('attack'),revision:0})).status,401);
 assert.equal((await a.request('/api/register','POST',credentials('26733'))).status,200);
 assert.equal((await b.request('/api/register','POST',credentials('26734'))).status,200);
 const accounts=db.sql.prepare('SELECT * FROM member_accounts').all();assert.equal(accounts.length,2);assert.notEqual(accounts[0].salt,accounts[1].salt);assert.notEqual(accounts[0].password_hash,'Private-test-123!');assert.match(a.cookie,/^__Host-halla-session=[a-f0-9]{64}$/);assert.notEqual(db.sql.prepare('SELECT token_hash FROM member_sessions LIMIT 1').get().token_hash,a.cookie.split('=')[1]);
 const payload=work('A 계정 전용');let r=await a.request('/api/state','PUT',{state:payload,revision:0});assert.equal(r.status,200);assert.equal((await r.json()).revision,1);
 const aData=await (await a.request('/api/bootstrap')).json();assert.equal(aData.state.works[0].keyword,'A 계정 전용');assert.equal(aData.employee,'26733');
 const bData=await (await b.request('/api/bootstrap?employee=26733')).json();assert.equal(bData.employee,'26734');assert.deepEqual(bData.state.works,[]);
 assert.equal((await b.request('/api/state','PUT',{state:work('B 전용'),revision:0,employee:'26733'})).status,200);assert.equal((await (await a.request('/api/bootstrap')).json()).state.works[0].keyword,'A 계정 전용');
 assert.equal((await a.request('/api/state','PUT',{state:work('stale overwrite'),revision:0})).status,409);
 assert.equal((await a.request('/api/state','PUT',{state:payload,revision:1},{Origin:'https://evil.test'})).status,403);
 assert.equal((await a.request('/api/state','PUT',{state:{version:2},revision:1})).status,400);
 assert.equal((await a.request('/api/logout','POST',{})).status,200);assert.equal((await a.request('/api/bootstrap')).status,401);
 assert.equal((await a.request('/api/login','POST',credentials('26733','Wrong-test-123!'))).status,401);
 assert.equal((await a.request('/api/login','POST',credentials('26733'))).status,200);assert.equal((await (await a.request('/api/bootstrap')).json()).state.works[0].keyword,'A 계정 전용');
 db.sql.prepare('UPDATE member_sessions SET expires_at=0 WHERE employee=?').run('26733');assert.equal((await a.request('/api/bootstrap')).status,401);
 db.sql.close();
});
test('registration validation, duplicates, rate limits and response headers',async()=>{const db=database(),c=client(db);assert.equal((await c.request('/api/register','POST',credentials('abc'))).status,400);assert.equal((await c.request('/api/register','POST',credentials('123','short'))).status,400);assert.equal((await c.request('/api/register','POST',{...credentials('123'),confirmPassword:'mismatch'})).status,400);const r=await c.request('/api/register','POST',credentials('123'));assert.equal(r.status,200);assert.match(r.headers.get('Set-Cookie'),/HttpOnly; Secure; SameSite=Strict/);assert.equal(r.headers.get('Cache-Control'),'no-store');assert.equal((await c.request('/api/register','POST',credentials('123'))).status,409);let last;for(let i=0;i<11;i++)last=await c.request('/api/register','POST',credentials(String(400+i)));assert.equal(last.status,429);db.sql.close();});
