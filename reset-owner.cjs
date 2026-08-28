'use strict';
// Re-apply the Owner password on every boot so a redeploy is a working reset.
// Best-effort: never crash a working instance over a failed reset.
const path = require('path');
function req(name, candidates) {
  for (const c of candidates) { try { return require(c); } catch (e) {} }
  throw new Error('cannot resolve ' + name);
}
const GI = process.env.GHOST_INSTALL || '/var/lib/ghost';
const V = process.env.GHOST_VERSION;
const store = `${GI}/versions/${V}/node_modules/.pnpm/node_modules`;
const bcrypt = req('bcryptjs', [`${store}/bcryptjs`, 'bcryptjs']);
const mysql = req('mysql2/promise', ['mysql2/promise', `${GI}/current/node_modules/mysql2/promise`]);

(async () => {
  const email = process.env.GHOST_ADMIN_EMAIL;
  const password = process.env.GHOST_ADMIN_PASSWORD;
  if (!email || !password) { console.error('[reset-owner] missing email/password, skip'); return; }
  const conn = await mysql.createConnection({
    host: process.env.database__connection__host,
    port: Number(process.env.database__connection__port || 3306),
    user: process.env.database__connection__user,
    password: process.env.database__connection__password,
    database: process.env.database__connection__database,
  });
  try {
    const [rows] = await conn.execute(
      "SELECT u.id FROM users u JOIN roles_users ru ON ru.user_id=u.id " +
      "JOIN roles r ON r.id=ru.role_id WHERE r.name='Owner' LIMIT 1");
    if (!rows.length) { console.error('[reset-owner] no Owner row yet, skip'); return; }
    const hash = bcrypt.hashSync(password, 10);
    await conn.execute("UPDATE users SET password=?, status='active', email=? WHERE id=?",
      [hash, email, rows[0].id]);
    console.error('[reset-owner] owner credential re-applied for ' + email);
  } finally { await conn.end(); }
})().catch(e => { console.error('[reset-owner] non-fatal: ' + e.message); });
