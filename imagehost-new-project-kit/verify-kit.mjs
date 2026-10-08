// Resource-package integrity only. Does not execute application or device tests.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const root=path.dirname(fileURLToPath(import.meta.url));
const manifest=JSON.parse(fs.readFileSync(path.join(root,'MANIFEST.json'),'utf8'));
const failures=[];
function allFiles(directory){return fs.readdirSync(directory,{withFileTypes:true}).flatMap(e=>e.isDirectory()?allFiles(path.join(directory,e.name)):[path.relative(root,path.join(directory,e.name)).replaceAll('\\','/')]);}
const listed=new Set([...manifest.files.map(e=>e.path),'MANIFEST.json']);
for(const relative of allFiles(root))if(!listed.has(relative))failures.push('Unlisted resource: '+relative);
for(const entry of manifest.files){
  const file=path.resolve(root,entry.path);
  if(!file.startsWith(root+path.sep)||!fs.existsSync(file)){failures.push('Missing/outside package: '+entry.path);continue;}
  const data=fs.readFileSync(file);
  if(data.length!==entry.bytes||crypto.createHash('sha256').update(data).digest('hex')!==entry.sha256)failures.push('Changed: '+entry.path);
}
let localReferences=0;
function reference(from,target){
  if(!target||target.startsWith('#')||/^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(target)||target.includes('${')||from.endsWith('.js')&&/(?:'\s*\+|\+\s*')/.test(target))return;
  localReferences++;
  const resolved=path.resolve(path.dirname(from),decodeURIComponent(target.split(/[?#]/)[0]));
  if(!resolved.startsWith(root+path.sep)||!fs.existsSync(resolved))failures.push('Unresolved '+path.relative(root,from)+': '+target);
}
for(const {path:relative} of manifest.files){
  if(!/\.(md|html|css|js)$/.test(relative))continue;
  const file=path.join(root,relative),content=fs.readFileSync(file,'utf8');
  if(relative.endsWith('.md'))for(const match of content.matchAll(/\[[^\]]+\]\(([^)]+)\)/g))reference(file,match[1]);
  if(relative.endsWith('.html')||relative.endsWith('.js'))for(const match of content.matchAll(/(?:href|src)="([^"\s]+)"/g))reference(file,match[1]);
  if(relative.endsWith('.css'))for(const match of content.matchAll(/url\((?:["']?)([^)"']+)(?:["']?)\)/g))reference(file,match[1]);
  if(relative.endsWith('.js'))new Function(content);
}
if(failures.length){console.error(failures.join('\n'));process.exitCode=1;}
else console.log(JSON.stringify({status:'resource-integrity-passed',files:manifest.files.length,localReferences,applicationTestsExecuted:false},null,2));
