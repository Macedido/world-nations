// World Nations — utilidades compartilhadas
const { useState, useEffect, useRef, useMemo } = React;
const html = htm.bind(React.createElement);
const CFG = window.WN_CONFIG || {};
const sb = supabase.createClient(CFG.url, CFG.key);
let D = null;                       // definições do jogo (lidas do banco: defs())
const bus = new EventTarget();
const toast = (msg, type = 'ok') => bus.dispatchEvent(new CustomEvent('toast', { detail: { msg, type, id: Math.random() } }));
let reloadNow = () => {};

// toda ação passa por uma função do servidor (nenhum valor é calculado no navegador)
async function rpc(fn, args, ok) {
  const { data, error } = await sb.rpc(fn, args);
  if (error) { toast(error.message, 'err'); throw error; }
  if (ok) toast(ok);
  reloadNow();
  return data;
}

const fmt = n => { n = +n || 0; const a = Math.abs(n);
  return a >= 1e9 ? (n / 1e9).toFixed(2) + ' bi' : a >= 1e6 ? (n / 1e6).toFixed(1) + ' mi' : a >= 1e4 ? (n / 1e3).toFixed(1) + ' mil'
    : a >= 100 ? Math.round(n).toLocaleString('pt-BR') : (Math.round(n * 10) / 10).toLocaleString('pt-BR'); };
const dur = ms => { if (ms <= 0) return 'pronto'; const s = Math.floor(ms / 1000), d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
  return d ? `${d}d ${h}h` : h ? `${h}h ${m}m` : `${m}m ${s % 60}s`; };
const when = t => new Date(t).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
let clockOff = 0;
const now = () => Date.now() + clockOff;
function useTick(ms = 1000) { const [, f] = useState(0); useEffect(() => { const i = setInterval(() => f(x => x + 1), ms); return () => clearInterval(i); }, [ms]); return now(); }

// geometria
const inPoly = ([x, y], r) => { let o = false; for (let i = 0, j = r.length - 1; i < r.length; j = i++) {
  const [xi, yi] = r[i], [xj, yj] = r[j]; if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) o = !o; } return o; };
const areaKm2 = p => { if (p.length < 3) return 0; const R = 6371, rad = Math.PI / 180; let s = 0;
  for (let i = 0; i < p.length; i++) { const a = p[i], b = p[(i + 1) % p.length]; s += (b[0] - a[0]) * rad * (2 + Math.sin(a[1] * rad) + Math.sin(b[1] * rad)); }
  return Math.abs(s * R * R / 2); };
const distKm = (a, b) => { const r = Math.PI / 180, dl = (b[1] - a[1]) * r, dg = (b[0] - a[0]) * r;
  const h = Math.sin(dl / 2) ** 2 + Math.cos(a[1] * r) * Math.cos(b[1] * r) * Math.sin(dg / 2) ** 2; return 12742 * Math.asin(Math.sqrt(h)); };
const rng = s => { s = (typeof s === 'string' ? [...s].reduce((a, c) => Math.imul(a ^ c.charCodeAt(0), 16777619), 2166136261) : s) >>> 0;
  return () => { s = s + 0x6D2B79F5 | 0; let t = Math.imul(s ^ s >>> 15, 1 | s); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; };
// ponto fixo (determinístico) dentro de um território, usado para desenhar construções
const spot = (t, seed) => { const r = t.g.coordinates[0], R = rng(String(seed));
  let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9; r.forEach(([x, y]) => { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); });
  for (let i = 0; i < 40; i++) { const p = [x0 + R() * (x1 - x0), y0 + R() * (y1 - y0)]; if (inPoly(p, r)) return p; } return t.pt; };

// construções ficam em volta da cidade principal da região (capital ou centro)
const hubOf = (S, t) => { const c = S.C[t.c]; return c && c.capital && inPoly(c.capital, t.g.coordinates[0]) ? c.capital : t.pt; };
const bspot = (S, t, id) => { const h = hubOf(S, t), R = rng('b' + id), a = R() * 6.283, d = .12 + R() * .3, p = [h[0] + Math.cos(a) * d * 1.3, h[1] + Math.sin(a) * d];
  return inPoly(p, t.g.coordinates[0]) ? p : h; };

// estado do mundo: índices para acesso rápido
function prep(s) {
  s.C = {}; s.countries.forEach(c => s.C[c.id] = c);
  s.T = {}; s.territories.forEach(t => { t.u = []; t.b = []; s.T[t.id] = t; });
  s.units.forEach(u => s.T[u.t] && s.T[u.t].u.push(u));
  s.buildings.forEach(b => s.T[b.t] && s.T[b.t].b.push(b));
  s.my = s.C[s.me]; s.R = {}; s.research.forEach(r => s.R[r.t] = r);
  clockOff = Date.parse(s.now) - Date.now();
  return s;
}
const done = (S, t) => S.R[t] && Date.parse(S.R[t].d) <= now();
const ready = x => Date.parse(x.d || x.r) <= now();
const myTerr = S => S.territories.filter(t => t.c === S.me);
const nb = (S, cid, k) => S.territories.filter(t => t.c === cid).reduce((a, t) => a + t.b.filter(b => b.k === k && ready(b)).length, 0);
const atWar = (S, a, b) => S.wars.some(w => !w.ended_at && ((w.attacker === a && w.defender === b) || (w.attacker === b && w.defender === a)));

const REL = { aliado: '#4f9a3c', 'amigável': '#9cc25e', neutro: '#9b9887', desconfiado: '#d8a63e', hostil: '#d6722c', inimigo: '#b5302a', 'você': '#d9bf6a' };
function relation(S, a, b) {
  if (!a || !b) return 'neutro'; if (a === b) return 'você';
  if (atWar(S, a, b)) return 'inimigo';
  const tr = S.treaties.filter(t => (t.a === a && t.b === b) || (t.a === b && t.b === a));
  const share = k => S.orgs.some(o => (!k || k.includes(o.kind)) && o.members.includes(a) && o.members.includes(b));
  if (tr.some(t => t.kind === 'defesa') || share(['alianca', 'federacao', 'coalizao'])) return 'aliado';
  if (tr.some(t => t.kind === 'sancao')) return 'hostil';
  if (tr.length || share()) return 'amigável';
  if ((S.C[b] && S.C[b].infamy > 40) || S.wars.some(w => !w.ended_at && (w.attacker === b))) return 'desconfiado';
  return 'neutro';
}

const FXN = { inc: 'renda', prod: 'produção', res: 'pesquisa', atk: 'ataque', def: 'defesa', atk_land: 'ataque terrestre', def_land: 'defesa terrestre', atk_air: 'ataque aéreo',
  def_air: 'defesa aérea', atk_sea: 'ataque naval', def_sea: 'defesa naval', happy: 'felicidade', stab: 'estabilidade', growth: 'crescimento', food: 'alimentos', build: 'velocidade de obras', spy: 'espionagem', dip: 'diplomacia' };
const fxTxt = fx => Object.entries(fx || {}).map(([k, v]) => `${v > 0 ? '+' : ''}${['happy', 'stab'].includes(k) ? v : Math.round(v * 100) + '%'} ${FXN[k] || k}`).join(', ');
ICONS.star = 'M256 32l62 147 151 13-115 100 36 149-134-83-134 83 36-149L43 192l151-13z';
function Ic({ n, s = 16, c, t }) { return html`<svg class="ic" viewBox="0 0 512 512" width=${s} height=${s} style=${c ? { color: c } : null}>${t && html`<title>${t}</title>`}<path d=${ICONS[n] || ''} fill="currentColor" /></svg>`; }
const RN = k => (D.res[k] || {}).n || k;
function Cost({ c, r, q = 1 }) { return html`<span class="cost">${c ? html`<span><${Ic} n="coins" s=${13} />${fmt(c * q)}</span>` : ''}${Object.entries(r || {}).map(([k, v]) => html`<span key=${k} title=${RN(k)}><${Ic} n=${k} s=${13} />${fmt(v * q)}</span>`)}</span>`; }
// textos de eventos vêm com um emoji no começo: vira ícone do tipo de evento
const EVI = { guerra: 'mil', alerta: 'fire', diplo: 'treaty', interno: 'fist', evento: 'globe', pesquisa: 'bulb', obra: 'infra', intel: 'eye', comercio: 'trade', militar: 'medal', sistema: 'castle', info: 'castle' };
const clean = t => String(t || '').replace(/^[^\p{L}\p{N}(]+/u, '');
const INTEL = ['Inexistente', 'Básico', 'Desenvolvido', 'Avançado', 'Elite'];
const GOODS = () => Object.keys(D.res).filter(k => D.res[k].g);
const RAW = () => Object.keys(D.res).filter(k => !D.res[k].g);
const leaderTitle = c => (D.gov[c.government] || {}).t || 'Chefe de Estado';
const age = n => 38 + (rng(n || 'x')() * 35 | 0);

// componentes pequenos
function Flag({ f, s = 22 }) { return f && f.startsWith('data:') ? html`<img class="flag" src=${f} style=${{ height: s }} />` : html`<span class="flag-e" style=${{ fontSize: s * .9 }}>${f || '🏳'}</span>`; }
function Btn({ onClick, children, cls = '', disabled, title }) {
  const [b, setB] = useState(false);
  return html`<button class=${'btn ' + cls} title=${title} disabled=${disabled || b}
    onClick=${async e => { e.stopPropagation(); setB(true); try { await onClick(); } catch (_) {} finally { setB(false); } }}>${b ? '…' : children}</button>`;
}
function Stat({ l, v, c, t }) { return html`<div class="stat" title=${t}><span>${l}</span><b class=${c || ''}>${v}</b></div>`; }
function Bar({ v, max = 100, c }) { return html`<div class="bar"><i style=${{ width: Math.max(0, Math.min(100, v / max * 100)) + '%', background: c }} /></div>`; }
function Tabs({ tabs, v, set }) { return html`<div class="tabs">${tabs.map(([k, n]) => html`<button key=${k} class=${v === k ? 'on' : ''} onClick=${() => set(k)}>${n}</button>`)}</div>`; }
function Chart({ data, keys, h = 110 }) {
  if (!data || data.length < 2) return html`<div class="muted small">O gráfico aparece após algumas horas de partida.</div>`;
  const W = 480;
  return html`<svg viewBox=${`0 0 ${W} ${h}`} class="chart">${keys.map(({ k, c, n }, i) => {
    const vs = data.map(d => +d[k]); const mn = Math.min(...vs), mx = Math.max(...vs), r = mx - mn || 1;
    const pts = vs.map((v, j) => `${(j / (vs.length - 1) * W).toFixed(1)},${(h - 6 - (v - mn) / r * (h - 22)).toFixed(1)}`).join(' ');
    return html`<g key=${k}><polyline points=${pts} fill="none" stroke=${c} stroke-width="2" /><text x=${6 + i * 150} y="12" fill=${c}>${n}: ${fmt(vs[vs.length - 1])}</text></g>`;
  })}</svg>`;
}
// imagem enviada → miniatura em data URL (bandeira / retrato)
const shrink = (file, w, h) => new Promise(ok => { const im = new Image(); im.onload = () => { const c = document.createElement('canvas'); c.width = w; c.height = h;
  const x = c.getContext('2d'), s = Math.max(w / im.width, h / im.height); x.drawImage(im, (w - im.width * s) / 2, (h - im.height * s) / 2, im.width * s, im.height * s);
  ok(c.toDataURL('image/jpeg', .8)); }; im.src = URL.createObjectURL(file); });
