// Local design preview only. No installation, uploads or writes through HTTP.
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.dirname(fileURLToPath(import.meta.url));
const types = {'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.png':'image/png','.md':'text/plain; charset=utf-8'};
http.createServer(async (req,res) => {
  try {
    if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405); res.end(); return; }
    const relative = decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\/+/, '') || 'mobile-m1/index.html';
    const target = path.resolve(root,relative);
    if (!target.startsWith(root+path.sep)) { res.writeHead(403); res.end(); return; }
    const bytes = await readFile(target);
    res.writeHead(200, {'Content-Type':types[path.extname(target)]||'application/octet-stream','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
    res.end(req.method === 'HEAD' ? undefined : bytes);
  } catch { res.writeHead(404); res.end('Not found'); }
}).listen(8775,'127.0.0.1',()=>console.log('ImageHub M1 refined preview: http://127.0.0.1:8775/mobile-m1/index.html'));
