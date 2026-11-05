// World Nations — telas: login, salas e jogo
const MENUS = [['map', 'Mapa'], ['country', 'País'], ['gov', 'Governo'], ['pop', 'População'], ['econ', 'Economia'], ['infra', 'Infraestrutura', 'Obras'],
  ['prod', 'Produção'], ['mil', 'Militar'], ['tech', 'Tecnologia'], ['diplo', 'Diplomacia'], ['trade', 'Comércio'], ['intel', 'Inteligência', 'Espiões'], ['hist', 'Histórico']];
const PANELS = { country: PCountry, gov: PGov, pop: PPop, econ: PEcon, infra: PInfra, prod: PProd, mil: PMil, tech: PTech, diplo: PDiplo, trade: PTrade, intel: PIntel, hist: PHist };
const LAYERS = [['pol', 'Político'], ['terreno', 'Terreno'], ['militar', 'Militar'], ['recursos', 'Recursos'], ['pop', 'População'], ['econ', 'Econômico'], ['diplo', 'Diplomático']];

function Toasts() {
  const [l, setL] = useState([]);
  useEffect(() => { const f = e => { setL(x => [...x.slice(-4), e.detail]); setTimeout(() => setL(x => x.filter(y => y.id !== e.detail.id)), 6000); }; bus.addEventListener('toast', f); return () => bus.removeEventListener('toast', f); }, []);
  return html`<div class="toasts">${l.map(t => html`<div key=${t.id} class=${'toast ' + t.type}>${clean(t.msg)}</div>`)}</div>`;
}
function WorldBG() { const r = useRef(); useEffect(() => { paintWorld(r.current); }, []); return html`<canvas class="worldbg" ref=${r} />`; }

// ---------------- CONTA ----------------
function Auth({ recovery }) {
  const [tab, setTab] = useState(recovery ? 'new' : 'in'); const [f, setF] = useState({ email: '', pass: '', user: '' }); const [msg, setMsg] = useState('');
  const on = k => e => setF({ ...f, [k]: e.target.value });
  const go = async () => {
    setMsg(''); let r;
    if (tab === 'in') r = await sb.auth.signInWithPassword({ email: f.email, password: f.pass });
    if (tab === 'up') { r = await sb.auth.signUp({ email: f.email, password: f.pass, options: { data: { username: f.user }, emailRedirectTo: location.origin + location.pathname } }); if (!r.error && !r.data.session) setMsg('Conta criada. Confirme pelo link enviado ao seu e-mail.'); }
    if (tab === 'fg') { r = await sb.auth.resetPasswordForEmail(f.email, { redirectTo: location.origin + location.pathname }); if (!r.error) setMsg('Link de recuperação enviado para o seu e-mail.'); }
    if (tab === 'new') { r = await sb.auth.updateUser({ password: f.pass }); if (!r.error) { location.hash = ''; location.reload(); } }
    if (r && r.error) setMsg(r.error.message);
  };
  return html`<div class="auth"><${WorldBG} /><div class="dossier"><div class="stamp">Confidencial</div><div class="logo">WORLD NATIONS</div>
    <div class="sub">Simulador geopolítico · arquivo de acesso</div>
    ${tab !== 'new' && html`<div class="ftabs">${[['in', 'Entrar'], ['up', 'Alistar-se'], ['fg', 'Perdi a senha']].map(([k, n]) => html`<button key=${k} class=${tab === k ? 'on' : ''} onClick=${() => setTab(k)}>${n}</button>`)}</div>`}
    <form onSubmit=${e => { e.preventDefault(); go(); }}>
      ${tab === 'up' && html`<label>Nome de usuário<input value=${f.user} onInput=${on('user')} required minlength="3" /></label>`}
      ${tab !== 'new' && html`<label>E-mail<input type="email" value=${f.email} onInput=${on('email')} required /></label>`}
      ${tab !== 'fg' && html`<label>${tab === 'new' ? 'Nova senha' : 'Senha'}<input type="password" value=${f.pass} onInput=${on('pass')} required minlength="6" /></label>`}
      <button class="btn big ok">${{ in: 'Entrar', up: 'Criar conta', fg: 'Enviar link', new: 'Salvar nova senha' }[tab]}</button></form>
    ${msg && html`<p class="msg">${msg}</p>`}</div><${Credit} /></div>`;
}
const Credit = () => html`<div class="credit">Ícones: game-icons.net (CC BY 3.0)</div>`;

// ---------------- SALAS ----------------
function Lobby({ open }) {
  const [d, setD] = useState(null); const [nm, setNm] = useState(''); const [code, setCode] = useState(''); const [un, setUn] = useState('');
  const load = () => sb.rpc('my_matches').then(r => { setD(r.data); setUn((r.data || {}).user || ''); });
  useEffect(() => { reloadNow = load; load(); }, []);
  return html`<div class="auth"><${WorldBG} /><div class="dossier wide"><div class="row"><div class="logo">WORLD NATIONS</div><span class="sp" /><button class="btn" onClick=${() => sb.auth.signOut()}>Sair</button></div>
    ${!d ? 'Carregando…' : html`<div>
    <div class="cols"><div><h4>Ficha do jogador</h4><div class="form"><input value=${un} onInput=${e => setUn(e.target.value)} placeholder="Nome de usuário" /><${Btn} onClick=${() => rpc('set_username', { p_name: un }, 'Nome salvo')}>Salvar</${Btn}></div></div>
      <div><h4>Nova partida</h4><div class="form"><input value=${nm} onInput=${e => setNm(e.target.value)} placeholder="Nome da partida" /><${Btn} cls="ok" onClick=${async () => open(await rpc('create_match', { p_name: nm }, 'Sala criada'))}>Criar sala</${Btn}></div></div>
      <div><h4>Entrar com código</h4><div class="form"><input value=${code} onInput=${e => setCode(e.target.value)} placeholder="Ex.: A1B2C3" /><${Btn} onClick=${async () => open(await rpc('join_match', { p_code: code }))}>Entrar</${Btn}></div></div></div>
    <h4>Minhas partidas</h4>${d.matches.length ? html`<table><tr><th>Partida</th><th>Código</th><th>Estado</th><th>Seu país</th><th>Jogadores</th><th>Criada</th><th></th></tr>
      ${d.matches.map(m => html`<tr key=${m.id}><td>${m.name}${m.host ? html` <${Ic} n="crown" s=${13} />` : ''}</td><td><code>${m.code}</code></td><td>${m.status === 'lobby' ? 'Preparação' : 'Em andamento'}</td><td>${m.country || '—'}</td>
        <td>${m.players}</td><td>${when(m.created)}</td><td><button class="btn" onClick=${() => open(m.id)}>Abrir</button></td></tr>`)}</table>` : html`<p class="muted">Nenhuma partida ainda.</p>`}</div>`}</div><${Credit} /></div>`;
}

// ---------------- EDITOR: novo país / nova região ----------------
function DrawBar({ S, draw, setDraw }) {
  const a = areaKm2(draw.pts), country = draw.kind === 'country', pk = country ? placeKind(draw.pts, S) : { k: '', f: 1 };
  const [f, setF] = useState({ name: '', flag: '🦅', color: '#' + ((Math.random() * 0xffffff) | 0).toString(16).padStart(6, '0'), capital_name: '', ideology: 'Democracia', government: 'República', leader: '', party: '' });
  const on = k => e => setF({ ...f, [k]: e.target.value });
  const where = pk.k && html`<span class=${'place ' + pk.k.split(' ')[0]}>${pk.k === 'ilha isolada' ? 'Ilha isolada: o país encolhe ~58%' : pk.k === 'interior' ? 'Interior: o país cresce ~80%' : 'Litoral / perto de vizinhos: tamanho normal'}</span>`;
  if (draw.stage === 'form') return html`<div class="modal"><div class="box">${country ? html`<h3>Fundar nação</h3>${where}
    <div class="form col"><label>Nome do país<input value=${f.name} onInput=${on('name')} /></label>
      <div class="row">Bandeira: <${Flag} f=${f.flag} s=${30} /><input style=${{ width: 70 }} value=${f.flag.startsWith('data:') ? '' : f.flag} placeholder="emoji" onInput=${on('flag')} />
        <label class="up">ou enviar imagem<input type="file" accept="image/*" onChange=${async e => e.target.files[0] && setF({ ...f, flag: await shrink(e.target.files[0], 90, 60) })} /></label>
        Cor: <input type="color" value=${f.color} onInput=${on('color')} /></div>
      <label>Capital<input value=${f.capital_name} onInput=${on('capital_name')} /></label>
      <div class="row"><input list="ide" placeholder="Ideologia" value=${f.ideology} onInput=${on('ideology')} /><input list="gov" placeholder="Sistema de governo" value=${f.government} onInput=${on('government')} /></div>
      <datalist id="ide">${Object.keys(D.ideo).map(k => html`<option key=${k} value=${k} />`)}</datalist><datalist id="gov">${Object.keys(D.gov).map(k => html`<option key=${k} value=${k} />`)}</datalist>
      <div class="small muted">Ideologia: ${fxTxt(D.ideo[f.ideology]) || 'personalizada (sem bônus)'} · Governo: ${fxTxt((D.gov[f.government] || {}).fx) || 'personalizado (sem bônus)'}</div>
      <div class="row"><input placeholder="Nome do líder" value=${f.leader} onInput=${on('leader')} /><input placeholder="Partido" value=${f.party} onInput=${on('party')} /></div>
      <div class="small">Área desenhada: ${fmt(a)} km² → final ~${fmt(a * pk.f)} km² (o desenho é recortado onde encosta em vizinhos). Terreno, recursos e população são sorteados pelo servidor.</div></div>
    <div class="form"><button class="btn" onClick=${() => setDraw({ ...draw, stage: 'poly', cap: null })}>Voltar</button>
      <${Btn} cls="ok" onClick=${() => P('create_country', { p: { ...f, poly: draw.pts, capital: draw.cap } }, 'Nação fundada!').then(() => setDraw(null))}>Fundar país</${Btn}></div>`
    : html`<h3>Anexar nova região</h3><div class="form col"><label>Nome da região<input value=${f.name} onInput=${on('name')} /></label>
      <div class="small">Área: ${fmt(a)} km² · custo ~${Math.round(80 + a / 800)} · precisa estar a até 300 km do seu território. A parte que invadir vizinhos é cortada.</div></div>
      <div class="form"><button class="btn" onClick=${() => setDraw({ ...draw, stage: 'poly' })}>Voltar</button>
      <${Btn} cls="ok" onClick=${() => P('claim_territory', { p_poly: draw.pts, p_name: f.name }, 'Região anexada').then(() => setDraw(null))}>Anexar</${Btn}></div>`}</div></div>`;
  return html`<div class="drawbar">${draw.stage === 'poly' ? html`<b>Desenhe ${country ? 'o formato do seu país' : 'a nova região'}</b>
    <span class="small">Clique para criar pontos · arraste para ajustar · botão direito apaga · ${fmt(a)} km²</span>${where}
    <button class="btn" onClick=${() => setDraw({ ...draw, pts: draw.pts.slice(0, -1) })}>Desfazer</button><button class="btn" onClick=${() => setDraw({ ...draw, pts: [] })}>Limpar</button>
    <button class="btn ok" disabled=${draw.pts.length < 3} onClick=${() => setDraw({ ...draw, stage: country ? 'cap' : 'form' })}>Confirmar forma</button>`
    : html`<b>Clique dentro do território para marcar a capital</b><button class="btn" onClick=${() => setDraw({ ...draw, stage: 'poly' })}>Voltar</button>`}
    <button class="btn red" onClick=${() => setDraw(null)}>Cancelar</button></div>`;
}

// jornal: grandes acontecimentos viram manchete
function Paper({ ev, day, close }) {
  const t = clean(ev.txt), i = t.search(/[!:.]/), head = i > 10 && i < 90 ? t.slice(0, i + 1) : t;
  return html`<div class="modal" onClick=${close}><div class="paper" onClick=${e => e.stopPropagation()}><div class="mast">O Correio Mundial</div>
    <div class="pline"><span>Edição extra</span><span>Dia ${day}</span><span>Preço: 1 moeda</span></div><h1>${head}</h1><p>${t}</p>
    <button class="btn" onClick=${close}>Entendido</button></div></div>`;
}

// ---------------- JOGO ----------------
function Game({ mid, leave }) {
  MID = mid;
  const [S, setS] = useState(null); const [err, setErr] = useState(null); const [menu, setMenu] = useState(null); const [pre, setPre] = useState(null);
  const [sel, setSel] = useState(null); const [mode, setMode] = useState('pol'); const [draw, setDraw] = useState(null); const [su, setSu] = useState([]); const [news, setNews] = useState([]);
  const lastEv = useRef(null), tmr = useRef();
  const load = async () => { const { data, error } = await sb.rpc('get_state', { p_match: mid }); if (error) return setErr(error.message); setS(prep(data)); };
  useEffect(() => {
    reloadNow = () => { clearTimeout(tmr.current); tmr.current = setTimeout(load, 250); }; load();
    const iv = setInterval(load, 60000);
    const ch = sb.channel('m' + mid).on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'matches', filter: 'id=eq.' + mid }, () => reloadNow()).subscribe();
    return () => { clearInterval(iv); sb.removeChannel(ch); };
  }, [mid]);
  useEffect(() => { if (!S) return; const top = S.events[0] ? S.events[0].id : 0;
    if (lastEv.current != null) { const nw = S.events.filter(e => e.id > lastEv.current);
      nw.slice(0, 3).forEach(e => toast(e.txt, ['guerra', 'alerta'].includes(e.kind) ? 'err' : 'info'));
      const big = nw.filter(e => !e.only_for && /declarou guerra|GOLPE|GUERRA CIVIL|NUCLEAR|completamente conquistado|CRISE ECONÔMICA MUNDIAL|Fundada a organização|capital de .* caiu/.test(e.txt));
      if (big.length) setNews(n => [...n, ...big.slice(0, 2)]); }
    lastEv.current = top; }, [S]);
  const t = useTick();
  if (err) return html`<div class="auth"><div class="dossier"><p>${err}</p><button class="btn" onClick=${leave}>Voltar</button></div></div>`;
  if (!S) return html`<div class="auth"><div class="dossier">Carregando o mundo…</div></div>`;
  const m = S.match, c = S.my, Pn = PANELS[menu], open = (k, x) => { setPre(x); setMenu(k); };
  const day = m.status === 'running' ? Math.floor((t - Date.parse(m.started_at)) / 864e5) + 1 : 0;
  const Slot = ({ i, v, l, cl: k }) => html`<div class="slot" title=${l}><${Ic} n=${i} s=${18} /><b class=${k || ''}>${v}</b></div>`;
  return html`<div class="game">
    <header class="top">${c ? html`<div class="flagbox"><${Flag} f=${c.flag} s=${34} /></div><div class="cname">${c.name}<small>${leaderTitle(c)} ${c.leader}</small></div>
      <${Slot} i="coins" l="Tesouro" v=${fmt(c.treasury)} cl=${c.treasury < 0 ? 'neg' : ''} /><${Slot} i="bank" l="Saldo por hora" v=${(c.income - c.expenses >= 0 ? '+' : '') + fmt(c.income - c.expenses)} cl=${c.income < c.expenses ? 'neg' : 'pos'} />
      <${Slot} i="person" l="População" v=${fmt(c.pop)} /><${Slot} i="stab" l="Estabilidade" v=${Math.round(c.stability) + '%'} cl=${c.stability < 35 ? 'neg' : ''} />
      <${Slot} i="happy" l="Satisfação" v=${Math.round(c.happiness) + '%'} cl=${c.happiness < 35 ? 'neg' : ''} /><${Slot} i="shield" l="Poder militar" v=${fmt(c.mil)} />
      <${Slot} i="food" l="Alimentos" v=${fmt((c.stock || {}).food)} cl=${(c.stock || {}).food < 20 ? 'neg' : ''} /><${Slot} i="goods" l="Produtos industriais" v=${fmt((c.stock || {}).goods)} />
      <${Slot} i="arms" l="Equipamento militar" v=${fmt((c.stock || {}).arms)} />` : html`<div class="cname">Sem nação</div>`}
      <span class="sp" /><div class="clock"><${Ic} n="clock" s=${16} /><div><b>${m.status === 'running' ? `Dia ${day} · ${new Date(t).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}` : `Preparação ${dur(Date.parse(m.prep_ends) - t)}`}</b>
        <span>${m.name} · <code>${m.code}</code></span></div></div><button class="btn" onClick=${leave}>Salas</button></header>
    <nav class="menu">${MENUS.map(([k, n, sh]) => html`<button key=${k} title=${n} class=${menu === k || (!menu && k === 'map') ? 'on' : ''} onClick=${() => open(k === 'map' ? null : k)}><${Ic} n=${k} s=${24} /><span>${sh || n}</span></button>`)}</nav>
    <${WorldMap} S=${S} mode=${mode} sel=${sel} setSel=${setSel} draw=${draw} setDraw=${setDraw} />
    <div class="layers">${LAYERS.map(([k, n]) => html`<button key=${k} class=${mode === k ? 'on' : ''} onClick=${() => setMode(k)}>${n}</button>`)}
      ${c && !draw && html`<button class="add" onClick=${() => setDraw({ kind: 'claim', stage: 'poly', pts: [] })} title="Desenhar e anexar território livre">+ Região</button>`}</div>
    ${Pn && html`<section class="panel"><div class="ph"><${Ic} n=${menu} s=${22} /><h3>${MENUS.find(x => x[0] === menu)[1]}</h3><span class="sp" /><a class="x" onClick=${() => setMenu(null)}>×</a></div>
      <div class="pb"><${Pn} key=${menu + pre} S=${S} pre=${pre} su=${su} setSu=${setSu} /></div></section>`}
    ${sel && !draw && html`<${SelPanel} S=${S} sel=${sel} setSel=${setSel} su=${su} setSu=${setSu} open=${open} />`}
    ${!c && !draw && html`<div class="lobbycard"><h3>${m.name}</h3><div>Código da sala: <code class="big">${m.code}</code></div>
      ${m.status === 'lobby' ? html`<div>Preparação de 24h termina em <b>${dur(Date.parse(m.prep_ends) - t)}</b></div>` : html`<div>A partida já começou — ainda dá para fundar um país em espaço livre.</div>`}
      <div class="small muted">No meio do oceano o país encolhe; no litoral fica normal; cercado de vizinhos cresce.</div>
      <button class="btn big ok" onClick=${() => setDraw({ kind: 'country', stage: 'poly', pts: [] })}>Desenhar meu país</button></div>`}
    ${m.status === 'lobby' && !draw && html`<div class="lobbycard small2"><b>Sala de espera</b> ${S.players.map(p => { const cc = S.countries.find(x => x.owner === p.id && x.alive);
      return html`<span key=${p.id} class="chip">${p.name}${p.id === m.host ? html` <${Ic} n="crown" s=${12} />` : ''} ${cc ? '· ' + cc.name : '· sem país'}</span>`; })}
      ${S.uid === m.host ? html`<${Btn} cls="ok" disabled=${Date.parse(m.prep_ends) > t} onClick=${() => rpc('start_match', { p_match: mid }, 'Partida iniciada!')} title="Liberado após as 24h de preparação">Iniciar partida</${Btn}>` : html`<span class="muted">Aguardando o anfitrião.</span>`}</div>`}
    ${draw && html`<${DrawBar} S=${S} draw=${draw} setDraw=${setDraw} />`}
    ${news[0] && html`<${Paper} ev=${news[0]} day=${day} close=${() => setNews(n => n.slice(1))} />`}
    <footer class="ticker"><div>${S.events.filter(e => !e.only_for).slice(0, 8).map(e => html`<span key=${e.id}>■ ${clean(e.txt)}</span>`)}</div></footer></div>`;
}

function App() {
  const [ses, setSes] = useState(undefined); const [rec, setRec] = useState(false); const [ok, setOk] = useState(!!D);
  const [mid, setMid] = useState(() => new URLSearchParams(location.hash.slice(1)).get('m'));
  useEffect(() => {
    sb.auth.getSession().then(({ data }) => setSes(data.session));
    const { data: { subscription } } = sb.auth.onAuthStateChange((ev, s) => { setSes(s); if (ev === 'PASSWORD_RECOVERY') setRec(true); });
    sb.rpc('defs').then(r => { if (r.error) toast('Banco não configurado: ' + r.error.message, 'err'); else { D = r.data; setOk(true); } });
    return () => subscription.unsubscribe();
  }, []);
  const open = id => { location.hash = id ? 'm=' + id : ''; setMid(id); };
  if (ses === undefined || !ok) return html`<div class="auth"><div class="dossier">Carregando…</div><${Toasts} /></div>`;
  return html`<${React.Fragment}>${!ses || rec ? html`<${Auth} recovery=${rec} />` : mid ? html`<${Game} key=${mid} mid=${mid} leave=${() => open(null)} />` : html`<${Lobby} open=${open} />`}<${Toasts} /></${React.Fragment}>`;
}

if (!CFG.url || CFG.url.includes('SEU-PROJETO')) document.getElementById('root').innerHTML = '<div class="auth"><div class="dossier"><div class="logo">WORLD NATIONS</div><p>Configure o arquivo <code>config.js</code> com a URL e a chave pública (anon) do seu projeto Supabase. Veja o README.</p></div></div>';
else ReactDOM.createRoot(document.getElementById('root')).render(html`<${App} />`);
