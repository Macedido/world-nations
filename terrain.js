// World Nations — mundo fictício: oceano e relevo gerados no navegador.
// Cada desenho de país vira terra de verdade; o tipo de terreno da região (dado do servidor) define o bioma.
const N2 = (() => {
  const P = new Uint8Array(512), R = rng('world-nations'), a = [...Array(256).keys()];
  for (let i = 255; i > 0; i--) { const j = R() * (i + 1) | 0; [a[i], a[j]] = [a[j], a[i]]; }
  for (let i = 0; i < 512; i++) P[i] = a[i & 255];
  const h = (i, j) => P[P[i & 255] + (j & 255)] / 255;
  const vn = (x, y) => { const i = Math.floor(x), j = Math.floor(y), fx = x - i, fy = y - j, u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy);
    const A = h(i, j), B = h(i + 1, j), C = h(i, j + 1), E = h(i + 1, j + 1); return A + (B - A) * u + (C - A) * v + (A - B - C + E) * u * v; };
  const fbm = (x, y, o) => { let s = 0, w = .5, n = 0; for (let k = 0; k < o; k++) { s += w * vn(x, y); n += w; x = x * 2.03 + 17.1; y = y * 2.03 + 3.7; w *= .5; } return s / n; };
  return { vn, fbm };
})();
const cl = v => v < 0 ? 0 : v > 1 ? 1 : v;
const mix = (a, b, t) => { t = cl(t); return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]; };

// cor da terra: bioma pelo tipo de terreno + elevação (e), umidade (m), detalhe (d), frio e praia
function landRGB(te, e, m, d, cold, beach) {
  let c;
  if (te === 'Floresta') { c = mix([70, 112, 56], [40, 80, 40], m); c = mix(c, [30, 60, 32], cl((d - .45) * 2.2) * .5); }
  else if (te === 'Montanha') { const k = e + d * .05;
    c = k < .5 ? mix([118, 140, 80], [132, 116, 88], (k - .3) / .2) : k < .68 ? mix([132, 116, 88], [120, 112, 102], (k - .5) / .18) : mix([128, 122, 114], [240, 240, 236], (k - .74) / .08); }
  else if (te === 'Deserto') { const r = .5 + .5 * Math.sin(e * 70 + d * 3); c = mix([231, 203, 146], [205, 166, 104], r * .55 + m * .3); }
  else if (te === 'Pântano') { c = m > .6 ? mix([70, 98, 92], [60, 88, 86], d) : mix([96, 112, 66], [72, 90, 54], d); }
  else { c = mix([164, 188, 104], [116, 150, 70], m); c = mix(c, [192, 176, 108], cl((d - .62) * 3) * .45); }
  if (cold > 0) c = mix(c, [234, 238, 240], cold);
  if (beach > 0) c = mix(c, [232, 216, 168], beach);
  return c;
}
const oceanRGB = (near, w) => { const c = mix([20, 56, 86], [58, 132, 156], Math.pow(cl(near), 1.4)); const k = 1 + (w - .5) * .08; return [c[0] * k, c[1] * k, c[2] * k]; };
const merc = lat => { const s = Math.sin(lat * Math.PI / 180); return .5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI); };
const unmerc = y => Math.atan(Math.sinh(Math.PI * (1 - 2 * y))) * 180 / Math.PI;

// pinta um tile em N×N pixels (128 = qualidade final, 32 = rascunho rápido) e devolve o canvas
function paintTile(c, terr, N = 128) {
  const sc = 256 / N, m = Math.ceil(20 / sc), W = 256 * Math.pow(2, c.z), X0 = c.x * 256, Y0 = c.y * 256, S = 1400, oct = Math.max(3, Math.min(8, c.z + 1));
  const pj = ([lng, lat]) => [((lng + 180) / 360 * W - X0) / sc + m, (merc(lat) * W - Y0) / sc + m];
  const mk = (w, h) => { const k = document.createElement('canvas'); k.width = w; k.height = h; return k; };
  const M = mk(N + 2 * m, N + 2 * m), mx = M.getContext('2d'), I = mk(N, N), ix = I.getContext('2d');
  const lng0 = (X0 - 40) / W * 360 - 180, lng1 = (X0 + 296) / W * 360 - 180, lat0 = unmerc((Y0 + 296) / W), lat1 = unmerc((Y0 - 40) / W);
  const near = terr.filter(t => !(t.bb[2] < lng0 || t.bb[0] > lng1 || t.bb[3] < lat0 || t.bb[1] > lat1));
  near.forEach((t, i) => { const r = t.g.coordinates; const path = new Path2D();
    r.forEach(ring => ring.forEach((p, k) => { const q = pj(p); k ? path.lineTo(q[0], q[1]) : path.moveTo(q[0], q[1]); }));
    mx.fillStyle = '#fff'; mx.fill(path, 'evenodd');
    ix.setTransform(1, 0, 0, 1, -m, -m); ix.fillStyle = `rgb(${(i + 1) & 255},${(i + 1) >> 8},255)`; ix.fill(path, 'evenodd'); });
  let B = null;
  if (near.length) { const Bc = mk(N + 2 * m, N + 2 * m), bx = Bc.getContext('2d'); bx.filter = `blur(${10 / sc}px)`; bx.drawImage(M, 0, 0); B = bx.getImageData(0, 0, N + 2 * m, N + 2 * m).data; }
  const Md = mx.getImageData(0, 0, N + 2 * m, N + 2 * m).data, Id = ix.getImageData(0, 0, N, N).data;
  const out = new ImageData(N, N), o = out.data;
  for (let j = 0; j < N; j++) {
    const Yw = (Y0 + (j + .5) * sc) / W, lat = unmerc(Yw), ny = Yw * S, cold = cl((Math.abs(lat) - 52) / 18); let last = 0;
    for (let i = 0; i < N; i++) {
      const nx = (X0 + (i + .5) * sc) / W * S, mi = ((j + m) * (N + 2 * m) + i + m) * 4, a = Md[mi + 3] / 255, b = B ? B[mi + 3] / 255 : 0, oi = (j * N + i) * 4; let col;
      if (a > .5) {
        const k = j * N * 4 + i * 4; let id = Id[k + 3] === 255 && Id[k + 2] === 255 ? Id[k] + Id[k + 1] * 256 : last; if (id) last = id;
        const te = (near[id - 1] || near[0]).te, mt = te === 'Montanha', rd = v => { if (!mt) return v; const r = 1 - Math.abs(2 * cl((v - .5) * 2.5 + .5) - 1); return .3 + .5 * r * r; };
        const e = rd(N2.fbm(nx * .35, ny * .35, oct)), eR = rd(N2.fbm(nx * .35 + .25, ny * .35 - .25, oct));
        const mo = N2.fbm(nx * .2 + 50, ny * .2, 3), d = N2.vn(nx * 6, ny * 6);
        col = landRGB(te, e, mo, d, cold, te === 'Montanha' ? 0 : (.66 - b) / .1);
        let sh = 1 + (e - eR) * (mt ? 4.5 : 2.4); if (c.z >= 6) { const fn = N2.vn(nx * 45, ny * 45); sh *= .93 + fn * .14; if (te === 'Floresta' && c.z >= 8 && N2.vn(nx * 140, ny * 140) > .62) sh *= .8; }
        col = [col[0] * sh, col[1] * sh, col[2] * sh];
      } else {
        col = oceanRGB(b * 1.9, N2.vn(nx * 3, ny * 3));
        if (b > .38) col = mix(col, [190, 220, 222], (b - .38) * 1.6 * (.6 + .4 * N2.vn(nx * 12, ny * 12)));
      }
      o[oi] = col[0]; o[oi + 1] = col[1]; o[oi + 2] = col[2]; o[oi + 3] = 255;
    }
  }
  const sm = mk(N, N); sm.getContext('2d').putImageData(out, 0, 0);
  return sm;
}

// cache dos tiles prontos (LRU ~20 MB) + fila que pinta em fatias de 12 ms sem travar o zoom
const TC = new Map(), TQ = [];
const tcSet = (k, v) => { TC.delete(k); TC.set(k, v); if (TC.size > 300) TC.delete(TC.keys().next().value); };
let tBusy = false;
function pump() {
  if (tBusy) return; tBusy = true;
  const run = () => { const t0 = performance.now(); while (TQ.length && performance.now() - t0 < 12) TQ.shift()();
    if (TQ.length) setTimeout(run, 0); else tBusy = false; };
  setTimeout(run, 0);
}
const blit = (t, src, sx = 0, sy = 0, sw = src.width, sh = src.height) => {
  const x = t.getContext('2d'); x.imageSmoothingEnabled = true; x.imageSmoothingQuality = 'high'; x.drawImage(src, sx, sy, sw, sh, 0, 0, 256, 256); };
// ao aproximar: usa o pedaço ampliado do tile "pai" já pintado — aparece na hora, nítido logo depois
function fromParent(t, c, sig) {
  for (let up = 1; up <= 4 && c.z - up >= 0; up++) {
    const k = 1 << up, px = Math.floor(c.x / k), py = Math.floor(c.y / k), src = TC.get(`${sig}|${c.z - up}|${px}|${py}`);
    if (src) { const s = src.width / k; blit(t, src, (c.x - px * k) * s, (c.y - py * k) * s, s, s); return true; }
  }
  return false;
}

const TerrainLayer = L.GridLayer.extend({
  options: { tileSize: 256, keepBuffer: 6, updateWhenZooming: false },
  setTerr(ts) { const sig = ts.map(t => t.id + t.te + t.a).join(); if (sig === this._sig) return; this._sig = sig; TC.clear();
    this._terr = ts.map(t => { let a = 1e9, b = 1e9, c = -1e9, d = -1e9; t.g.coordinates[0].forEach(([x, y]) => { a = Math.min(a, x); b = Math.min(b, y); c = Math.max(c, x); d = Math.max(d, y); });
      return { ...t, bb: [a, b, c, d] }; }); this.redraw(); },
  createTile(c, done) {
    const t = document.createElement('canvas'); t.width = t.height = 256;
    const terr = this._terr || [], key = `${this._sig}|${c.z}|${c.x}|${c.y}`, hit = TC.get(key);
    if (hit) blit(t, hit);
    else {
      // 1) rascunho imediato (pai ampliado ou versão 32×32), 2) versão final na fila
      if (!fromParent(t, c, this._sig)) try { blit(t, paintTile(c, terr, 32)); } catch (e) { console.warn(e); }
      TQ.push(() => { if (!t.isConnected) return; try { const sm = paintTile(c, terr, 128); tcSet(key, sm); blit(t, sm); } catch (e) { console.warn(e); } });
      pump();
    }
    setTimeout(() => done(null, t), 0);
    return t;
  }
});

// fundo da tela inicial: um mundo inventado só de enfeite
function paintWorld(cv) {
  const w = cv.width = Math.ceil(innerWidth / 2), h = cv.height = Math.ceil(innerHeight / 2), x = cv.getContext('2d'), im = x.createImageData(w, h), o = im.data, S = 6 / w;
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
    const nx = i * S * 4 + 3, ny = j * S * 4 + 7, e = N2.fbm(nx * .55, ny * .55, 6) + .12 - Math.hypot(i / w - .5, (j / h - .5) * 1.2) * .35, k = (j * w + i) * 4;
    let c;
    if (e > .5) { const mo = N2.fbm(nx * .4 + 40, ny * .4, 3), d = N2.vn(nx * 9, ny * 9), lat = Math.abs(j / h - .5) * 150;
      const te = e > .68 ? 'Montanha' : mo > .58 ? 'Floresta' : mo < .4 && lat < 40 ? 'Deserto' : mo > .55 && e < .54 ? 'Pântano' : 'Planície';
      c = landRGB(te, (e - .5) * 2.2, mo, d, cl((lat - 62) / 12), (.53 - e) / .03); const sh = 1 + (e - N2.fbm(nx * .55 + .2, ny * .55 - .2, 6) - .12 + Math.hypot(i / w - .5, (j / h - .5) * 1.2) * .35) * 4; c = c.map(v => v * sh); }
    else c = oceanRGB(cl((e - .38) / .12), N2.vn(nx * 6, ny * 6));
    o[k] = c[0]; o[k + 1] = c[1]; o[k + 2] = c[2]; o[k + 3] = 255;
  }
  x.putImageData(im, 0, 0);
}
