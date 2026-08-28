'use strict';
// Seed the Ghost Owner over loopback before the public port opens (AzuraCast rule).
// Idempotent: if setup is already complete this is a no-op.
const http = require('http');
const PORT = process.env.SEED_PORT || '2369';
function req(method, path, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const r = http.request({ host: '127.0.0.1', port: PORT, path, method,
      headers: { 'Content-Type': 'application/json', 'Accept-Version': 'v6.0', 'X-Forwarded-Proto': 'https',
        ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {}) } },
      res => { let b = ''; res.on('data', c => b += c); res.on('end', () => resolve({ code: res.statusCode, body: b })); });
    r.on('error', reject); if (data) r.write(data); r.end();
  });
}
(async () => {
  const email = process.env.GHOST_ADMIN_EMAIL, password = process.env.GHOST_ADMIN_PASSWORD;
  const title = process.env.GHOST_BLOG_TITLE || 'My Ghost Site';
  const name = process.env.GHOST_ADMIN_NAME || 'Owner';
  if (!email || !password) { console.error('[seed-owner] missing email/password'); process.exit(2); }
  // wait for loopback API
  for (let i = 0; i < 60; i++) {
    try { const s = await req('GET', '/ghost/api/admin/authentication/setup/'); if (s.code === 200) { 
      const done = JSON.parse(s.body).setup[0].status;
      if (done) { console.error('[seed-owner] setup already complete'); process.exit(0); }
      break; } } catch (e) {}
    await new Promise(r => setTimeout(r, 2000));
  }
  const s = await req('POST', '/ghost/api/admin/authentication/setup/',
    { setup: [{ name, email, password, blogTitle: title }] });
  if (s.code === 201) { console.error('[seed-owner] owner created: ' + email); process.exit(0); }
  console.error('[seed-owner] setup failed ' + s.code + ' ' + s.body.slice(0, 200)); process.exit(1);
})().catch(e => { console.error('[seed-owner] error ' + e.message); process.exit(1); });
