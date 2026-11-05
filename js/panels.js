// World Nations — menus de gerenciamento
let MID = null;                                  // partida aberta
const P = (fn, a = {}, ok) => rpc(fn, { p_match: MID, ...a }, ok);
const NoC = () => html`<p class="muted">Você ainda não tem um país nesta partida.</p>`;
const Sel = ({ v, set, opts, ph }) => html`<select value=${v} onChange=${e => set(e.target.value)}>${ph && html`<option value="">${ph}</option>`}${opts.map(([k, n]) => html`<option key=${k} value=${k}>${n}</option>`)}</select>`;
const terrOpts = S => myTerr(S).map(t => [t.id, t.n]);
const cOpts = S => S.countries.filter(c => c.alive && c.id !== S.me).map(c => [c.id, c.name]);
const H4 = ({ i, children }) => html`<h4>${i && html`<${Ic} n=${i} s=${15} />`}${children}</h4>`;
const satC = v => v < 25 ? '#c4442f' : v < 45 ? '#d6982e' : v < 65 ? '#b9b25a' : '#6fa043';
const GRPD = { agr: 'fazendas, tecnologia agrícola e comida garantida', ope: 'empregos (fábricas e minas), produtos industriais, impostos baixos, programas sociais',
  eng: 'obras de infraestrutura, universidades e verba de educação', cie: 'laboratórios, verba de educação e liberdade (ditaduras os afastam)',
  com: 'tratados de comércio, organizações, fronteiras abertas, paz e nenhuma sanção', ser: 'tesouro em dia e impostos moderados',
  sol: 'doutrinas, economia de guerra, soldo em dia e alistamento moderado', des: 'empregos e programas sociais', dep: 'hospitais, comida, produtos e programas sociais' };
const GRPR = { ope: 'greve geral', agr: 'bloqueio das safras', sol: 'motim ou golpe', cie: 'fuga de cérebros', eng: 'fuga de cérebros', com: 'fuga de capitais', des: 'saques e incêndios', ser: 'paralisação do Estado', dep: '—' };

function derived(S, c) {
  const n = k => nb(S, c.id, k), pop = +c.pop || 1;
  return { idh: Math.min(1, (c.education || 0) * .4 + (c.happiness || 0) / 100 * .3 + Math.min(1, (c.gdp || 0) / (pop / 1e6) / 5) * .3),
    infl: c.income != null ? Math.max(0, 2 + ((c.expenses - c.income) / Math.max(1, c.income)) * 8 + (c.treasury < 0 ? 6 : 0)) : null,
    ind: n('factory') * 10 + n('power') * 5 + n('mine') * 3 };
}

// ---------------- PAÍS / STATUS / RANKING ----------------
function PCountry({ S }) {
  const [tab, setTab] = useState('st'); const c = S.my;
  return html`<div><${Tabs} tabs=${[['st', 'Status nacional'], ['rk', 'Classificação mundial']]} v=${tab} set=${setTab} />
    ${tab === 'rk' ? html`<${Ranking} S=${S} />` : c ? html`<${Status} S=${S} c=${c} />` : html`<${NoC} />`}</div>`;
}
function Status({ S, c }) {
  const d = derived(S, c);
  return html`<div>
    <div class="hero"><${Flag} f=${c.flag} s=${54} /><div><h2>${c.name}</h2><div class="muted">Capital: ${c.capital_name} · ${c.government} · ${c.ideology}</div>
      <div>${leaderTitle(c)}: <b>${c.leader}</b> ${c.party ? `(${c.party})` : ''}</div></div>${c.portrait && html`<img class="portrait" src=${c.portrait} />`}</div>
    <div class="grid">
      <${Stat} l="População" v=${fmt(c.pop)} /><${Stat} l="Território" v=${fmt(c.area) + ' km²'} /><${Stat} l="PIB" v=${fmt(c.gdp) + '/h'} />
      <${Stat} l="Renda nacional" v=${fmt(c.income) + '/h'} /><${Stat} l="Despesas" v=${fmt(c.expenses) + '/h'} />
      <${Stat} l="Dívida" v=${c.treasury < 0 ? fmt(-c.treasury) : '0'} c=${c.treasury < 0 ? 'neg' : ''} /><${Stat} l="Inflação" v=${d.infl.toFixed(1) + '%'} />
      <${Stat} l="IDH" v=${d.idh.toFixed(3)} /><${Stat} l="Poder militar" v=${fmt(c.mil)} /><${Stat} l="Poder industrial" v=${d.ind} />
      <${Stat} l="Tecnologias" v=${c.techs} /><${Stat} l="Infâmia" v=${Math.round(c.infamy)} c=${c.infamy > 40 ? 'neg' : ''} t="Reputação ruim: piora relações e estabilidade" />
    </div>
    <label>Estabilidade ${Math.round(c.stability)}%</label><${Bar} v=${c.stability} c="#7aa34a" />
    <label>Felicidade ${Math.round(c.happiness)}%</label><${Bar} v=${c.happiness} c="#d8b04a" />
    <${H4} i="cargo">Estoque nacional</${H4}><div class="res">${Object.keys(D.res).map(k => html`<span key=${k} title=${RN(k)}><${Ic} n=${k} s=${15} /> ${fmt((c.stock || {})[k])}</span>`)}</div>
    <${H4} i="diplo">Relações</${H4}><div class="chips">${S.countries.filter(x => x.alive && x.id !== c.id).map(x => { const r = relation(S, c.id, x.id);
      return html`<span key=${x.id} class="chip" style=${{ borderColor: REL[r] }}><${Flag} f=${x.flag} s=${14} /> ${x.name}: <b style=${{ color: REL[r] }}>${r}</b></span>`; })}</div>
    <${H4} i="hist">Evolução</${H4}>
    <${Chart} data=${S.stats} keys=${[{ k: 'pop', c: '#d8b04a', n: 'População' }, { k: 'gdp', c: '#7aa34a', n: 'PIB' }]} />
    <${Chart} data=${S.stats} keys=${[{ k: 'tr', c: '#c9a227', n: 'Tesouro' }, { k: 'mil', c: '#b5302a', n: 'Militar' }, { k: 'st', c: '#5b8bd0', n: 'Estabilidade' }]} />
  </div>`;
}
function Ranking({ S }) {
  const cs = S.countries.filter(c => c.alive);
  const inf = c => S.treaties.filter(t => t.kind !== 'sancao' && (t.a === c.id || t.b === c.id)).length * 2 + S.orgs.filter(o => o.members.includes(c.id)).length * 3 + S.orgs.filter(o => o.leader === c.id).length * 3 - c.infamy / 10;
  const cats = [['Maior economia', c => +c.gdp, v => fmt(v) + '/h'], ['Maior população', c => +c.pop, fmt], ['Maior território', c => +c.area, v => fmt(v) + ' km²'],
    ['Maior poder militar', c => +c.mil, fmt], ['Desenvolvimento tecnológico', c => +c.techs, v => v + ' tec.'], ['Produção industrial', c => derived(S, c).ind, v => v],
    ['Influência diplomática', inf, v => Math.round(v)]];
  return html`<div class="muted small">Classificação só informativa — não existe condição de vitória.</div>${cats.map(([n, f, show]) => html`<div key=${n}><h4>${n}</h4>
    ${cs.slice().sort((a, b) => f(b) - f(a)).slice(0, 5).map((c, i) => html`<div key=${c.id} class="row rank"><b>${i + 1}</b> <${Flag} f=${c.flag} s=${14} /> ${c.name}<span class="sp" />${show(f(c))}</div>`)}</div>`)}`;
}

// ---------------- GOVERNO ----------------
function PGov({ S }) {
  const c = S.my; const [ld, setLd] = useState(c ? c.leader : ''); const [pt, setPt] = useState(c ? c.party || '' : '');
  const [ide, setIde] = useState(''); const [gov, setGov] = useState(''); const [mn, setMn] = useState({});
  const [tax, setTax] = useState(c ? Math.round(c.tax * 100) : 25); const [con, setCon] = useState(c ? +(c.conscription * 100).toFixed(1) : 3);
  const [soc, setSoc] = useState(c && c.budget ? c.budget.social || 0 : 0); const [edu, setEdu] = useState(c && c.budget ? c.budget.edu || 0 : 0);
  const t = useTick(30000); if (!c) return html`<${NoC} />`;
  const run = S.match.status === 'running', bc = l => fmt(c.pop / 1e6 * .12 * l);
  return html`<div>
    <div class="hero">${c.portrait ? html`<img class="portrait" src=${c.portrait} />` : html`<div class="portrait ph"><${Ic} n="person" s=${48} /></div>`}
      <div><div class="muted">${leaderTitle(c)}</div><h2>${c.leader}</h2><div>${c.party || 'Sem partido'} · ${age(c.leader)} anos</div>
      <div class="small">No poder há ${dur(t - Date.parse(c.leader_since))} · Popularidade ${Math.round(c.happiness)}% · Legitimidade ${Math.round(c.stability)}%</div>
      <label class="up">Trocar retrato<input type="file" accept="image/*" onChange=${async e => e.target.files[0] && P('set_policy', { p: { portrait: await shrink(e.target.files[0], 120, 150) } }, 'Retrato atualizado')} /></label></div></div>
    <div class="form"><input value=${ld} onInput=${e => setLd(e.target.value)} placeholder="Nome do líder" /><input value=${pt} onInput=${e => setPt(e.target.value)} placeholder="Partido / grupo político" />
      <${Btn} onClick=${() => P('set_policy', { p: { leader: ld, party: pt } }, 'Governo atualizado')}>Salvar</${Btn}></div>
    <${H4} i="vote">Leis e orçamento</${H4}>
    <label>Impostos: <b>${tax}%</b> <span class="muted small">mais renda, todos os grupos ficam menos satisfeitos</span></label><input type="range" min="0" max="70" value=${tax} onInput=${e => setTax(+e.target.value)} />
    <label>Alistamento: <b>${con}%</b> da população <span class="muted small">mais tropas, soldados insatisfeitos acima de 3%</span></label><input type="range" min="0.5" max="15" step="0.5" value=${con} onInput=${e => setCon(+e.target.value)} />
    <label>Programas sociais: <b>${['nenhum', 'básico', 'amplo'][soc]}</b> <span class="muted small">💰${bc(soc)}/h · agrada desempregados, operários e famílias</span></label><input type="range" min="0" max="2" value=${soc} onInput=${e => setSoc(+e.target.value)} />
    <label>Investimento em educação: <b>${['mínimo', 'médio', 'alto'][edu]}</b> <span class="muted small">💰${bc(edu)}/h · mais educação, engenheiros e cientistas</span></label><input type="range" min="0" max="2" value=${edu} onInput=${e => setEdu(+e.target.value)} />
    <div class="form"><${Btn} cls="ok" onClick=${() => P('set_policy', { p: { tax: tax / 100, conscription: con / 100, budget: { social: soc, edu } } }, 'Leis aprovadas')}>Aprovar</${Btn}>
      <${Btn} cls=${c.focus === 'guerra' ? 'red' : ''} onClick=${() => P('set_policy', { p: { focus: c.focus === 'guerra' ? 'civil' : 'guerra' } })}>${c.focus === 'guerra' ? 'Voltar à economia civil' : 'Economia de guerra'}</${Btn}>
      <${Btn} cls=${c.emergency ? 'red' : ''} onClick=${() => P('set_policy', { p: { emergency: !c.emergency } })}>${c.emergency ? 'Encerrar emergência' : 'Estado de emergência'}</${Btn}>
      <${Btn} onClick=${() => P('elections')} title="Só em repúblicas, federações e democracias">Convocar eleições</${Btn}></div>
    <div class="muted small">Economia de guerra: fábricas +20% e tropas 25% mais rápidas, PIB −10%, operários reclamam. Emergência: +15 estabilidade, −8 satisfação.</div>
    <${H4} i="crown">Ministros</${H4}>${Object.entries(D.min).map(([k, m]) => { const cur = (c.ministers || {})[k];
      return html`<div key=${k} class="row"><span class="w40">${m.n}</span><span class="w30 small">${cur ? `${cur.n} (+${Math.round(cur.b * 100)}% ${FXN[cur.k]})` : '—'}</span>
        <input class="w20" placeholder="Nome" value=${mn[k] || ''} onInput=${e => setMn({ ...mn, [k]: e.target.value })} /><${Btn} onClick=${() => P('appoint_minister', { p_role: k, p_name: mn[k] || '' }, 'Ministro nomeado')}>Nomear · 60</${Btn}></div>`; })}
    <${H4} i="gov">Reforma de governo ${run ? html`<span class="muted small">(custa 300 e −15 estabilidade)</span>` : ''}</${H4}>
    <div class="form"><${Sel} v=${ide} set=${setIde} ph=${'Ideologia: ' + c.ideology} opts=${Object.keys(D.ideo).map(k => [k, `${k} (${fxTxt(D.ideo[k])})`]).concat([['*', 'Outra (personalizada)…']])} />
      <${Sel} v=${gov} set=${setGov} ph=${'Governo: ' + c.government} opts=${Object.keys(D.gov).map(k => [k, `${k} (${fxTxt(D.gov[k].fx)})`]).concat([['*', 'Outro (personalizado)…']])} />
      <${Btn} onClick=${() => { const i = ide === '*' ? prompt('Nome da ideologia') : ide, g = gov === '*' ? prompt('Nome do sistema de governo') : gov;
        return P('set_policy', { p: { ...(i ? { ideology: i } : {}), ...(g ? { government: g } : {}) } }, 'Reforma realizada'); }}>Reformar</${Btn}></div>
    <${H4} i="country">Símbolos nacionais</${H4}><div class="form"><label class="up">Nova bandeira<input type="file" accept="image/*" onChange=${async e => e.target.files[0] && P('set_policy', { p: { flag: await shrink(e.target.files[0], 90, 60) } }, 'Bandeira trocada')} /></label>
      <input type="color" value=${c.color} onChange=${e => P('set_policy', { p: { color: e.target.value } }, 'Cor alterada')} /></div>
  </div>`;
}

// ---------------- POPULAÇÃO: grupos sociais e migração ----------------
function PPop({ S }) {
  const c = S.my; if (!c) return html`<${NoC} />`;
  const g = c.groups || {}, keys = ['agr', 'ope', 'com', 'ser', 'eng', 'cie', 'sol', 'des', 'dep'].filter(k => g[k]), st = S.stats, mg = c.mig || {};
  const gr = st.length > 1 ? (st[st.length - 1].pop - st[0].pop) / Math.max(1, (Date.parse(st[st.length - 1].t) - Date.parse(st[0].t)) / 864e5) : 0;
  return html`<div><div class="grid"><${Stat} l="População" v=${fmt(c.pop)} /><${Stat} l="Variação/dia" v=${(gr >= 0 ? '+' : '') + fmt(gr)} c=${gr < 0 ? 'neg' : 'pos'} />
    <${Stat} l="Desemprego" v=${Math.round(c.unemployment * 100) + '%'} c=${c.unemployment > .2 ? 'neg' : ''} /><${Stat} l="Educação" v=${Math.round(c.education * 100) + '%'} />
    <${Stat} l="Satisfação geral" v=${Math.round(c.happiness) + '%'} /><${Stat} l="Reserva militar" v=${fmt(Math.max(0, c.pop * c.conscription - ((g.sol || {}).n || 0)))} /></div>
    <${H4} i="pop">Grupos sociais</${H4}>
    ${!keys.length ? html`<p class="muted">Os grupos aparecem depois do primeiro ciclo da partida.</p>` : html`<table class="grp"><tr><th>Grupo</th><th>Pessoas</th><th>Satisfação</th><th>Se revoltar</th></tr>
      ${keys.map(k => html`<tr key=${k} title=${'Querem: ' + GRPD[k]}><td><${Ic} n=${k} s=${16} /> ${D.grp[k]}</td><td>${fmt(g[k].n)} <span class="muted small">${Math.round(g[k].n / c.pop * 100)}%</span></td>
        <td><div class="sat"><${Bar} v=${g[k].s} c=${satC(g[k].s)} /><b style=${{ color: satC(g[k].s) }}>${Math.round(g[k].s)}</b></div></td><td class="small">${g[k].s < 30 ? html`<b class="neg">${GRPR[k]}</b>` : GRPR[k]}</td></tr>`)}</table>
      <div class="small muted">Cada grupo só existe se houver emprego: fábricas criam operários, universidades criam cientistas, cidades e portos criam comerciantes. Quem sobra fica desempregado. Grupo abaixo de 25 pode se revoltar. Passe o mouse para ver o que cada um quer.</div>`}
    <${H4} i="boot">Migração</${H4}>
    <div class="grid"><${Stat} l="Imigrantes/h" v=${'+' + fmt(mg.in || 0)} c="pos" /><${Stat} l="Emigrantes/h" v=${'−' + fmt(mg.out || 0)} c=${mg.out ? 'neg' : ''} /><${Stat} l="Êxodo interno/h" v=${fmt(mg.int || 0)} t="Pessoas mudando de regiões pobres para regiões com cidades e emprego" /></div>
    ${Object.keys(mg.from || {}).length > 0 && html`<div class="small">Chegando de: ${Object.entries(mg.from).map(([n, v]) => `${n} (${fmt(v)}/h)`).join(', ')}</div>`}
    <div class="seg">${[['aberta', 'Fronteiras abertas', 'mais imigrantes e comerciantes felizes'], ['controlada', 'Controladas', 'equilíbrio'], ['fechada', 'Fechadas', 'ninguém entra, poucos saem, comerciantes reclamam']].map(([k, n, d]) =>
      html`<button key=${k} class=${c.border === k ? 'on' : ''} onClick=${() => P('set_policy', { p: { border: k } })} title=${d}><${Ic} n="wall" s=${14} /> ${n}</button>`)}</div>
    <div class="small muted">As pessoas saem de países em guerra, com fome ou miséria e vão para países mais ricos, estáveis e felizes que deixam entrar.</div>
    <${H4} i="map">Regiões</${H4}><table><tr><th>Região</th><th>Terreno</th><th>População</th><th>Densidade</th><th>Rebeldes</th></tr>${myTerr(S).map(t => html`<tr key=${t.id}><td>${t.n}${t.o ? ' (ocupada)' : ''}</td><td>${t.te}</td><td>${fmt(t.p)}</td><td>${fmt(t.p / Math.max(1, t.a))}/km²</td><td class=${t.rb > 0 ? 'neg' : ''}>${t.rb}</td></tr>`)}</table></div>`;
}

// ---------------- ECONOMIA ----------------
function PEcon({ S }) {
  const c = S.my; if (!c) return html`<${NoC} />`; const d = derived(S, c), net = c.income - c.expenses, b = c.budget || {};
  return html`<div><div class="grid"><${Stat} l="Tesouro" v=${fmt(c.treasury)} c=${c.treasury < 0 ? 'neg' : ''} /><${Stat} l="Receita" v=${fmt(c.income) + '/h'} c="pos" /><${Stat} l="Despesas" v=${fmt(c.expenses) + '/h'} c="neg" />
    <${Stat} l="Saldo" v=${(net >= 0 ? '+' : '') + fmt(net) + '/h'} c=${net < 0 ? 'neg' : 'pos'} /><${Stat} l="PIB" v=${fmt(c.gdp) + '/h'} /><${Stat} l="Impostos" v=${Math.round(c.tax * 100) + '%'} />
    <${Stat} l="Dívida" v=${c.treasury < 0 ? fmt(-c.treasury) : '0'} /><${Stat} l="Inflação" v=${d.infl.toFixed(1) + '%'} /><${Stat} l="Modelo" v=${c.focus === 'guerra' ? 'De guerra' : 'Civil'} /></div>
    <${Chart} data=${S.stats} keys=${[{ k: 'tr', c: '#c9a227', n: 'Tesouro' }, { k: 'gdp', c: '#7aa34a', n: 'PIB' }]} />
    <${H4} i="coins">Receita</${H4}><div class="small">PIB = população + fábricas, usinas, cidades, portos, aeroportos, estradas e ferrovias × bônus (tecnologia, ideologia, ministros, tratados, organizações). Desemprego e falta de produtos industriais derrubam o PIB. Receita = PIB × impostos.</div>
    <${H4} i="bank">Despesas</${H4}><div class="small">Tropas (1% do custo/h), prédios (0,05/h cada), serviço secreto, emergência, programas sociais (${fmt(c.pop / 1e6 * .12 * (b.social || 0))}/h), educação (${fmt(c.pop / 1e6 * .12 * (b.edu || 0))}/h) e juros da dívida (0,2%/h).</div>
    <${H4} i="cargo">Consumo da população por hora</${H4}><div class="res"><span><${Ic} n="food" s=${15} /> ${fmt(c.pop / 1e6 * .15)}</span><span><${Ic} n="goods" s=${15} /> ${fmt(c.pop / 1e6 * .04)}</span>
      <span class="small muted">sem comida: fome · sem produtos industriais: −6 de satisfação e PIB −5%</span></div>
    <${H4} i="mine">Extração por hora</${H4}><div class="res">${RAW().map(k => { const v = myTerr(S).reduce((a, t) => a + ((t.r || {})[k] || 0) * .5 * (1 + .5 * t.b.filter(b => b.k === 'mine' && ready(b)).length), 0) + (k === 'food' ? nb(S, c.id, 'farm') * 3 : 0);
      return html`<span key=${k} title=${RN(k)}><${Ic} n=${k} s=${15} /> ${fmt(v)}</span>`; })}</div></div>`;
}

// ---------------- INFRAESTRUTURA ----------------
function PInfra({ S, pre }) {
  const [tid, setTid] = useState(pre || (myTerr(S)[0] || {}).id || ''); const t = S.T[tid]; useTick(); if (!S.my) return html`<${NoC} />`;
  const wip = S.buildings.filter(b => S.T[b.t] && S.T[b.t].c === S.me && !ready(b));
  return html`<div><${Sel} v=${tid} set=${setTid} opts=${terrOpts(S)} />
    ${t && html`<div class="small muted">${t.te} · ${fmt(t.a)} km² · ${fmt(t.p)} hab.</div>`}
    ${wip.length > 0 && html`<${H4} i="clock">Em obras</${H4}>${wip.map(b => html`<div key=${b.id} class="row"><${Ic} n=${b.k} /> ${D.b[b.k].n} — ${S.T[b.t].n}<span class="sp" />${dur(Date.parse(b.d) - now())}</div>`)}`}
    <${H4} i="infra">Construir</${H4}><div class="cards">${Object.entries(D.b).sort((a, b) => a[1].c - b[1].c).map(([k, b]) => { const lock = b.t && !done(S, b.t), n = t ? t.b.filter(x => x.k === k).length : 0;
      return html`<div key=${k} class=${'card bc' + (lock ? ' lock' : '')}><div class="row"><${Ic} n=${k} s=${26} /><b>${b.n}</b><span class="sp" />${n ? html`<span class="badge">${n}</span>` : ''}</div>
        <div class="small">${b.e}</div><div class="small"><${Cost} c=${b.c} r=${b.r} /> · ${b.h}h ${lock ? html`· <b class="neg">requer ${D.t[b.t].n}</b>` : ''}</div>
        <${Btn} disabled=${lock || !t} onClick=${() => P('build', { p_terr: tid, p_kind: k }, b.n + ' em construção')}>Construir</${Btn}></div>`; })}</div></div>`;
}

// ---------------- PRODUÇÃO: indústria + recrutamento ----------------
function PProd({ S, pre }) {
  const [tab, setTab] = useState('ind'); const [tid, setTid] = useState(pre || (myTerr(S)[0] || {}).id || ''); const [q, setQ] = useState(1);
  const c = S.my; const [al, setAl] = useState(() => { const x = c && c.industry && Object.keys(c.industry).length ? c.industry : { goods: .4, arms: .4, mach: .2 }; const o = {}; GOODS().forEach(k => o[k] = Math.round((x[k] || 0) * 100)); return o; });
  useTick(); if (!c) return html`<${NoC} />`;
  const used = S.units.filter(u => u.c === c.id).reduce((a, u) => a + D.u[u.k].m, 0), mp = c.pop * c.conscription, train = S.units.filter(u => u.c === c.id && !ready(u));
  const nf = nb(S, c.id, 'factory') * (1 + Math.min(5, nb(S, c.id, 'power')) * .08) * (c.focus === 'guerra' ? 1.2 : 1), sum = Object.values(al).reduce((a, b) => a + b, 0);
  return html`<div><${Tabs} tabs=${[['ind', 'Indústria'], ['mil', 'Recrutamento']]} v=${tab} set=${setTab} />
    ${tab === 'ind' ? html`<div><div class="small">Fábricas ativas: <b>${nb(S, c.id, 'factory')}</b> · capacidade ${fmt(nf)} produtos/h. Divida as linhas de produção (total ${sum}%):</div>
      ${GOODS().map(k => { const out = nf * al[k] / 100; return html`<div key=${k} class="prod"><div class="row"><${Ic} n=${k} s=${22} /><b>${RN(k)}</b><span class="sp" />${al[k]}% · ~${fmt(out)}/h · estoque ${fmt((c.stock || {})[k])}</div>
        <input type="range" min="0" max="100" step="5" value=${al[k]} onInput=${e => setAl({ ...al, [k]: +e.target.value })} />
        <div class="small muted">Cada unidade gasta <${Cost} r=${D.res[k].rc} /> ${out > 0 ? html`· por hora: <${Cost} r=${D.res[k].rc} q=${out} />` : ''}</div></div>`; })}
      <${Btn} cls="ok" disabled=${sum > 100} onClick=${() => P('set_policy', { p: { industry: Object.fromEntries(Object.entries(al).map(([k, v]) => [k, v / 100])) } }, 'Produção reorganizada')}>${sum > 100 ? 'Passou de 100%' : 'Aplicar divisão'}</${Btn}>
      <div class="small muted">Sem matéria-prima a linha para: compre no Comércio. Máquinas servem para obras, equipamento militar e veículos para tropas, aviões e navios para força aérea e marinha, produtos industriais para a população.</div></div>`
    : html`<div><div class="form"><${Sel} v=${tid} set=${setTid} opts=${terrOpts(S)} /><label>Qtd <input type="number" min="1" max="20" value=${q} onInput=${e => setQ(+e.target.value)} style=${{ width: 60 }} /></label></div>
      <div class="small">Mão de obra: ${fmt(used)} / ${fmt(mp)} · Bases na região: ${S.T[tid] ? S.T[tid].b.filter(b => b.k === 'base' && ready(b)).length : 0}</div>
      <div class="cards">${Object.entries(D.u).sort((a, b) => a[1].c - b[1].c).map(([k, u]) => { const lock = u.t && !done(S, u.t);
        return html`<div key=${k} class=${'card bc' + (lock ? ' lock' : '')}><div class="row"><${Ic} n=${k} s=${26} /><b>${u.n}</b><span class="sp" /><span class="small">ATQ ${u.a} · DEF ${u.d}</span></div>
          <div class="small"><${Cost} c=${u.c} r=${u.r} q=${q} /> · ${fmt(u.m * q)} pessoas · ${u.h}h ${u.k === 'air' ? '· aeroporto' : u.k === 'sea' ? '· porto' : ''} ${lock ? html`· <b class="neg">${D.t[u.t].n}</b>` : ''}</div>
          <${Btn} disabled=${lock} onClick=${() => P('recruit', { p_kind: k, p_terr: tid, p_qty: q }, 'Produção iniciada')}>Produzir</${Btn}></div>`; })}</div>
      ${train.length > 0 && html`<${H4} i="clock">Em treinamento / movimento</${H4}>${train.map(u => html`<div key=${u.id} class="row"><${Ic} n=${u.k} /> ${D.u[u.k].n} — ${(S.T[u.t] || {}).n}<span class="sp" />${dur(Date.parse(u.r) - now())}</div>`)}`}</div>`}</div>`;
}

// ---------------- MILITAR ----------------
function PMil({ S, su, setSu }) {
  const c = S.my; const [tg, setTg] = useState(''); useTick(5000); if (!c) return html`<${NoC} />`;
  const mine = S.units.filter(u => u.c === c.id), kinds = {}; mine.forEach(u => kinds[u.k] = (kinds[u.k] || 0) + 1);
  const wars = S.wars.filter(w => !w.ended_at && (w.attacker === c.id || w.defender === c.id)), tog = id => setSu(su.includes(id) ? su.filter(x => x !== id) : [...su, id]);
  return html`<div><div class="res">${Object.entries(kinds).map(([k, n]) => html`<span key=${k}><${Ic} n=${k} s=${18} /> ${D.u[k].n}: <b>${n}</b></span>`)}${!mine.length && 'Sem unidades.'}</div>
    <${H4} i="mil">Guerras</${H4}>${wars.length ? wars.map(w => { const e = w.attacker === c.id ? w.defender : w.attacker;
      return html`<div key=${w.id} class="row">${S.C[e].name} <span class="muted small">desde ${when(w.started_at)}</span><span class="sp" /><${Btn} cls="red" onClick=${() => confirm('Render-se? Você paga 25% do tesouro e perde os territórios ocupados.') && P('surrender', { p_enemy: e }, 'Rendição assinada')}>Render-se</${Btn}></div>`; }) : html`<div class="muted">Em paz.</div>`}
    <div class="form"><${Sel} v=${tg} set=${setTg} ph="Declarar guerra a…" opts=${cOpts(S)} /><${Btn} cls="red" disabled=${!tg} onClick=${() => confirm('Declarar guerra?') && P('declare_war', { p_target: tg }, 'Guerra declarada')}>Declarar guerra</${Btn}></div>
    <${H4} i="medal">Doutrinas</${H4}>${[['land', 'Terrestre'], ['air', 'Aérea'], ['sea', 'Naval'], ['strat', 'Estratégica']].map(([k, n]) => html`<div key=${k} class="row"><span class="w30">${n}</span>
      <${Sel} v=${(c.doctrines || {})[k] || ''} set=${v => P('set_policy', { p: { doctrines: { [k]: v } } }, 'Doutrina adotada')} ph="Nenhuma"
        opts=${Object.entries(D.d).filter(([, d]) => d.k === k && done(S, d.t)).map(([i, d]) => [i, `${d.n} (${fxTxt(d.fx)})`])} /></div>`)}
    <div class="muted small">Novas doutrinas: pesquise a categoria "Doutrinas" em Tecnologia.</div>
    <${H4} i="shield">Exércitos ${su.length ? `· ${su.length} selecionadas — clique num território para Mover/Atacar` : ''}</${H4}>
    ${S.territories.filter(t => t.u.some(u => u.c === c.id)).map(t => html`<div key=${t.id} class="card"><b>${t.n}</b>
      ${t.u.filter(u => u.c === c.id).map(u => html`<label key=${u.id} class="unit"><input type="checkbox" disabled=${!ready(u)} checked=${su.includes(u.id)} onChange=${() => tog(u.id)} />
        <${Ic} n=${u.k} /> ${D.u[u.k].n} <${Bar} v=${u.s * 100} c="#7aa34a" /> ${ready(u) ? '' : dur(Date.parse(u.r) - now())}</label>`)}</div>`)}
    ${su.length > 0 && html`<${Btn} onClick=${() => setSu([])}>Limpar seleção</${Btn}>`}</div>`;
}

// ---------------- TECNOLOGIA ----------------
function PTech({ S }) {
  useTick(); if (!S.my) return html`<${NoC} />`;
  const depth = {}, dp = k => depth[k] != null ? depth[k] : (depth[k] = 1 + Math.max(0, ...(D.t[k].req || []).map(dp)));
  const cats = {}; ['Industrial', 'Econômica', 'Agrícola', 'Médica', 'Ciência', 'Militar', 'Aeronáutica', 'Naval', 'Eletrônica', 'Estratégica', 'Doutrinas'].forEach(c => cats[c] = []);
  Object.entries(D.t).forEach(([k, t]) => (cats[t.c] = cats[t.c] || []).push(k));
  const slots = 2 + Math.min(2, nb(S, S.me, 'lab')), busy = S.research.filter(r => !ready(r)).length;
  return html`<div><div class="small">Vagas de pesquisa: <b>${busy}/${slots}</b> · escolas, universidades, centros de pesquisa, educação e acordos de pesquisa aceleram.</div>
    ${Object.entries(cats).map(([cat, ks]) => html`<div key=${cat}><h4>${cat}</h4><div class="tree">${ks.sort((a, b) => dp(a) - dp(b) || D.t[a].cost - D.t[b].cost).map(k => { const t = D.t[k], r = S.R[k];
      const ok = (t.req || []).every(q => done(S, q)), st = r ? (ready(r) ? 'done' : 'wip') : ok ? 'av' : 'lock';
      return html`<div key=${k} class=${'tech ' + st} style=${{ marginLeft: (dp(k) - 1) * 14 }}>
        <b>${t.n}</b> <span class="small muted">nível ${dp(k)}${st === 'done' ? ' · concluída' : ''}</span>
        <div class="small">${t.req ? 'Requer: ' + t.req.map(q => D.t[q].n).join(', ') + ' · ' : ''}${fxTxt(t.fx) || 'libera novos equipamentos e opções'}${t.wmd ? ' · consequências diplomáticas' : ''}</div>
        ${st === 'wip' ? html`<div class="small">Conclui em ${dur(Date.parse(r.d) - now())}</div>` : st === 'av' ? html`<${Btn} onClick=${() => P('research_start', { p_tech: k }, 'Pesquisa iniciada')}>Pesquisar · ${t.cost} · ${t.h}h</${Btn}>` : ''}</div>`; })}</div></div>`)}</div>`;
}

// ---------------- DIPLOMACIA ----------------
function Terms({ S, other, v, set }) {
  const opt = cid => S.territories.filter(t => t.c === cid && !(S.C[cid].capital && inPoly(S.C[cid].capital, t.g.coordinates[0])));
  const tg = (key, id) => set({ ...v, [key]: v[key].includes(id) ? v[key].filter(x => x !== id) : [...v[key], id] });
  return html`<div class="terms"><div><b>Você cede</b>${opt(S.me).map(t => html`<label key=${t.id}><input type="checkbox" checked=${v.give.includes(t.id)} onChange=${() => tg('give', t.id)} />${t.n}</label>`)}</div>
    <div><b>Você recebe</b>${opt(other).map(t => html`<label key=${t.id}><input type="checkbox" checked=${v.take.includes(t.id)} onChange=${() => tg('take', t.id)} />${t.n}</label>`)}</div>
    <label>Pagamento <input type="number" value=${v.pay} onInput=${e => set({ ...v, pay: +e.target.value })} /><span class="small muted">positivo = você paga · negativo = eles pagam (reparações / compra)</span></label></div>`;
}
const PN = p => D.tr[p.kind] || { paz: 'Tratado de paz', acordo: 'Acordo / compra de território', ultimato: 'Ultimato', alianca: 'Convite para organização', contrato: 'Contrato de fornecimento' }[p.kind];
function PDiplo({ S, pre, su }) {
  const [cid, setCid] = useState(pre || ''); const [kind, setKind] = useState('nao_agressao'); const [deal, setDeal] = useState('acordo');
  const [terms, setTerms] = useState({ give: [], take: [], pay: 0 }); const [gift, setGift] = useState({ m: 0, r: 'food', q: 0, s: false });
  const [org, setOrg] = useState({ name: '', kind: 'alianca', flag: '', descr: '', rules: '' }); const [inv, setInv] = useState('');
  if (!S.my) return html`<${NoC} />`;
  const o = S.C[cid], me = S.me, inbox = S.proposals.filter(p => p.status === 'pendente'), myOrgs = S.orgs.filter(x => x.members.includes(me));
  const tDesc = t => [t.give && t.give.length ? `cede ${t.give.map(i => (S.T[i] || {}).n).join(', ')}` : '', t.take && t.take.length ? `exige ${t.take.map(i => (S.T[i] || {}).n).join(', ')}` : '',
    t.pay ? `pagamento ${t.pay > 0 ? 'do proponente' : 'exigido'}: ${Math.abs(t.pay)}` : '', t.org ? `organização: ${(S.orgs.find(x => x.id === t.org) || {}).name}` : '',
    t.item ? `${t.dir === 'vendo' ? 'vende' : 'compra'} ${t.qty}/h de ${RN(t.item)} a ${t.price} por ${t.hours}h` : ''].filter(Boolean).join(' · ');
  return html`<div>
    <${H4} i="quill">Propostas</${H4}>${inbox.length ? inbox.map(p => html`<div key=${p.id} class="card"><b>${PN(p)}</b> ${p.from_c === me ? `→ ${S.C[p.to_c].name}` : `de ${S.C[p.from_c].name}`}
      <div class="small">${tDesc(p.terms)}</div>${p.to_c === me ? html`<${Btn} cls="ok" onClick=${() => P('respond', { p_id: p.id, p_accept: true }, 'Proposta aceita')}>Aceitar</${Btn}><${Btn} cls="red" onClick=${() => P('respond', { p_id: p.id, p_accept: false })}>Recusar</${Btn}>`
        : html`<${Btn} onClick=${() => P('respond', { p_id: p.id, p_accept: false })}>Cancelar</${Btn}>`}</div>`) : html`<div class="muted">Nenhuma proposta pendente.</div>`}
    <${H4} i="globe">Países</${H4}><${Sel} v=${cid} set=${setCid} ph="Escolha um país…" opts=${cOpts(S).map(([k, n]) => [k, `${n} — ${relation(S, me, k)}`])} />
    ${o && html`<div class="card"><div class="row"><${Flag} f=${o.flag} /> <b>${o.name}</b> · ${o.government} · ${o.ideology}<span class="sp" /><b style=${{ color: REL[relation(S, me, o.id)] }}>${relation(S, me, o.id)}</b></div>
      <div class="small">${leaderTitle(o)} ${o.leader} · Pop. ${fmt(o.pop)} · Militar ${fmt(o.mil)} · Infâmia ${Math.round(o.infamy)} · Fronteiras ${o.border}${o.treasury != null ? ` · Tesouro (espionado) ${fmt(o.treasury)}` : ''}</div>
      <div class="form"><${Sel} v=${kind} set=${setKind} opts=${Object.entries(D.tr)} /><${Btn} onClick=${() => P('propose', { p_to: cid, p_kind: kind, p_terms: {} }, 'Proposta enviada')}>Propor tratado</${Btn}></div>
      <div class="form"><${Sel} v=${deal} set=${setDeal} opts=${atWar(S, me, cid) ? [['paz', 'Tratado de paz'], ['ultimato', 'Ultimato / exigir rendição']] : [['acordo', 'Acordo / compra ou cessão de território'], ['ultimato', 'Ultimato']]} /></div>
      <${Terms} S=${S} other=${cid} v=${terms} set=${setTerms} /><${Btn} onClick=${() => P('propose', { p_to: cid, p_kind: deal, p_terms: terms }, 'Proposta enviada').then(() => setTerms({ give: [], take: [], pay: 0 }))}>Enviar ${deal === 'paz' ? 'proposta de paz' : deal}</${Btn}>
      <${H4} i="suitcase">Apoio / ajuda</${H4}><div class="form"><input type="number" placeholder="dinheiro" value=${gift.m} onInput=${e => setGift({ ...gift, m: +e.target.value })} style=${{ width: 90 }} />
        <${Sel} v=${gift.r} set=${r => setGift({ ...gift, r })} opts=${Object.keys(D.res).map(k => [k, RN(k)])} /><input type="number" placeholder="qtd" value=${gift.q} onInput=${e => setGift({ ...gift, q: +e.target.value })} style=${{ width: 70 }} />
        <label><input type="checkbox" checked=${gift.s} onChange=${() => setGift({ ...gift, s: !gift.s })} />secreta</label>
        <${Btn} onClick=${() => P('gift', { p_to: cid, p_money: gift.m, p_res: gift.q > 0 ? { [gift.r]: gift.q } : {}, p_units: su.length ? su : null, p_secret: gift.s }, 'Ajuda enviada')}>Enviar${su.length ? ` + ${su.length} unidades` : ''}</${Btn}></div>
      <div class="form"><${Btn} onClick=${() => P('sanction', { p_target: cid })}>${S.treaties.some(t => t.kind === 'sancao' && t.a === me && t.b === cid) ? 'Suspender sanções' : 'Aplicar sanções'}</${Btn}>
        ${!atWar(S, me, cid) && html`<${Btn} cls="red" onClick=${() => confirm('Declarar guerra a ' + o.name + '?') && P('declare_war', { p_target: cid }, 'Guerra declarada')}>Declarar guerra</${Btn}>`}
        ${myOrgs.length > 0 && html`<${Sel} v=${inv} set=${setInv} ph="Convidar para…" opts=${myOrgs.map(x => [x.id, x.name])} /><${Btn} disabled=${!inv} onClick=${() => P('propose', { p_to: cid, p_kind: 'alianca', p_terms: { org: inv } }, 'Convite enviado')}>Convidar</${Btn}>`}</div></div>`}
    <${H4} i="treaty">Tratados vigentes</${H4}>${S.treaties.filter(t => t.a === me || t.b === me).map(t => html`<div key=${t.id} class="row">${D.tr[t.kind] || 'Sanções'} — ${S.C[t.a === me ? t.b : t.a].name}<span class="sp" />
      <${Btn} onClick=${() => P('cancel_treaty', { p_id: t.id }, 'Tratado encerrado')}>Encerrar</${Btn}></div>`)}
    <${H4} i="org">Organizações internacionais</${H4}>${S.orgs.map(x => html`<div key=${x.id} class="card"><b>${x.flag} ${x.name}</b> <span class="small">(${D.org[x.kind]}) · líder: ${(S.C[x.leader] || {}).name || '—'}</span>
      <div class="small">${x.descr}${x.rules ? ' · Regras: ' + x.rules : ''} · Efeito: ${fxTxt(D.orgfx[x.kind])}</div>
      <div class="chips">${x.members.map(m => html`<span key=${m} class="chip">${(S.C[m] || {}).name}${x.leader === me && m !== me ? html` <a onClick=${() => P('org_action', { p_org: x.id, p_act: 'expulsar', p_country: m })}>expulsar</a> <a onClick=${() => P('org_action', { p_org: x.id, p_act: 'lider', p_country: m })}>líder</a>` : ''}</span>`)}</div>
      ${x.members.includes(me) && html`<${Btn} onClick=${() => P('org_action', { p_org: x.id, p_act: 'sair' }, 'Você saiu da organização')}>Sair</${Btn}>`}</div>`)}
    <details><summary>Criar organização / aliança (custa 100)</summary><div class="form col"><input placeholder="Nome" value=${org.name} onInput=${e => setOrg({ ...org, name: e.target.value })} />
      <${Sel} v=${org.kind} set=${k => setOrg({ ...org, kind: k })} opts=${Object.entries(D.org)} /><input placeholder="Sigla ou símbolo" value=${org.flag} onInput=${e => setOrg({ ...org, flag: e.target.value })} />
      <input placeholder="Descrição e objetivos" value=${org.descr} onInput=${e => setOrg({ ...org, descr: e.target.value })} /><input placeholder="Regras e compromissos" value=${org.rules} onInput=${e => setOrg({ ...org, rules: e.target.value })} />
      <${Btn} onClick=${() => P('create_org', { p: org }, 'Organização criada')}>Fundar</${Btn}></div></details></div>`;
}

// ---------------- COMÉRCIO ----------------
function Spark({ pts, w = 74, h = 20 }) {
  if (!pts || pts.length < 2) return html`<span class="muted small">—</span>`; const vs = pts.map(p => +p[1]), mn = Math.min(...vs), mx = Math.max(...vs), r = mx - mn || 1, up = vs[vs.length - 1] >= vs[0];
  return html`<svg width=${w} height=${h} class="spark"><polyline fill="none" stroke=${up ? '#86b84f' : '#d0573f'} stroke-width="1.5" points=${vs.map((v, i) => `${(i / (vs.length - 1) * w).toFixed(1)},${(h - 2 - (v - mn) / r * (h - 4)).toFixed(1)}`).join(' ')} /></svg>`;
}
function PTrade({ S }) {
  const [it, setIt] = useState('oil'); const [q, setQ] = useState(10); const [pr, setPr] = useState(''); const [tab, setTab] = useState('g'); const [ex, setEx] = useState('');
  const [ct, setCt] = useState({ to: '', dir: 'vendo', item: 'iron', qty: 2, price: 5, hours: 48 }); useTick(30000);
  if (!S.my) return html`<${NoC} />`;
  const c = S.my, ph = k => (S.ph || {})[k] || [], last = k => { const a = ph(k); return a.length ? +a[a.length - 1][1] : S.prices[k]; };
  const ch = k => { const a = ph(k), t0 = now() / 1000 - 86400, o = a.find(p => p[0] >= t0); return o ? (S.prices[k] - o[1]) / o[1] * 100 : 0; };
  const shock = k => S.shocks && S.shocks[k] && Date.parse(S.shocks[k].until) > now() ? S.shocks[k].m : null;
  const ask = k => S.orders.filter(o => o.item === k && o.side !== 'buy' && !o.black), bid = k => S.orders.filter(o => o.item === k && o.side === 'buy');
  const t24 = S.trades.filter(t => Date.parse(t.t) > now() - 864e5 && t.i === it), top = key => { const m = {}; t24.forEach(t => t[key] && (m[t[key]] = (m[t[key]] || 0) + +t.q)); return Object.entries(m).sort((a, b) => b[1] - a[1]).slice(0, 3); };
  const myOrgs = S.orgs.filter(x => x.members.includes(S.me)), all = Object.keys(D.res);
  const Row = ({ k }) => { const v = ch(k), sh = shock(k);
    return html`<tr class=${it === k ? 'on' : ''} onClick=${() => setIt(k)}><td><${Ic} n=${k} s=${16} /> ${RN(k)}</td><td><b>${S.prices[k]}</b></td><td class=${v > 0 ? 'pos' : v < 0 ? 'neg' : ''}>${v ? (v > 0 ? '▲' : '▼') + Math.abs(v).toFixed(0) + '%' : '—'}</td>
      <td><${Spark} pts=${ph(k)} /></td><td>${fmt(ask(k).reduce((a, o) => a + +o.qty, 0))}</td><td>${fmt(bid(k).reduce((a, o) => a + +o.qty, 0))}</td>
      <td class="small">${sh ? html`<b class=${sh > 1 ? 'neg' : 'pos'}>${sh > 1 ? 'choque' : 'excesso'}</b>` : S.prices[k] > D.res[k].p * 1.3 ? html`<b class="neg">em falta</b>` : S.prices[k] < D.res[k].p * .7 ? 'sobrando' : ''}</td></tr>`; };
  return html`<div><${Tabs} tabs=${[['g', 'Mercado mundial'], ['c', 'Contratos'], ['n', 'Mercado negro']]} v=${tab} set=${setTab} />
  ${tab === 'g' ? html`<div>
    <table class="mkt"><tr><th>Produto</th><th>Preço</th><th>24h</th><th>7 dias</th><th>Oferta</th><th>Procura</th><th></th></tr>
      <tr class="sec"><td colspan="7">Matérias-primas</td></tr>${RAW().map(k => html`<${Row} key=${k} k=${k} />`)}
      <tr class="sec"><td colspan="7">Produtos industriais</td></tr>${GOODS().map(k => html`<${Row} key=${k} k=${k} />`)}</table>
    <div class="card"><div class="row"><${Ic} n=${it} s=${28} /><h3>${RN(it)}</h3><span class="sp" />preço mundial <b>${S.prices[it]}</b> · seu estoque <b>${fmt((c.stock || {})[it])}</b></div>
      <${Chart} data=${ph(it).map(p => ({ t: p[0], p: p[1] }))} keys=${[{ k: 'p', c: '#d6b86b', n: 'Preço (7 dias)' }]} />
      <div class="small">Maiores vendedores 24h: ${top('s').map(([k, v]) => `${(S.C[k] || {}).name || '?'} (${fmt(v)})`).join(', ') || '—'} · compradores: ${top('b').map(([k, v]) => `${(S.C[k] || {}).name || '?'} (${fmt(v)})`).join(', ') || '—'}</div>
      <div class="form">Qtd <input type="number" value=${q} min="1" onInput=${e => setQ(+e.target.value)} style=${{ width: 70 }} />
        <${Btn} onClick=${() => P('market', { p_act: 'npc_buy', p: { item: it, qty: q } }, 'Importado')}>Importar · ${fmt(S.prices[it] * 1.25 * q)}</${Btn}>
        <${Btn} onClick=${() => P('market', { p_act: 'npc_sell', p: { item: it, qty: q } }, 'Exportado')}>Exportar · ${fmt(S.prices[it] * .8 * q)}</${Btn}></div>
      <div class="book"><div><b>Vendendo (ofertas)</b>${ask(it).sort((a, b) => a.price - b.price).map(o => html`<div key=${o.id} class="row small">${fmt(o.qty)} a <b>${o.price}</b> · ${o.mine ? 'você' : (S.C[o.c] || {}).name}${o.org ? ' · exclusiva' : ''}<span class="sp" />
          ${o.mine ? html`<a onClick=${() => P('market', { p_act: 'cancel', p: { id: o.id } })}>retirar</a>` : html`<${Btn} onClick=${() => P('market', { p_act: 'buy', p: { id: o.id, qty: Math.min(q, o.qty) } }, 'Compra concluída')}>Comprar ${fmt(Math.min(q, o.qty))}</${Btn}>`}</div>`)}</div>
        <div><b>Comprando (lances)</b>${bid(it).sort((a, b) => b.price - a.price).map(o => html`<div key=${o.id} class="row small">${fmt(o.qty)} a <b>${o.price}</b> · ${o.mine ? 'você' : (S.C[o.c] || {}).name}${o.org ? ' · exclusiva' : ''}<span class="sp" />
          ${o.mine ? html`<a onClick=${() => P('market', { p_act: 'cancel', p: { id: o.id } })}>retirar</a>` : html`<${Btn} onClick=${() => P('market', { p_act: 'fill', p: { id: o.id, qty: Math.min(q, o.qty) } }, 'Venda concluída')}>Vender ${fmt(Math.min(q, o.qty))}</${Btn}>`}</div>`)}</div></div>
      <div class="form">Preço <input type="number" value=${pr} placeholder=${S.prices[it]} onInput=${e => setPr(e.target.value)} style=${{ width: 80 }} />
        ${myOrgs.length > 0 && html`<${Sel} v=${ex} set=${setEx} ph="Aberto a todos" opts=${myOrgs.map(x => [x.id, 'Só ' + x.name])} />`}
        <${Btn} onClick=${() => P('market', { p_act: 'sell', p: { item: it, qty: q, price: +(pr || S.prices[it]), org: ex } }, 'Oferta publicada')}>Ofertar venda</${Btn}>
        <${Btn} onClick=${() => P('market', { p_act: 'bid', p: { item: it, qty: q, price: +(pr || S.prices[it]), org: ex } }, 'Lance publicado (dinheiro reservado)')}>Dar lance de compra</${Btn}></div>
      <div class="small muted">Importar/exportar usa o mercado neutro (+25% / −20%). Ofertas e lances entre países pagam o preço combinado; ofertas exclusivas valem só para membros da organização. Guerras, sanções e choques mexem nos preços.</div></div></div>`
  : tab === 'c' ? html`<div>
    <${H4} i="quill">Seus contratos</${H4}>${S.contracts.length ? S.contracts.map(x => { const sell = x.seller === S.me, pt = S.C[sell ? x.buyer : x.seller] || {};
      return html`<div key=${x.id} class="card"><div class="row"><${Ic} n=${x.item} s=${20} /><b>${sell ? 'Venda' : 'Compra'}: ${x.qty}/h de ${RN(x.item)}</b> a ${x.price} · ${pt.name}<span class="sp" /><b class=${x.status === 'ativo' ? 'pos' : 'neg'}>${x.status}</b></div>
        <div class="small">Entregue: ${fmt(x.delivered)} · termina em ${dur(Date.parse(x.ends_at) - now())}</div>
        ${['ativo', 'suspenso'].includes(x.status) && html`<${Btn} cls="red" onClick=${() => confirm('Romper o contrato? (+2 infâmia)') && P('cancel_contract', { p_id: x.id }, 'Contrato rompido')}>Romper</${Btn}>`}</div>`; }) : html`<p class="muted">Nenhum contrato.</p>`}
    <${H4} i="treaty">Propor contrato de fornecimento</${H4}><div class="small muted">Entrega automática a cada hora enquanto houver mercadoria e dinheiro. Suspende sozinho se faltar.</div>
    <div class="form"><${Sel} v=${ct.to} set=${v => setCt({ ...ct, to: v })} ph="País…" opts=${cOpts(S)} /><${Sel} v=${ct.dir} set=${v => setCt({ ...ct, dir: v })} opts=${[['vendo', 'Eu vendo'], ['compro', 'Eu compro']]} />
      <${Sel} v=${ct.item} set=${v => setCt({ ...ct, item: v })} opts=${all.map(k => [k, RN(k)])} /></div>
    <div class="form"><label>Qtd/h <input type="number" value=${ct.qty} onInput=${e => setCt({ ...ct, qty: +e.target.value })} style=${{ width: 60 }} /></label>
      <label>Preço <input type="number" value=${ct.price} onInput=${e => setCt({ ...ct, price: +e.target.value })} style=${{ width: 70 }} /></label>
      <label>Horas <input type="number" value=${ct.hours} onInput=${e => setCt({ ...ct, hours: +e.target.value })} style=${{ width: 60 }} /></label>
      <${Btn} disabled=${!ct.to} onClick=${() => P('propose', { p_to: ct.to, p_kind: 'contrato', p_terms: { item: ct.item, qty: ct.qty, price: ct.price, hours: ct.hours, dir: ct.dir } }, 'Contrato proposto')}>Propor</${Btn}></div>
    <div class="small">Total: ${fmt(ct.qty * ct.hours)} de ${RN(ct.item)} por ${fmt(ct.qty * ct.hours * ct.price)} · preço mundial ${S.prices[ct.item]}</div></div>`
  : c.intel_level < 1 ? html`<p class="muted">O mercado negro exige um serviço secreto (nível Básico) — veja Inteligência. Contrabando tem risco de golpe, apreensão e escândalo.</p>`
  : html`<div><${H4} i="mask">Contrabandistas</${H4}><div class="small muted">Furam sanções e guerras. Cobram 70% a mais e 12% das vezes somem com o dinheiro.</div>
    <table><tr><th>Produto</th><th>Preço</th><th></th></tr>${['arms', 'veh', 'plane', 'oil', 'alu', 'rare', 'uranium'].map(k => html`<tr key=${k}><td><${Ic} n=${k} /> ${RN(k)}</td><td>${fmt(S.prices[k] * 1.7)}</td>
      <td><${Btn} onClick=${() => P('market', { p_act: 'black_buy', p: { item: k, qty: q } })}>Comprar ${q}</${Btn}></td></tr>`)}</table>
    <div class="form">Qtd <input type="number" value=${q} onInput=${e => setQ(+e.target.value)} style=${{ width: 70 }} /><${Sel} v=${it} set=${setIt} opts=${all.map(k => [k, RN(k)])} />
      <${Btn} onClick=${() => P('market', { p_act: 'black_sell', p: { item: it, qty: q } }, 'Vendido aos contrabandistas')}>Vender por ${fmt(S.prices[it] * .9 * q)}</${Btn}>
      <${Btn} onClick=${() => P('market', { p_act: 'sell', p: { item: it, qty: q, price: +(pr || S.prices[it] * 1.4), black: true } }, 'Oferta clandestina publicada')}>Ofertar anônimo</${Btn}></div>
    <${H4} i="cargo">Ofertas anônimas</${H4}>${S.orders.filter(o => o.black).map(o => html`<div key=${o.id} class="row"><${Ic} n=${o.item} /> ${fmt(o.qty)} ${RN(o.item)} a ${o.price} — ${o.mine ? 'sua' : 'vendedor desconhecido'}<span class="sp" />
      ${o.mine ? html`<a onClick=${() => P('market', { p_act: 'cancel', p: { id: o.id } })}>retirar</a>` : html`<${Btn} onClick=${() => P('market', { p_act: 'buy', p: { id: o.id, qty: o.qty } })}>Comprar</${Btn}>`}</div>`)}</div>`}</div>`;
}

// ---------------- INTELIGÊNCIA ----------------
function PIntel({ S }) {
  const c = S.my; const [nm, setNm] = useState(''); const [op, setOp] = useState('info'); const [tg, setTg] = useState(''); useTick(); if (!c) return html`<${NoC} />`;
  const lv = c.intel_level, o = D.ops[op];
  return html`<div><div class="hero"><div class="portrait ph"><${Ic} n="intel" s=${48} /></div><div><h2>${c.intel_name || 'Sem serviço secreto'}</h2><div>Nível: <b>${INTEL[lv]}</b> (${lv}/4) · ${1 + lv} operações ao mesmo tempo</div>
    <div class="small muted">Manutenção ${(0.4 * lv).toFixed(1)}/h. Nível maior = mais sucesso, menos descoberta, mais proteção.</div></div></div>
    ${lv < 4 && html`<div class="form"><input placeholder="Nome da agência" value=${nm} onInput=${e => setNm(e.target.value)} /><${Btn} onClick=${() => P('intel', { p_act: 'upgrade', p: { name: nm } }, 'Serviço secreto ampliado')}>${lv ? 'Subir para ' + INTEL[lv + 1] : 'Criar agência'} · ${150 * (lv + 1) * (lv + 1)}</${Btn}></div>`}
    <${H4} i="eye">Nova operação</${H4}><div class="form"><${Sel} v=${op} set=${setOp} opts=${Object.entries(D.ops).sort((a, b) => a[1].lv - b[1].lv).map(([k, x]) => [k, `${x.n} (nível ${x.lv})`])} /><${Sel} v=${tg} set=${setTg} ph="Alvo…" opts=${cOpts(S)} />
      <${Btn} disabled=${!tg || lv < o.lv} onClick=${() => P('intel', { p_act: 'op', p: { kind: op, target: tg } }, 'Agentes enviados')}>Executar · ${o.c} · ${o.h}h</${Btn}></div>
    <div class="small muted">Sucesso e descoberta são sorteados no servidor e dependem do seu nível contra o do alvo. O alvo não sabe quem agiu, mas pode investigar.</div>
    <${H4} i="hist">Operações</${H4}>${S.ops.map(x => html`<div key=${x.id} class="row">${D.ops[x.kind].n} → ${(S.C[x.target] || {}).name}<span class="sp" />
      ${x.result ? html`<b class=${x.result === 'sucesso' ? 'pos' : 'neg'}>${x.result}</b>${x.discovered ? ' · descoberta' : ''}` : dur(Date.parse(x.done_at) - now())}</div>`)}</div>`;
}

// ---------------- HISTÓRICO ----------------
function PHist({ S }) {
  const [k, setK] = useState('');
  const kinds = [['', 'Tudo'], ['guerra', 'Guerra'], ['diplo', 'Diplomacia'], ['interno', 'Política interna'], ['evento', 'Eventos'], ['alerta', 'Alertas'], ['pesquisa', 'Pesquisa'], ['obra', 'Obras'], ['intel', 'Inteligência'], ['comercio', 'Comércio']];
  return html`<div><${Sel} v=${k} set=${setK} opts=${kinds} />${S.events.filter(e => !k || e.kind === k).map(e => html`<div key=${e.id} class=${'ev ' + e.kind}><${Ic} n=${EVI[e.kind] || 'castle'} s=${14} /><span class="muted small">${when(e.created_at)}</span> ${e.only_for ? html`<b class="secret">SECRETO</b> ` : ''}${clean(e.txt)}</div>`)}</div>`;
}

// ---------------- TERRITÓRIO / PAÍS SELECIONADO ----------------
function SelPanel({ S, sel, setSel, su, setSu, open }) {
  const [st, setSt] = useState('padrao'); useTick();
  if (sel.c) { const c = S.C[sel.c]; const t = c && S.territories.find(x => x.c === c.id); return c ? html`<div class="side"><a class="x" onClick=${() => setSel(null)}>×</a>
    <div class="row"><${Flag} f=${c.flag} s=${30} /><h3>${c.name}</h3></div><div class="small">${c.government} · ${c.ideology} · ${leaderTitle(c)} ${c.leader}</div>
    ${c.portrait && html`<img class="portrait" src=${c.portrait} />`}
    <div class="grid"><${Stat} l="População" v=${fmt(c.pop)} /><${Stat} l="Área" v=${fmt(c.area)} /><${Stat} l="Militar" v=${fmt(c.mil)} /><${Stat} l="Relação" v=${relation(S, S.me, c.id)} /></div>
    ${c.id !== S.me && S.my && html`<${Btn} onClick=${() => open('diplo', c.id)}>Diplomacia</${Btn}>`}${t && html`<${Btn} onClick=${() => setSel({ t: t.id })}>Ver região</${Btn}>`}</div>` : null; }
  const t = S.T[sel.t]; if (!t) return null; const c = S.C[t.c], mine = t.c === S.me, my = S.my;
  const war = c && my && atWar(S, S.me, c.id), canHit = my && !mine && (!c || war), mv = su.filter(id => { const u = S.units.find(x => x.id === id); return u && u.t !== t.id; });
  return html`<div class="side"><a class="x" onClick=${() => setSel(null)}>×</a>
    <div class="row">${c ? html`<${Flag} f=${c.flag} s=${26} />` : html`<${Ic} n="skull" s=${24} />`}<div><h3>${t.n}</h3><div class="small">${c ? c.name : 'Sem governo (rebeldes)'}${t.o ? ` · ocupado de ${(S.C[t.o] || {}).name}` : ''}</div></div></div>
    <div class="grid"><${Stat} l="Terreno" v=${t.te} /><${Stat} l="Área" v=${fmt(t.a) + ' km²'} /><${Stat} l="População" v=${fmt(t.p)} /><${Stat} l="Rebeldes" v=${t.rb} c=${t.rb > 0 ? 'neg' : ''} /></div>
    <div class="res">${Object.entries(t.r || {}).filter(e => e[1] > 0).map(([k, v]) => html`<span key=${k} title=${RN(k)}><${Ic} n=${k} s=${15} />${v}</span>`)}</div>
    <h4>Construções</h4><div>${t.b.length ? t.b.map(b => html`<span key=${b.id} class="chip" title=${D.b[b.k].n}><${Ic} n=${b.k} />${ready(b) ? '' : ' ' + dur(Date.parse(b.d) - now())}</span>`) : html`<span class="muted">nenhuma</span>`}</div>
    <h4>Tropas</h4>${t.u.length ? t.u.map(u => html`<label key=${u.id} class="unit">${u.c === S.me ? html`<input type="checkbox" disabled=${!ready(u)} checked=${su.includes(u.id)} onChange=${() => setSu(su.includes(u.id) ? su.filter(x => x !== u.id) : [...su, u.id])} />` : ''}
      <i class="dot" style=${{ background: (S.C[u.c] || {}).color }} /><${Ic} n=${u.k} /> ${D.u[u.k].n} ${Math.round(u.s * 100)}% ${ready(u) ? '' : dur(Date.parse(u.r) - now())}</label>`) : html`<span class="muted">nenhuma</span>`}
    ${mine && html`<div class="form"><${Btn} onClick=${() => open('infra', t.id)}>Construir</${Btn}><${Btn} onClick=${() => open('prod', t.id)}>Recrutar</${Btn}></div>`}
    ${mv.length > 0 && !canHit && html`<${Btn} cls="ok" onClick=${() => P('move_units', { p_ids: mv, p_target: t.id }, 'Tropas em movimento').then(() => setSu([]))}>Mover ${mv.length} unidade(s) para cá</${Btn}>`}
    ${canHit && html`<div class="card"><b>Ataque</b><div class="small">${su.length ? `Usará ${su.length} unidade(s) selecionada(s)` : 'Usará todas as unidades prontas ao alcance'} (terra 400 km, mar 800 km, ar 1500 km).</div>
      <div class="form"><${Sel} v=${st} set=${setSt} opts=${Object.entries(D.st).map(([k, x]) => [k, x.n])} />
      <${Btn} cls="red" onClick=${() => (['nuclear', 'quimico'].includes(st) ? confirm('Usar arma de destruição em massa? O mundo inteiro reagirá.') : true) && P('attack', { p_target: t.id, p_strat: st, p_ids: su.length ? su : null }).then(r => { toast(clean(r.msg), r.win ? 'ok' : 'err'); setSu([]); })}>Atacar</${Btn}></div></div>`}
    ${c && !mine && my && !war && html`<div class="small muted">Para atacar, declare guerra a ${c.name} (Diplomacia ou Militar).</div>`}
    ${c && !mine && html`<${Btn} onClick=${() => setSel({ c: c.id })}>Ver país</${Btn}>`}</div>`;
}
