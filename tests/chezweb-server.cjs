// Disposable loopback protocol fixtures; no user documents or AI programs.
const fs=require('fs'),os=require('os'),path=require('path'),cp=require('child_process'),http=require('http'),assert=require('assert');
const root=path.resolve(__dirname,'..'),dir=fs.mkdtempSync(path.join(os.tmpdir(),'chezweb-server-test-')),token='test-token-with-no-credentials';
fs.writeFileSync(path.join(dir,'initial'),'Original fixture\n');fs.writeFileSync(path.join(dir,'name'),'fixture.md');
const child=cp.spawn(path.join(root,'chezweb-server'),[root,dir,token],{stdio:'inherit'});
async function request(url,method='GET',body='',headers={}){return await new Promise((resolve,reject)=>{const q=http.request(url,{method,headers:{...headers,...(method==='PUT'?{'Content-Length':Buffer.byteLength(body)}:{})}},r=>{let text='';r.on('data',x=>text+=x);r.on('end',()=>resolve({status:r.statusCode,text}));});q.on('error',reject);q.end(body);});}
(async()=>{try{
 const ready=path.join(dir,'ready');for(let n=0;n<100&&!fs.existsSync(ready);n++)await new Promise(r=>setTimeout(r,20));
 const url=fs.readFileSync(ready,'utf8').trim(),origin=new URL(url).origin;
 assert.equal((await request(url)).status,200);assert.equal((await request(url+'session')).text,'Original fixture\n');
 assert.equal((await request(origin+'/wrong-token/session')).status,403);
 assert.equal((await request(url+'session','GET','',{Host:'evil.example'})).status,403);
 assert.equal((await request(url+'session','GET','',{Origin:'https://evil.example'})).status,403);
 assert.equal((await request(url+'session','PUT','Bad',{'Content-Type':'text/plain',Origin:origin})).status,405);
 assert.equal((await request(url+'session','PUT','Bad',{'Content-Type':'application/x-chezweb-text'})).status,405);
 assert(!fs.existsSync(path.join(dir,'pending')));
 assert.equal((await request(url+'session','PUT','Saved fixture é\n',{'Content-Type':'application/x-chezweb-text',Origin:origin})).status,200);
 assert.equal(fs.readFileSync(path.join(dir,'pending'),'utf8'),'Saved fixture é\n');
 assert.equal((await request(url+'session')).text,'Saved fixture é\n');
 for(const name of ['codex','claude','shell','files','../README.md','%2e%2e/README.md'])assert([403,404].includes((await request(url+name)).status));
 console.log('PASS loopback token, Host, Origin, explicit writes, reload state, traversal and absent AI/shell endpoints');
 }finally{child.kill();await new Promise(r=>child.once('exit',r));fs.rmSync(dir,{recursive:true,force:true});}
})().catch(e=>{console.error(e);process.exitCode=1;});
