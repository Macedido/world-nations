// World Nations — mapa: terreno próprio, camadas temáticas, editor de fronteiras e cidades
const RESC = { oil: '#2b2b2b', iron: '#8a8f99', coal: '#4a4a4a', gold: '#e3b928', uranium: '#7bd23b', copper: '#c56a2d', alu: '#b9c4cc', rare: '#a24fd1', wood: '#4d7a31', food: '#d7c45a' };
const heat = v => `hsl(${50 - v * 50},75%,${62 - v * 25}%)`;
const LEVEL = z => z >= 10 ? 4 : z >= 7 ? 3 : z >= 5 ? 2 : 1;
const svgI = (k, s, c = 'currentColor') => `<svg viewBox="0 0 512 512" width="${s}" height="${s}"><path fill="${c}" d="${ICONS[k] || ''}"/></svg>`;

// onde o desenho cai: ilha isolada (encolhe), litoral (normal) ou interior cercado de vizinhos (cresce) — o servidor decide de verdade
function placeKind(pts, S) {
  if (pts.length < 3 || !S.territories.length) return { k: 'litoral', f: 1 };
  const ring = pts.concat([pts[0]]), others = S.territories.map(t => t.g.coordinates[0]);
  const dSeg = (p, a, b) => { const kx = Math.cos(p[1] * Math.PI / 180) * 111, ax = (a[0] - p[0]) * kx, ay = (a[1] - p[1]) * 111, bx = (b[0] - p[0]) * kx, by = (b[1] - p[1]) * 111;
    const dx = bx - ax, dy = by - ay, t = cl(-(ax * dx + ay * dy) / (dx * dx + dy * dy || 1)); return Math.hypot(ax + dx * t, ay + dy * t); };
  const dTo = p => Math.min(...others.map(r => inPoly(p, r) ? 0 : Math.min(...r.slice(1).map((q, i) => dSeg(p, r[i], q)))));
  const samples = []; for (let i = 0; i < pts.length; i++) for (let k = 0; k < 8; k++) { const a = ring[i], b = ring[i + 1]; samples.push([a[0] + (b[0] - a[0]) * k / 8, a[1] + (b[1] - a[1]) * k / 8]); }
  const ds = samples.map(dTo), mn = Math.min(...ds);
  if (mn > 600) return { k: 'ilha isolada', f: .42 };
  return ds.filter(d => d < 40).length / ds.length >= .35 ? { k: 'interior', f: 1.82 } : { k: 'litoral', f: 1 };
}

function WorldMap({ S, mode, sel, setSel, draw, setDraw }) {
  const div = useRef(), M = useRef(), G = useRef({}), drawR = useRef(draw), SR = useRef(S);
  const [z, setZ] = useState(3);
  drawR.current = draw; SR.current = S;

  useEffect(() => {
    const m = L.map(div.current, { zoomControl: false, minZoom: 2, maxZoom: 13, maxBounds: [[-85, -200], [85, 200]], attributionControl: false }).setView([28, 10], 3);
    L.control.zoom({ position: 'bottomright' }).addTo(m);
    G.current = { terrain: new TerrainLayer().addTo(m), terr: L.layerGroup().addTo(m), deco: L.layerGroup().addTo(m), draw: L.layerGroup().addTo(m) };
    G.current.city = cityLayer(m, SR);
    m.on('zoomend', () => setZ(m.getZoom()));
    m.on('click', e => {
      const d = drawR.current; if (!d) return setSel(null);
      const ll = e.latlng, p = [+ll.lng.toFixed(4), +ll.lat.toFixed(4)];
      if (d.stage === 'poly') setDraw({ ...d, pts: [...d.pts, p] });
      else if (d.stage === 'cap') inPoly(p, d.pts) ? setDraw({ ...d, cap: p, stage: 'form' }) : toast('A capital precisa ficar dentro do território', 'err');
    });
    M.current = window.wnMap = m;
    return () => m.remove();
  }, []);

  useEffect(() => { if (S && G.current.terrain) { G.current.terrain.setTerr(S.territories); G.current.city.redraw(); } }, [S]);

  // fronteiras e camadas temáticas
  useEffect(() => {
    const m = M.current; if (!m || !S) return;
    const { terr, deco } = G.current; terr.clearLayers(); deco.clearLayers();
    const lv = LEVEL(z), maxD = Math.log(1 + Math.max(1, ...S.territories.map(t => t.p / Math.max(1, t.a)))), maxG = Math.max(1, ...S.countries.map(c => +c.gdp || 0));
    S.territories.forEach(t => {
      const c = S.C[t.c], top = Object.entries(t.r || {}).sort((a, b) => b[1] - a[1])[0];
      let fill = c ? c.color : '#3a3530', op = lv >= 3 ? .1 : .32;
      if (mode === 'terreno') op = 0;
      if (mode === 'militar') { fill = REL[relation(S, S.me, t.c)] || '#777'; op = .42; }
      if (mode === 'recursos') { fill = top && top[1] > 0 ? RESC[top[0]] : '#999'; op = .5; }
      if (mode === 'pop') { fill = heat(Math.log(1 + t.p / Math.max(1, t.a)) / maxD); op = .55; }
      if (mode === 'econ') { fill = c ? heat((+c.gdp || 0) / maxG) : '#999'; op = .55; }
      if (mode === 'diplo') { fill = c ? REL[relation(S, S.me, t.c)] : '#999'; op = .5; }
      const on = sel && sel.t === t.id, war = mode === 'militar' && c && S.wars.some(w => !w.ended_at && (w.attacker === t.c || w.defender === t.c));
      const lay = L.geoJSON(t.g, { style: { fillColor: fill, fillOpacity: op, color: on ? '#ffe08a' : war ? '#c0261e' : c ? c.color : '#1f1b16',
        weight: on ? 3.5 : lv >= 3 ? 2 : 2.6, opacity: .95, dashArray: t.o || !c ? '7 5' : null } });
      lay.on('click', e => { if (drawR.current) return; L.DomEvent.stop(e); setSel({ t: t.id }); });
      lay.bindTooltip(`<b>${c ? c.name : 'Sem governo / rebeldes'}</b><br>${t.n} · ${t.te}${t.o ? ' · ocupado' : ''}`, { sticky: true, className: 'tt' });
      lay.addTo(terr);
      const at = [t.pt[1], t.pt[0]];
      if (mode === 'recursos') deco.addLayer(L.marker(at, { interactive: false, icon: L.divIcon({ className: 'res-i', iconSize: null,
        html: Object.entries(t.r || {}).filter(e => e[1] > 0).sort((a, b) => b[1] - a[1]).slice(0, 4).map(([k]) => `<i style="color:${RESC[k]}">${svgI(k, 18)}</i>`).join('') }) }));
      if (mode === 'pop') deco.addLayer(L.marker(at, { interactive: false, icon: L.divIcon({ className: 'lbl-i', iconSize: null, html: fmt(t.p) }) }));
      if (lv === 2 && c) deco.addLayer(L.marker([at[0] - .35, at[1]], { interactive: false, icon: L.divIcon({ className: 'rname', iconSize: null, html: t.n }) }));
      // divisões militares no estilo contador de tabuleiro
      const g = {}; t.u.forEach(u => (g[u.c] = g[u.c] || []).push(u));
      if (mode === 'militar' || lv <= 2) Object.entries(g).forEach(([cid, us], i) => { const hv = us.some(u => /tank|armor/.test(u.k)), cc = S.C[cid] || {};
        deco.addLayer(L.marker([at[0] - .9 * i - .7, at[1] + 1], { interactive: false, icon: L.divIcon({ className: 'army', iconSize: null,
          html: `<b style="--c:${cc.color || '#555'}">${svgI(hv ? 'tank' : 'inf', 15, '#f3ecd2')}<span>${us.length}</span></b>` }) })); });
    });
    if (mode === 'militar') S.wars.filter(w => !w.ended_at).forEach(w => {
      const A = S.territories.filter(t => t.c === w.attacker), B = S.territories.filter(t => t.c === w.defender);
      A.forEach(a => B.forEach(b => { if (distKm(a.pt, b.pt) < 900) deco.addLayer(L.polyline([[a.pt[1], a.pt[0]], [b.pt[1], b.pt[0]]], { color: '#c0261e', weight: 5, dashArray: '2 9', lineCap: 'round', opacity: .9, interactive: false })); }));
    });
    // nomes de países no estilo de mapa histórico + capitais
    S.countries.filter(c => c.alive && c.capital).forEach(c => {
      const ts = S.territories.filter(t => t.c === c.id); if (!ts.length) return;
      const big = ts.reduce((a, b) => a.a > b.a ? a : b), fs = Math.max(11, Math.min(46, Math.sqrt(c.area) / 30 * Math.pow(2, z - 3)));
      if (lv <= 2 && !['recursos', 'pop'].includes(mode)) deco.addLayer(L.marker([big.pt[1] + 1.2, big.pt[0]], { interactive: false,
        icon: L.divIcon({ className: 'cname-map', iconSize: null, html: `<span style="font-size:${fs}px">${c.name}</span>` }) }));
      const mk = L.marker([c.capital[1], c.capital[0]], { icon: L.divIcon({ className: 'cap', iconSize: null, html: `<i>${svgI('star', 15)}</i><span>${c.capital_name}</span>` }) });
      mk.on('click', e => { L.DomEvent.stop(e); setSel({ c: c.id }); }); deco.addLayer(mk);
    });
  }, [S, mode, sel, z]);

  // editor: vértices arrastáveis, clique direito apaga
  useEffect(() => {
    const g = G.current.draw; if (!g) return; g.clearLayers(); if (!draw) return;
    const pts = draw.pts, ll = pts.map(p => [p[1], p[0]]);
    const poly = pts.length > 2 ? L.polygon(ll, { color: '#ffd24a', weight: 2, fillColor: '#c8b26a', fillOpacity: .35, dashArray: '6 4', interactive: false }) : L.polyline(ll, { color: '#ffd24a', interactive: false });
    g.addLayer(poly);
    if (draw.stage === 'poly') pts.forEach((p, i) => {
      const mk = L.marker([p[1], p[0]], { draggable: true, icon: L.divIcon({ className: 'vtx', iconSize: [12, 12] }) });
      mk.on('drag', e => { ll[i] = e.latlng; poly.setLatLngs(ll); });
      mk.on('dragend', e => { const q = e.target.getLatLng(); const n = pts.slice(); n[i] = [+q.lng.toFixed(4), +q.lat.toFixed(4)]; setDraw({ ...drawR.current, pts: n }); });
      mk.on('contextmenu', () => setDraw({ ...drawR.current, pts: pts.filter((_, j) => j !== i) }));
      g.addLayer(mk);
    });
    if (draw.cap) g.addLayer(L.marker([draw.cap[1], draw.cap[0]], { icon: L.divIcon({ className: 'cap', iconSize: null, html: `<i>${svgI('star', 15)}</i>` }) }));
  }, [draw]);

  useEffect(() => { if (S && S.my && S.my.capital && M.current && !M.current._wnc) { M.current._wnc = 1; M.current.setView([S.my.capital[1], S.my.capital[0]], 5); } }, [S]);
  return html`<div class=${'map lv' + LEVEL(z)} ref=${div}><div class="zlv">${['', 'Visão mundial', 'Visão regional', 'Visão urbana', 'Visão detalhada'][LEVEL(z)]}</div></div>`;
}
