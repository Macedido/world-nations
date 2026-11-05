// World Nations — cidades e construções desenhadas no mapa (canvas).
// Tudo sai dos dados reais: população define o tamanho da cidade, cada construção aparece no lugar, tropas e carros circulam.
const CB = .05;                                     // um quarteirão, em graus (escala estilizada)
const IP = {}; const icon = k => IP[k] || (IP[k] = new Path2D(ICONS[k] || ICONS.castle));
const ROOF = ['#a8553a', '#5d6670', '#8b5a3a', '#3f7474', '#7b3d33', '#6b6f45'];
const SITE = { factory: [1.5, 1], power: [1.3, 1.1], mine: [1.2, 1.2], hospital: [.9, .7], school: [.85, .7], univ: [1.4, 1], lab: [1, .8], base: [1.9, 1.6],
  airport: [3.4, .9], port: [1.6, 1], farm: [2.6, 2], road: null, rail: null, city: null };

function makeCity(hub, size, ring, seed, cap, name) {
  const R = rng(seed), th = 0, cs = Math.cos(th), sn = Math.sin(th), kx = 1 / Math.cos(hub[1] * Math.PI / 180);
  const n = Math.ceil(Math.sqrt(size) * 1.5 + 1), r = n * CB, off = R() * 100, blocks = [];
  for (let i = -n; i <= n; i++) for (let j = -n; j <= n; j++) {
    const d = Math.hypot(i, j) / n * (.75 + N2.vn(i * .6 + off, j * .6) * .5); if (d > 1) continue;
    const x = hub[0] + (i * CB * cs - j * CB * sn) * kx, y = hub[1] + i * CB * sn + j * CB * cs;
    if (!inPoly([x, y], ring)) continue;
    const q = R(), z = i === 0 && j === 0 ? 'z' : q < .07 && d > .2 ? 'p' : d < .3 ? 'c' : d < .62 ? 'm' : 's';
    blocks.push({ x, y, z, h: R(), c: R() * 6 | 0, d });
  }
  return { hub, size, th, kx, r, n, blocks, cap, name, seed };
}
const toW = (C, u, v) => [C.hub[0] + (u * Math.cos(C.th) - v * Math.sin(C.th)) * C.kx, C.hub[1] + u * Math.sin(C.th) + v * Math.cos(C.th)];

function cityData(S) {
  const cities = [], sites = [], links = [], hubs = {};
  S.territories.forEach(t => {
    const c = S.C[t.c]; if (!c) return; const ring = t.g.coordinates[0], hub = hubOf(S, t), cap = hub !== t.pt;
    const nc = t.b.filter(b => b.k === 'city' && ready(b)).length;
    const C = makeCity(hub, 3 + Math.min(28, t.p / 1.6e6) + nc * 6 + (cap ? 6 : 0), ring, t.id, cap, cap ? c.capital_name : t.n); C.col = c.color; C.pop = t.p; C.t = t.id;
    cities.push(C); hubs[t.id] = C;
    let k = 0;
    t.b.forEach(b => {
      if (b.k === 'city') { const R = rng('cb' + b.id), a = R() * 6.28, p = [hub[0] + Math.cos(a) * C.r * 2.2 * C.kx, hub[1] + Math.sin(a) * C.r * 2.2];
        if (inPoly(p, ring)) cities.push(Object.assign(makeCity(p, 6, ring, 'cb' + b.id, false, ''), { col: c.color, pop: 2e6, t: t.id })); return; }
      if (!SITE[b.k]) return;
      const R = rng('s' + b.id), f = { factory: 1.25, power: 1.35, mine: 1.7, farm: 1.9, airport: 2.1, base: 2.4, port: 1.3 }[b.k] || .55;
      let p, tries = 0;
      do { const a = (b.k.match(/factory|power/) ? C.th + R() * 1.2 : R() * 6.28), dd = C.r * (f + R() * .35) + (b.k === 'farm' ? k++ * .02 : 0);
        p = [hub[0] + Math.cos(a) * dd * C.kx, hub[1] + Math.sin(a) * dd]; } while (!inPoly(p, ring) && ++tries < 12);
      if (b.k === 'port') { let best = 1e9; ring.forEach(q => { const dd = Math.hypot((q[0] - hub[0]) / C.kx, q[1] - hub[1]); if (dd < best) { best = dd; p = [hub[0] + (q[0] - hub[0]) * .97, hub[1] + (q[1] - hub[1]) * .97]; } }); }
      if (!inPoly(p, ring)) p = hub;
      sites.push({ k: b.k, x: p[0], y: p[1], ok: ready(b), id: b.id, th: C.th, kx: C.kx, col: c.color });
    });
  });
  // estradas e ferrovias ligam cada região à capital
  S.countries.filter(c => c.alive && c.capital).forEach(c => {
    const ts = S.territories.filter(t => t.c === c.id), cap = ts.find(t => hubs[t.id] && hubs[t.id].cap);
    ts.forEach(t => { if (!cap || t === cap) return; const has = k => t.b.concat(cap.b).some(b => b.k === k && ready(b));
      if (has('rail') || has('road')) links.push({ a: hubs[cap.id].hub, b: hubs[t.id].hub, rail: has('rail'), road: has('road') }); });
  });
  // tropas marcham perto do centro da região onde estão
  const troops = []; S.territories.forEach(t => { const g = {}; t.u.forEach(u => (g[u.c] = g[u.c] || []).push(u));
    Object.entries(g).forEach(([cid, us], i) => { const h = hubs[t.id] ? hubs[t.id].hub : t.pt; troops.push({ x: h[0] + .25 + i * .2, y: h[1] - .25, us, col: (S.C[cid] || {}).color || '#555' }); }); });
  return { cities, sites, links, troops };
}

// ---------- desenho ----------
function box(x, X, Y, w, h, H, wall, roof) {        // prédio com volume: parede frontal + telhado
  x.fillStyle = wall; x.fillRect(X, Y - H + h, w, H); x.fillStyle = roof; x.fillRect(X, Y - H, w, h);
  x.fillStyle = 'rgba(0,0,0,.18)'; x.fillRect(X + w * .5, Y - H, w * .5, h);
}
function windows(x, X, Y, w, H, s, night, seed) {
  if (w < 7 || H < 7) return; const g = Math.max(3, s / 9), R = rng(seed);
  for (let yy = Y + g * .6; yy < Y + H - g * .5; yy += g * 1.4) for (let xx = X + g * .5; xx < X + w - g * .6; xx += g * 1.3) {
    const lit = night && R() < .55; x.fillStyle = lit ? '#ffd770' : night ? '#2a2f3a' : 'rgba(40,60,80,.55)'; x.fillRect(xx, yy, g * .6, g * .7); }
}
function drawSite(x, st, p, s, night) {
  const [fw, fh] = SITE[st.k], w = fw * s, h = fh * s, X = p.x - w / 2, Y = p.y - h / 2;
  if (!st.ok) { x.strokeStyle = '#e3b33b'; x.setLineDash([4, 3]); x.lineWidth = 2; x.strokeRect(X, Y, w, h); x.setLineDash([]);
    x.strokeStyle = '#e3b33b'; x.beginPath(); x.moveTo(X + w * .2, Y + h); x.lineTo(X + w * .2, Y - h * .8); x.lineTo(X + w * .9, Y - h * .8); x.stroke(); return; }
  if (s < 9) { x.fillStyle = 'rgba(25,25,20,.85)'; x.beginPath(); x.arc(p.x, p.y, 8, 0, 6.3); x.fill(); x.strokeStyle = st.col; x.lineWidth = 1.5; x.stroke();
    x.save(); x.translate(p.x - 6, p.y - 6); x.scale(12 / 512, 12 / 512); x.fillStyle = '#efe6c8'; x.fill(icon(st.k)); x.restore(); return; }
  const H = s * .35;
  switch (st.k) {
    case 'farm': { const R = rng('f' + st.id); for (let i = 0; i < 3; i++) for (let j = 0; j < 2; j++) { const c = ['#c9b45a', '#8fae55', '#a77d4f', '#b9c56a'][R() * 4 | 0], fx = X + i * w / 3, fy = Y + j * h / 2;
        x.fillStyle = c; x.fillRect(fx + 1, fy + 1, w / 3 - 2, h / 2 - 2); x.strokeStyle = 'rgba(0,0,0,.12)'; x.lineWidth = 1;
        for (let k = fx + 3; k < fx + w / 3 - 2; k += Math.max(2, s / 10)) { x.beginPath(); x.moveTo(k, fy + 2); x.lineTo(k, fy + h / 2 - 2); x.stroke(); } }
      box(x, X + w * .42, Y + h * .4, s * .25, s * .18, s * .2, '#8e2f25', '#5e3a2a'); break; }
    case 'factory': box(x, X, Y + h * .3, w, h * .7, H, '#6d7378', '#8a9096');
      x.fillStyle = '#5c6268'; for (let i = 0; i < 4; i++) { x.beginPath(); x.moveTo(X + i * w / 4, Y + h * .3 - H + h * .7); x.lineTo(X + (i + 1) * w / 4, Y + h * .3 - H); x.lineTo(X + (i + 1) * w / 4, Y + h * .3 - H + h * .7); x.fill(); }
      x.fillStyle = '#7a3b2e'; x.fillRect(X + w * .78, Y - H * 1.6, s * .1, H * 1.6 + h * .3); x.fillRect(X + w * .62, Y - H * 1.3, s * .1, H * 1.3 + h * .3);
      windows(x, X, Y + h - H, w, H * .9, s, night, st.id); break;
    case 'power': box(x, X, Y + h * .4, w * .55, h * .6, H, '#7c7f74', '#9a9d90');
      x.fillStyle = '#c7c8c2'; x.beginPath(); const cx = X + w * .78, cw = w * .2; x.moveTo(cx - cw, Y + h); x.quadraticCurveTo(cx - cw * .5, Y + h * .2, cx - cw * .8, Y - H);
      x.lineTo(cx + cw * .8, Y - H); x.quadraticCurveTo(cx + cw * .5, Y + h * .2, cx + cw, Y + h); x.fill(); x.fillStyle = 'rgba(0,0,0,.15)'; x.fillRect(cx, Y - H, cw, h + H); break;
    case 'mine': for (let i = 0; i < 4; i++) { x.fillStyle = ['#8b6e4e', '#7a5f42', '#6a5138', '#57432f'][i]; x.beginPath(); x.ellipse(p.x, p.y, w / 2 * (1 - i * .22), h / 2 * (1 - i * .22), 0, 0, 6.3); x.fill(); }
      x.strokeStyle = '#3b3329'; x.lineWidth = Math.max(1, s / 20); x.beginPath(); x.moveTo(p.x, p.y); x.lineTo(X + w, Y - h * .2); x.stroke(); break;
    case 'port': x.fillStyle = '#8d8a80'; x.fillRect(X, Y + h * .45, w, h * .25); for (let i = 0; i < 3; i++) x.fillRect(X + w * (.15 + i * .3), Y - h * .3, w * .08, h * .8);
      for (let i = 0; i < 6; i++) { x.fillStyle = ['#b5452f', '#3e6fa3', '#d39b2a', '#4b8a4b'][i % 4]; x.fillRect(X + w * (.05 + i * .15), Y + h * .5, w * .11, h * .14); }
      x.strokeStyle = '#d27b1f'; x.lineWidth = Math.max(1.5, s / 18); x.beginPath(); x.moveTo(X + w * .2, Y + h * .55); x.lineTo(X + w * .2, Y - h * .6); x.lineTo(X + w * .5, Y - h * .6); x.stroke(); break;
    case 'airport': x.fillStyle = '#4b4d50'; x.fillRect(X, Y + h * .35, w, h * .3); x.strokeStyle = '#eee'; x.setLineDash([s * .15, s * .12]); x.lineWidth = Math.max(1, s / 30);
      x.beginPath(); x.moveTo(X + 4, Y + h * .5); x.lineTo(X + w - 4, Y + h * .5); x.stroke(); x.setLineDash([]);
      box(x, X + w * .35, Y - h * .1, w * .3, h * .3, H * .6, '#9aa3a8', '#c2c9cc'); x.fillStyle = '#d9dcd6'; x.fillRect(X + w * .7, Y - h * .6, s * .12, h * .6); break;
    case 'hospital': box(x, X, Y, w, h, H, '#d7d4cc', '#f1efe8'); x.fillStyle = '#c62828'; const c = Math.min(w, h) * .3;
      x.fillRect(p.x - c / 2, Y - H + h / 2 - c / 6, c, c / 3); x.fillRect(p.x - c / 6, Y - H + h / 2 - c / 2, c / 3, c); windows(x, X, Y + h - H, w, H, s, night, st.id); break;
    case 'school': x.fillStyle = '#7fa35a'; x.fillRect(X, Y, w, h); x.fillStyle = '#5a7fb0'; x.fillRect(X + w * .55, Y + h * .45, w * .4, h * .45);
      box(x, X, Y + h * .1, w * .5, h * .5, H * .7, '#b8664a', '#c9795c'); windows(x, X, Y + h * .6 - H * .7, w * .5, H * .7, s, night, st.id); break;
    case 'univ': x.fillStyle = '#86a862'; x.fillRect(X, Y, w, h); box(x, X + w * .1, Y + h * .15, w * .8, h * .35, H, '#c9b998', '#ddd0b2');
      x.fillStyle = '#7f9aa3'; x.beginPath(); x.arc(p.x, Y + h * .15 - H, s * .18, Math.PI, 0); x.fill(); windows(x, X + w * .1, Y + h * .5 - H, w * .8, H, s, night, st.id); break;
    case 'lab': box(x, X, Y + h * .2, w, h * .8, H * .8, '#cfd5d8', '#e9eef0'); x.fillStyle = '#b8c4ca';
      [.3, .7].forEach(f => { x.beginPath(); x.arc(X + w * f, Y + h * .2 - H * .8 + h * .4, s * .16, Math.PI, 0); x.fill(); }); break;
    case 'base': x.fillStyle = '#7b7f5a'; x.fillRect(X, Y, w, h); x.strokeStyle = '#4a4c36'; x.lineWidth = Math.max(2, s / 12); x.strokeRect(X, Y, w, h);
      for (let i = 0; i < 3; i++) box(x, X + w * .1, Y + h * (.15 + i * .27), w * .5, h * .15, H * .4, '#5d6145', '#6f7452');
      x.fillStyle = '#555'; x.fillRect(X + w * .8, Y + h * .1 - H, 2, H * 1.4); x.fillStyle = st.col; x.fillRect(X + w * .8 + 2, Y + h * .1 - H, s * .22, s * .14); break;
  }
}

function cityLayer(m, SR) {
  const pane = m.createPane('city'); pane.style.zIndex = 440; pane.style.pointerEvents = 'none';
  const pane2 = m.createPane('life'); pane2.style.zIndex = 445; pane2.style.pointerEvents = 'none';
  const A = L.DomUtil.create('canvas', '', pane), a = A.getContext('2d'), Bc = L.DomUtil.create('canvas', '', pane2), b = Bc.getContext('2d');
  let D0 = null, sig = null, org = null, last = 0;
  const data = () => { const S = SR.current; if (S && S !== sig) { sig = S; D0 = cityData(S); } return D0; };
  const fit = (cv, ctx) => { const sz = m.getSize(), pad = .25, w = sz.x * (1 + 2 * pad), h = sz.y * (1 + 2 * pad), dpr = Math.min(2, devicePixelRatio || 1);
    if (cv.width !== Math.round(w * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); cv.style.width = w + 'px'; cv.style.height = h + 'px'; }
    const tl = m.containerPointToLayerPoint([-sz.x * pad, -sz.y * pad]); L.DomUtil.setPosition(cv, tl); ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, w, h);
    return { ox: sz.x * pad, oy: sz.y * pad, w, h, tl }; };
  const nightAt = lng => { if (window.wnHour != null) return window.wnHour < 6 || window.wnHour > 19 ? 1 : 0; const t = ((new Date().getUTCHours() + new Date().getUTCMinutes() / 60 + lng / 15) % 24 + 24) % 24; return t < 5 ? 1 : t < 7 ? (7 - t) / 2 : t < 17.5 ? 0 : t < 19.5 ? (t - 17.5) / 2 : 1; };

  function drawStatic() {
    const Dd = data(), z = m.getZoom(), f = fit(A, a); org = f; if (!Dd || z < 5) return;
    const P = (lng, lat) => { const q = m.latLngToContainerPoint([lat, lng]); return { x: q.x + f.ox, y: q.y + f.oy }; }, vis = p => p.x > -60 && p.y > -60 && p.x < f.w + 60 && p.y < f.h + 60;
    const s0 = CB * 256 * Math.pow(2, z) / 360, night = z >= 7 ? nightAt(m.getCenter().lng) : 0, dark = night > .5;
    // estradas e ferrovias
    Dd.links.forEach(l => { const p = P(l.a[0], l.a[1]), q = P(l.b[0], l.b[1]);
      if (l.road) { a.strokeStyle = '#5f5a50'; a.lineWidth = Math.max(2, s0 * .14); a.beginPath(); a.moveTo(p.x, p.y); a.lineTo(q.x, q.y); a.stroke();
        if (s0 > 8) { a.strokeStyle = '#e6d9a8'; a.lineWidth = 1; a.setLineDash([6, 6]); a.stroke(); a.setLineDash([]); } }
      if (l.rail) { const o = l.road ? Math.max(4, s0 * .2) : 0; a.strokeStyle = '#2f2a24'; a.lineWidth = 2; a.beginPath(); a.moveTo(p.x + o, p.y + o); a.lineTo(q.x + o, q.y + o); a.stroke();
        a.setLineDash([1.5, 5]); a.lineWidth = 6; a.stroke(); a.setLineDash([]); } });
    Dd.cities.forEach(C => {
      const s = s0 * C.kx;
      const c0 = P(C.hub[0], C.hub[1]), rp = C.r * 256 * Math.pow(2, z) / 360 * 1.6; if (c0.x < -rp || c0.y < -rp || c0.x > f.w + rp || c0.y > f.h + rp) return;
      if (s < 4.5) { C.blocks.forEach(k => { const p = P(k.x, k.y); a.fillStyle = k.z === 'p' ? '#6f9a52' : k.z === 'c' ? '#5e5a55' : k.z === 'm' ? '#8d8476' : '#a47a60'; a.fillRect(p.x - s * .45, p.y - s * .45, s * .9, s * .9); }); return; }
      const bl = C.blocks.map(k => ({ k, p: P(k.x, k.y) })).filter(o => vis(o.p)).sort((u, v) => u.p.y - v.p.y);
      bl.forEach(({ p }) => { a.fillStyle = '#56544f'; a.fillRect(p.x - s / 2, p.y - s / 2, s, s); });               // asfalto
      bl.forEach(({ k, p }) => {
        const L0 = s * .72, X = p.x - L0 / 2, Y = p.y - L0 / 2;
        a.fillStyle = s > 16 ? '#b9b3a6' : '#8d867a'; a.fillRect(p.x - s * .4, p.y - s * .4, s * .8, s * .8);   // calçada
        a.fillStyle = { p: '#6f9a52', z: '#d6ccb5', c: '#a29c92', m: '#c4bba9', s: '#93ad6c' }[k.z]; a.fillRect(X, Y, L0, L0);
        if (s < 16) { if (k.z !== 'p' && k.z !== 'z') { a.fillStyle = k.z === 's' ? ROOF[k.c] : k.z === 'c' ? '#6f7d88' : '#a99a85'; const q = k.z === 's' ? .3 : .6;
            k.z === 's' ? [[.1, .1], [.55, .1], [.1, .55], [.55, .55]].forEach(([u, v]) => a.fillRect(X + L0 * u, Y + L0 * v, L0 * q, L0 * q)) : a.fillRect(X + L0 * .2, Y + L0 * .2, L0 * q, L0 * q); } return; }
        if (k.z === 'p') { const R = rng(C.seed + k.x); for (let i = 0; i < 7; i++) { a.fillStyle = i % 2 ? '#3f6b35' : '#4e7d3f'; a.beginPath(); a.arc(X + R() * L0, Y + R() * L0, s * (.06 + R() * .05), 0, 6.3); a.fill(); } return; }
        if (k.z === 'z') { a.fillStyle = '#7fb0c4'; a.beginPath(); a.arc(p.x, p.y, s * .14, 0, 6.3); a.fill(); a.fillStyle = '#6d6455'; a.fillRect(p.x - s * .03, p.y - s * .32, s * .06, s * .3); return; }
        if (k.z === 's') [[.08, .1], [.54, .1], [.08, .56], [.54, .56]].forEach(([u, v], i) => { const w = L0 * .36, hx = X + L0 * u, hy = Y + L0 * v;
          box(a, hx, hy + w * .25, w, w * .7, w * .45, dark ? '#4a4540' : '#e2d5ba', dark ? '#3a3a40' : ROOF[(k.c + i) % 6]);
          if (s > 40) { a.fillStyle = dark && (k.c + i) % 3 ? '#ffd770' : '#5b4a3a'; a.fillRect(hx + w * .4, hy + w * .65, w * .2, w * .3); } });
        if (k.z === 'm') [0, .5].forEach((v, i) => { const H = s * (.3 + k.h * .25); box(a, X + L0 * .05, Y + L0 * (v + .05) + L0 * .1, L0 * .9, L0 * .3, H, dark ? '#4b463f' : '#cbbd9f', dark ? '#3b3b41' : '#9d8f7a');
          windows(a, X + L0 * .05, Y + L0 * (v + .05) + L0 * .4 - H, L0 * .9, H, s, dark, C.seed + k.x + i); });
        if (k.z === 'c') { const H = s * (.45 + k.h * .8), w = L0 * .7; box(a, X + L0 * .15, Y + L0 * .4, w, w * .6, H, dark ? '#2e3742' : '#6d8191', dark ? '#3a4552' : '#94a7b3');
          windows(a, X + L0 * .15, Y + L0 * .4 + w * .6 - H, w, H, s, dark, C.seed + k.x); }
      });
    });
    Dd.sites.forEach(st => { const p = P(st.x, st.y); if (vis(p)) drawSite(a, st, p, s0 * st.kx, dark); });
    if (night > 0) { a.fillStyle = `rgba(8,14,38,${night * .5})`; a.globalCompositeOperation = 'multiply'; a.fillRect(0, 0, f.w, f.h); a.globalCompositeOperation = 'source-over'; }
  }

  // camada animada: carros, trens, fumaça, navios, aviões, pedestres e tropas
  const frame = t => {
    requestAnimationFrame(frame); if (t - last < 40) return; last = t;
    const Dd = data(), z = m.getZoom(); if (!Dd || z < 6 || !org) { b.clearRect(0, 0, Bc.width, Bc.height); return; }
    const f = fit(Bc, b), P = (lng, lat) => { const q = m.latLngToContainerPoint([lat, lng]); return { x: q.x + f.ox, y: q.y + f.oy }; }, vis = p => p.x > -20 && p.y > -20 && p.x < f.w + 20 && p.y < f.h + 20;
    const s = CB * 256 * Math.pow(2, z) / 360, T = t / 1000, night = z >= 7 && nightAt(m.getCenter().lng) > .5;
    Dd.links.forEach((l, i) => { const p = P(l.a[0], l.a[1]), q = P(l.b[0], l.b[1]);
      if (l.rail) { const u = (T * .03 + i * .37) % 1; for (let k = 0; k < 5; k++) { const v = ((u - k * .008) % 1 + 1) % 1, x = p.x + (q.x - p.x) * v + 4, y = p.y + (q.y - p.y) * v + 4; b.fillStyle = k ? '#7a3324' : '#1d1d1d'; b.fillRect(x - 3, y - 2, 6, 4); } }
      if (l.road) for (let k = 0; k < 6; k++) { const v = ((T * (.02 + k * .004) * (k % 2 ? 1 : -1) + k * .17 + i * .3) % 1 + 1) % 1, x = p.x + (q.x - p.x) * v, y = p.y + (q.y - p.y) * v;
        if (!vis({ x, y })) continue; b.fillStyle = night ? '#ffe9a0' : ['#c23b2c', '#2d5d9f', '#e6e1d3', '#2f2f2f'][k % 4]; b.fillRect(x - 2, y - 1.5, 4, 3); } });
    if (z >= 7) Dd.cities.forEach(C => { const c0 = P(C.hub[0], C.hub[1]), rp = C.r * 256 * Math.pow(2, z) / 360 * 1.4; if (c0.x < -rp || c0.y < -rp || c0.x > f.w + rp || c0.y > f.h + rp) return;
      const R = rng(C.seed + 'v'), nc = Math.min(50, 8 + C.size * 2);
      for (let i = 0; i < nc; i++) { const lane = (Math.floor(R() * C.n * 2) - C.n + .5) * CB, dir = R() < .5, sp = .3 + R() * .5, u = ((T * sp * CB * 2 + R() * 2 * C.r) % (2 * C.r)) - C.r;
        const w = toW(C, dir ? u : lane, dir ? lane : u), p = P(w[0], w[1]); if (!vis(p)) continue; const k = Math.max(2.5, s / 9);
        b.fillStyle = night ? '#ffe39a' : ['#b8352a', '#2c5aa0', '#e8e3d4', '#333', '#d9a62a'][i % 5]; b.fillRect(p.x - k / 2, p.y - k / 3, k, k * .66); }
      if (z >= 10) for (let i = 0; i < 70; i++) { const bk = C.blocks[(R() * C.blocks.length) | 0]; if (!bk) break; const ph = T * (.05 + R() * .08) + R() * 4, e = .45 * CB * Math.cos(ph), e2 = .45 * CB * Math.sin(ph * 1.3);
        const p = P(bk.x + e / Math.cos(bk.y * Math.PI / 180), bk.y + e2); if (!vis(p)) continue; const k = Math.max(1.5, s / 40);
        b.fillStyle = `hsl(${R() * 360},40%,40%)`; b.fillRect(p.x - k / 2, p.y, k, k * 1.8); b.fillStyle = '#e5c29b'; b.beginPath(); b.arc(p.x, p.y - k * .3, k * .5, 0, 6.3); b.fill(); }
    });
    Dd.sites.forEach((st, i) => { if (!st.ok) return; const p = P(st.x, st.y); if (!vis(p)) return;
      if ((st.k === 'factory' || st.k === 'power') && z >= 7) for (let k = 0; k < 8; k++) { const ph = ((T * .25 + k / 8 + i * .13) % 1), r = s * (.08 + ph * .35);
        b.fillStyle = `rgba(${st.k === 'power' ? '235,235,235' : '90,90,90'},${(1 - ph) * .45})`; b.beginPath(); b.arc(p.x + s * .5 + ph * s * .4, p.y - s * .4 - ph * s * 1.4, r, 0, 6.3); b.fill(); }
      if (st.k === 'port') for (let k = 0; k < 2; k++) { const ph = T * .05 + k * 3 + i, x = p.x + Math.cos(ph) * s * 2.2, y = p.y + s * 1.2 + Math.sin(ph) * s * .8, w = Math.max(10, s * .5);
        b.fillStyle = '#3b3e44'; b.beginPath(); b.moveTo(x - w / 2, y); b.lineTo(x + w / 2, y); b.lineTo(x + w * .35, y + w * .25); b.lineTo(x - w * .4, y + w * .25); b.fill();
        b.fillStyle = ['#b5452f', '#3e6fa3', '#d39b2a'][k % 3]; b.fillRect(x - w * .3, y - w * .15, w * .5, w * .15); }
      if (st.k === 'airport') { const ph = (T * .06 + i) % 1, R0 = s * 3, ang = ph * 6.283, x = p.x + Math.cos(ang) * R0, y = p.y + Math.sin(ang) * R0 * .6, k = Math.max(16, s * .5);
        b.save(); b.translate(x, y); b.rotate(ang + Math.PI); b.scale(k / 512, k / 512); b.translate(-256, -256); b.fillStyle = '#f4f4f0'; b.fill(icon('plane')); b.restore(); }
    });
    if (z >= 7) Dd.troops.forEach(tr => { const p = P(tr.x, tr.y); if (!vis(p)) return; const k = Math.max(2, s / 12);
      tr.us.slice(0, 16).forEach((u, i) => { const col = i % 4, row = i / 4 | 0, mv = !ready(u) ? Math.sin(T * 6 + i) * k * .3 : 0, x = p.x + col * k * 3 + (T * (ready(u) ? 0 : 6)) % (k * 3), y = p.y + row * k * 3 + mv;
        if (u.k === 'tank' || u.k === 'armor') { b.fillStyle = tr.col; b.fillRect(x - k, y - k * .6, k * 2, k * 1.2); b.fillStyle = '#222'; b.fillRect(x, y - k * .15, k * 1.4, k * .3); }
        else { b.fillStyle = tr.col; b.fillRect(x - k * .4, y - k * .2, k * .8, k * 1.2); b.fillStyle = '#3f4a2c'; b.beginPath(); b.arc(x, y - k * .5, k * .45, 0, 6.3); b.fill(); } }); });
  };
  m.on('moveend zoomend viewreset resize', drawStatic); setInterval(drawStatic, 60000);
  requestAnimationFrame(frame);
  return { redraw: drawStatic };
}
