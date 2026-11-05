-- =====================================================================
-- WORLD NATIONS — parte 1/3: tabelas, segurança e definições do jogo
-- (o arquivo schema.sql já junta as 3 partes: cole ele no SQL Editor)
-- =====================================================================
create extension if not exists postgis with schema extensions;
set search_path = public, extensions;

create table if not exists profiles(id uuid primary key references auth.users on delete cascade, username text unique, created_at timestamptz default now());
create table if not exists matches(id uuid primary key default gen_random_uuid(), name text not null, code text unique not null, host uuid not null references auth.users on delete cascade,
  status text not null default 'lobby', prep_ends timestamptz not null, started_at timestamptz, last_tick timestamptz default now(), ver bigint default 0, created_at timestamptz default now());
create table if not exists players(match_id uuid references matches on delete cascade, user_id uuid references auth.users on delete cascade, joined_at timestamptz default now(), primary key(match_id,user_id));
create table if not exists countries(id uuid primary key default gen_random_uuid(), match_id uuid not null references matches on delete cascade, owner uuid references auth.users on delete set null,
  name text not null, flag text, color text not null, capital_name text, capital geometry(Point,4326), ideology text, government text,
  leader text, party text, portrait text, leader_since timestamptz default now(),
  treasury numeric default 1000, tax numeric default 0.25, conscription numeric default 0.03, emergency bool default false, focus text default 'civil',
  pop numeric default 0, happiness numeric default 60, stability numeric default 65, unemployment numeric default 0, education numeric default 0.3, infamy numeric default 0,
  gdp numeric default 0, income numeric default 0, expenses numeric default 0,
  stock jsonb default '{}', doctrines jsonb default '{}', ministers jsonb default '{}', intel_level int default 0, intel_name text,
  alive bool default true, created_at timestamptz default now(), unique(match_id,owner));
create table if not exists territories(id uuid primary key default gen_random_uuid(), match_id uuid not null references matches on delete cascade, country_id uuid references countries on delete set null,
  name text, geom geometry(Polygon,4326) not null, area numeric, pop numeric default 0, res jsonb default '{}', terrain text, occupied uuid, rebels numeric default 0, created_at timestamptz default now());
create index if not exists terr_geom on territories using gist(geom);
create index if not exists terr_match on territories(match_id);
create table if not exists buildings(id bigserial primary key, match_id uuid not null references matches on delete cascade, country_id uuid references countries on delete set null,
  territory_id uuid references territories on delete cascade, kind text not null, done_at timestamptz not null, notified bool default false);
create table if not exists research(country_id uuid references countries on delete cascade, tech text, match_id uuid references matches on delete cascade, done_at timestamptz not null, notified bool default false, primary key(country_id,tech));
create table if not exists units(id bigserial primary key, match_id uuid not null references matches on delete cascade, country_id uuid references countries on delete cascade, kind text not null,
  territory_id uuid references territories on delete cascade, strength numeric default 1, ready_at timestamptz not null, notified bool default false);
create table if not exists orgs(id uuid primary key default gen_random_uuid(), match_id uuid not null references matches on delete cascade, name text, flag text, descr text, rules text, kind text,
  leader uuid references countries on delete set null, created_at timestamptz default now());
create table if not exists org_members(org_id uuid references orgs on delete cascade, country_id uuid references countries on delete cascade, primary key(org_id,country_id));
create table if not exists proposals(id bigserial primary key, match_id uuid not null references matches on delete cascade, from_c uuid references countries on delete cascade, to_c uuid references countries on delete cascade,
  kind text not null, terms jsonb default '{}', status text default 'pendente', created_at timestamptz default now());
create table if not exists treaties(id bigserial primary key, match_id uuid not null references matches on delete cascade, a uuid references countries on delete cascade, b uuid references countries on delete cascade, kind text not null, created_at timestamptz default now());
create table if not exists wars(id bigserial primary key, match_id uuid not null references matches on delete cascade, attacker uuid references countries on delete cascade, defender uuid references countries on delete cascade, started_at timestamptz default now(), ended_at timestamptz);
create table if not exists orders(id bigserial primary key, match_id uuid not null references matches on delete cascade, country_id uuid references countries on delete cascade, item text, qty numeric, price numeric, black bool default false, created_at timestamptz default now());
create table if not exists trades(id bigserial primary key, match_id uuid not null references matches on delete cascade, item text, qty numeric, price numeric, npc bool default false, created_at timestamptz default now());
create table if not exists events(id bigserial primary key, match_id uuid not null references matches on delete cascade, kind text, txt text, only_for uuid, created_at timestamptz default now());
create index if not exists ev_match on events(match_id, id desc);
create table if not exists ops(id bigserial primary key, match_id uuid not null references matches on delete cascade, country_id uuid references countries on delete cascade, target uuid references countries on delete cascade,
  kind text, done_at timestamptz, result text, discovered bool default false, created_at timestamptz default now());
create table if not exists stats(country_id uuid references countries on delete cascade, t timestamptz default now(), pop numeric, treasury numeric, gdp numeric, mil numeric, stab numeric);
create index if not exists stats_c on stats(country_id, t desc);
create table if not exists logs(id bigserial primary key, user_id uuid, fn text, args jsonb, created_at timestamptz default now());
create index if not exists logs_u on logs(user_id, created_at);

alter table countries add column if not exists groups jsonb default '{}', add column if not exists mig jsonb default '{}', add column if not exists border text default 'controlada',
  add column if not exists industry jsonb default '{}', add column if not exists budget jsonb default '{}';
alter table orders add column if not exists side text default 'sell', add column if not exists org uuid;
alter table trades add column if not exists seller uuid, add column if not exists buyer uuid;
alter table matches add column if not exists shocks jsonb default '{}';
alter table countries add column if not exists bot text;
create table if not exists contracts(id bigserial primary key, match_id uuid not null references matches on delete cascade, seller uuid references countries on delete cascade, buyer uuid references countries on delete cascade,
  item text, qty numeric, price numeric, ends_at timestamptz, status text default 'ativo', delivered numeric default 0, created_at timestamptz default now());
create table if not exists price_hist(match_id uuid references matches on delete cascade, item text, t timestamptz default now(), p numeric);
create index if not exists ph_m on price_hist(match_id, t);

-- Segurança: RLS ligado em tudo e NENHUMA escrita direta. Tudo passa por funções validadas no servidor.
do $$ declare t text; begin
  foreach t in array array['profiles','matches','players','countries','territories','buildings','research','units','orgs','org_members','proposals','treaties','wars','orders','trades','events','ops','stats','logs','contracts','price_hist'] loop
    execute format('alter table %I enable row level security', t); end loop; end $$;
create or replace function is_member(mid uuid) returns bool language sql stable security definer set search_path=public as $$
  select exists(select 1 from players where match_id=mid and user_id=auth.uid()) $$;
drop policy if exists m_sel on matches;
create policy m_sel on matches for select to authenticated using (is_member(id));  -- só para o Realtime avisar mudanças
do $$ begin alter publication supabase_realtime add table matches; exception when others then null; end $$;

-- ---------------------------------------------------------------------
-- DEFINIÇÕES (fonte única de verdade, lida pelo servidor e pelo site)
-- ---------------------------------------------------------------------
create or replace function defs() returns jsonb language sql immutable as $j$ select $${
"res":{"oil":{"n":"Petróleo","p":6,"i":"🛢"},"iron":{"n":"Ferro","p":4,"i":"⛓"},"coal":{"n":"Carvão","p":3,"i":"⚫"},"gold":{"n":"Ouro","p":15,"i":"🥇"},"uranium":{"n":"Urânio","p":25,"i":"☢"},
 "copper":{"n":"Cobre","p":5,"i":"🟠"},"alu":{"n":"Alumínio","p":6,"i":"🔩"},"rare":{"n":"Terras raras","p":20,"i":"💎"},"wood":{"n":"Madeira","p":2,"i":"🪵"},"food":{"n":"Alimentos","p":2,"i":"🌽"},
 "mach":{"n":"Máquinas","p":18,"i":"⚙","g":1,"rc":{"iron":2,"coal":1}},"arms":{"n":"Equipamento militar","p":16,"i":"🔫","g":1,"rc":{"iron":2,"copper":0.5,"coal":0.5}},
 "veh":{"n":"Veículos","p":32,"i":"🚚","g":1,"rc":{"iron":3,"oil":1,"copper":0.5}},"plane":{"n":"Aviões","p":48,"i":"✈","g":1,"rc":{"alu":3,"oil":1,"rare":0.3}},
 "shipg":{"n":"Navios","p":42,"i":"🚢","g":1,"rc":{"iron":4,"wood":2}},"goods":{"n":"Produtos industriais","p":10,"i":"📦","g":1,"rc":{"wood":1,"copper":0.3,"iron":0.5}}},
"b":{"farm":{"n":"Fazenda","c":40,"r":{"wood":5},"h":4,"i":"🌾","e":"+3 alimentos/h"},
 "mine":{"n":"Mina","c":60,"r":{"wood":8},"h":6,"i":"⛏","e":"+50% extração da região"},
 "factory":{"n":"Fábrica","c":120,"r":{"iron":10,"wood":5},"h":10,"i":"🏭","e":"+PIB, empregos, produção militar mais rápida"},
 "power":{"n":"Usina elétrica","c":150,"r":{"iron":12,"coal":8,"mach":2},"h":12,"i":"⚡","t":"eletricidade","e":"+8% produção (consome carvão)"},
 "road":{"n":"Estradas","c":40,"r":{},"h":3,"i":"🛣","e":"+PIB, obras e tropas mais rápidas"},
 "rail":{"n":"Ferrovia","c":110,"r":{"iron":15,"wood":10,"mach":1},"h":10,"i":"🚆","t":"ferrovias","e":"+PIB, tropas 50% mais rápidas"},
 "port":{"n":"Porto","c":120,"r":{"wood":10,"iron":5},"h":10,"i":"⚓","e":"+PIB, permite navios"},
 "airport":{"n":"Aeroporto","c":160,"r":{"iron":10,"alu":5,"mach":2},"h":12,"i":"✈","t":"aviacao","e":"+PIB, permite aviões"},
 "hospital":{"n":"Hospital","c":90,"r":{"wood":5,"goods":3},"h":8,"i":"🏥","e":"+felicidade, +crescimento"},
 "school":{"n":"Escola","c":60,"r":{"wood":6},"h":6,"i":"🏫","e":"+educação, +pesquisa"},
 "univ":{"n":"Universidade","c":160,"r":{"wood":10,"goods":4},"h":16,"i":"🎓","t":"educacao","e":"++pesquisa"},
 "base":{"n":"Base militar","c":120,"r":{"iron":10},"h":10,"i":"🛡","e":"+25% defesa, treino mais rápido"},
 "lab":{"n":"Centro de pesquisa","c":220,"r":{"copper":8,"mach":2},"h":18,"i":"🔬","t":"ciencia","e":"+pesquisa, +1 vaga de pesquisa"},
 "city":{"n":"Cidade","c":250,"r":{"wood":20,"iron":10,"goods":10},"h":24,"i":"🏙","e":"+3 mi de capacidade populacional, +PIB"}},
"u":{"inf":{"n":"Infantaria","c":20,"r":{"arms":1},"m":10000,"a":1,"d":2,"h":2,"s":20,"k":"land","i":"🪖"},
 "art":{"n":"Artilharia","c":45,"r":{"arms":3},"m":3000,"a":3,"d":1.5,"h":4,"s":15,"k":"land","t":"artilharia","i":"💥"},
 "armor":{"n":"Blindados","c":80,"r":{"veh":1,"arms":1},"m":2000,"a":3.5,"d":3,"h":6,"s":40,"k":"land","t":"motorizacao","i":"🚙"},
 "tank":{"n":"Tanques","c":130,"r":{"veh":2,"arms":2},"m":1500,"a":6,"d":3.5,"h":8,"s":35,"k":"land","t":"tanques","i":"🛡"},
 "fighter":{"n":"Caças","c":100,"r":{"plane":1},"m":300,"a":3,"d":4,"h":8,"s":500,"k":"air","t":"aviacao","i":"✈"},
 "bomber":{"n":"Bombardeiros","c":160,"r":{"plane":2},"m":500,"a":7,"d":1,"h":10,"s":400,"k":"air","t":"bombardeiros","i":"🛩"},
 "heli":{"n":"Helicópteros","c":110,"r":{"plane":1},"m":200,"a":4,"d":2,"h":8,"s":200,"k":"air","t":"helicopteros","i":"🚁"},
 "ship":{"n":"Navios de guerra","c":170,"r":{"shipg":3,"arms":2},"m":800,"a":4,"d":5,"h":14,"s":30,"k":"sea","t":"naval","i":"🚢"},
 "sub":{"n":"Submarinos","c":150,"r":{"shipg":2,"arms":1},"m":300,"a":5,"d":2,"h":12,"s":25,"k":"sea","t":"submarinos","i":"🐟"},
 "nuke":{"n":"Arma nuclear","c":2000,"r":{"uranium":40,"rare":10},"m":50,"a":0,"d":0,"h":48,"s":800,"k":"strat","t":"nuclear","i":"☢"},
 "chem":{"n":"Arma química","c":600,"r":{"oil":20,"copper":10},"m":50,"a":0,"d":0,"h":24,"s":400,"k":"strat","t":"quimicas","i":"☣"}},
"t":{"ind1":{"n":"Industrialização básica","c":"Industrial","cost":100,"h":4,"fx":{"inc":0.05}},
 "metal":{"n":"Metalurgia avançada","c":"Industrial","cost":200,"h":8,"req":["ind1"],"fx":{"prod":0.1}},
 "mecanica":{"n":"Engenharia mecânica","c":"Industrial","cost":300,"h":10,"req":["metal"],"fx":{"prod":0.1}},
 "eletricidade":{"n":"Eletrificação","c":"Industrial","cost":200,"h":8,"req":["ind1"],"fx":{"inc":0.03}},
 "automacao":{"n":"Automação industrial","c":"Industrial","cost":700,"h":20,"req":["mecanica","computadores"],"fx":{"inc":0.12,"prod":0.15}},
 "bancos":{"n":"Sistema bancário","c":"Econômica","cost":150,"h":6,"fx":{"inc":0.08}},
 "comercio":{"n":"Comércio internacional","c":"Econômica","cost":250,"h":8,"req":["bancos"],"fx":{"inc":0.07}},
 "ferrovias":{"n":"Ferrovias","c":"Econômica","cost":200,"h":8,"req":["ind1"],"fx":{"build":0.05}},
 "planejamento":{"n":"Planejamento econômico","c":"Econômica","cost":400,"h":12,"req":["comercio"],"fx":{"inc":0.08,"stab":3}},
 "agri1":{"n":"Agricultura mecanizada","c":"Agrícola","cost":120,"h":5,"fx":{"food":0.25}},
 "fertil":{"n":"Fertilizantes","c":"Agrícola","cost":250,"h":8,"req":["agri1"],"fx":{"food":0.3,"growth":0.1}},
 "irrigacao":{"n":"Irrigação moderna","c":"Agrícola","cost":350,"h":10,"req":["fertil"],"fx":{"food":0.3,"happy":2}},
 "med1":{"n":"Medicina moderna","c":"Médica","cost":150,"h":6,"fx":{"growth":0.2,"happy":3}},
 "antib":{"n":"Antibióticos","c":"Médica","cost":300,"h":10,"req":["med1"],"fx":{"growth":0.2,"happy":4}},
 "educacao":{"n":"Educação pública","c":"Ciência","cost":150,"h":6,"fx":{"res":0.1}},
 "ciencia":{"n":"Método científico","c":"Ciência","cost":300,"h":10,"req":["educacao"],"fx":{"res":0.15}},
 "fuzis":{"n":"Fuzis modernos","c":"Militar","cost":100,"h":4,"fx":{"atk":0.05}},
 "metralhadoras":{"n":"Metralhadoras","c":"Militar","cost":180,"h":6,"req":["fuzis"],"fx":{"def":0.08}},
 "artilharia":{"n":"Artilharia","c":"Militar","cost":200,"h":6,"req":["fuzis"]},
 "antitanque":{"n":"Armas antitanque","c":"Militar","cost":300,"h":8,"req":["artilharia"],"fx":{"def":0.1}},
 "defesas":{"n":"Sistemas de defesa","c":"Militar","cost":350,"h":10,"req":["metralhadoras"],"fx":{"def":0.1}},
 "motorizacao":{"n":"Veículos blindados","c":"Militar","cost":300,"h":10,"req":["mecanica"]},
 "tanques":{"n":"Tanques","c":"Militar","cost":450,"h":14,"req":["motorizacao"]},
 "tanques2":{"n":"Tanques avançados","c":"Militar","cost":800,"h":24,"req":["tanques"],"fx":{"atk_land":0.1}},
 "aviacao":{"n":"Aviação militar","c":"Aeronáutica","cost":350,"h":12,"req":["mecanica"]},
 "bombardeiros":{"n":"Bombardeiros","c":"Aeronáutica","cost":500,"h":16,"req":["aviacao"]},
 "helicopteros":{"n":"Helicópteros","c":"Aeronáutica","cost":450,"h":14,"req":["aviacao"]},
 "jatos":{"n":"Motores a jato","c":"Aeronáutica","cost":800,"h":24,"req":["aviacao","metal"],"fx":{"atk_air":0.15,"def_air":0.1}},
 "naval":{"n":"Construção naval","c":"Naval","cost":300,"h":10,"req":["metal"]},
 "submarinos":{"n":"Submarinos","c":"Naval","cost":400,"h":12,"req":["naval"]},
 "cruzadores":{"n":"Cruzadores e encouraçados","c":"Naval","cost":600,"h":18,"req":["naval"],"fx":{"atk_sea":0.15}},
 "portaavioes":{"n":"Porta-aviões","c":"Naval","cost":900,"h":24,"req":["cruzadores","aviacao"],"fx":{"atk_sea":0.1,"atk_air":0.05}},
 "eletronica":{"n":"Eletrônica","c":"Eletrônica","cost":300,"h":10,"req":["eletricidade"],"fx":{"res":0.05}},
 "radar":{"n":"Radar","c":"Eletrônica","cost":400,"h":12,"req":["eletronica"],"fx":{"def_air":0.1,"def":0.03}},
 "comunicacoes":{"n":"Telecomunicações","c":"Eletrônica","cost":350,"h":12,"req":["eletronica"],"fx":{"spy":0.08}},
 "computadores":{"n":"Computadores","c":"Eletrônica","cost":700,"h":20,"req":["comunicacoes"],"fx":{"res":0.2}},
 "satelites":{"n":"Satélites","c":"Eletrônica","cost":1000,"h":30,"req":["foguetes","computadores"],"fx":{"spy":0.15,"def":0.05}},
 "foguetes":{"n":"Foguetes","c":"Estratégica","cost":600,"h":18,"req":["metal","eletronica"]},
 "misseis":{"n":"Mísseis","c":"Estratégica","cost":800,"h":24,"req":["foguetes"],"fx":{"atk":0.08}},
 "antimissil":{"n":"Defesa antimíssil","c":"Estratégica","cost":1000,"h":30,"req":["misseis","radar"],"fx":{"def":0.12}},
 "fissao":{"n":"Física nuclear","c":"Estratégica","cost":800,"h":24,"req":["ciencia"],"fx":{"res":0.05}},
 "nuclear":{"n":"Programa nuclear (ADM)","c":"Estratégica","cost":2500,"h":72,"req":["fissao","foguetes"],"wmd":true},
 "quimicas":{"n":"Armas químicas (ADM)","c":"Estratégica","cost":1200,"h":36,"req":["ciencia","fertil"],"wmd":true},
 "biologicas":{"n":"Armas biológicas (ADM)","c":"Estratégica","cost":1500,"h":48,"req":["antib","ciencia"],"wmd":true},
 "d_blitz":{"n":"Doutrina: Blitzkrieg","c":"Doutrinas","cost":300,"h":10,"req":["motorizacao"]},
 "d_def":{"n":"Doutrina: Guerra defensiva","c":"Doutrinas","cost":200,"h":8,"req":["metralhadoras"]},
 "d_desg":{"n":"Doutrina: Guerra de desgaste","c":"Doutrinas","cost":200,"h":8,"req":["artilharia"]},
 "d_mass":{"n":"Doutrina: Superioridade numérica","c":"Doutrinas","cost":150,"h":6,"req":["fuzis"]},
 "d_prof":{"n":"Doutrina: Defesa em profundidade","c":"Doutrinas","cost":350,"h":12,"req":["d_def"]},
 "d_mob":{"n":"Doutrina: Mobilidade e velocidade","c":"Doutrinas","cost":350,"h":12,"req":["d_blitz"]},
 "d_sup":{"n":"Doutrina: Superioridade aérea","c":"Doutrinas","cost":300,"h":10,"req":["aviacao"]},
 "d_cas":{"n":"Doutrina: Apoio aéreo às tropas","c":"Doutrinas","cost":300,"h":10,"req":["aviacao"]},
 "d_bomb":{"n":"Doutrina: Bombardeio estratégico","c":"Doutrinas","cost":400,"h":12,"req":["bombardeiros"]},
 "d_mar":{"n":"Doutrina: Controle marítimo","c":"Doutrinas","cost":300,"h":10,"req":["naval"]},
 "d_subw":{"n":"Doutrina: Guerra submarina","c":"Doutrinas","cost":300,"h":10,"req":["submarinos"]},
 "d_comb":{"n":"Doutrina: Proteção de comboios","c":"Doutrinas","cost":250,"h":8,"req":["naval"]},
 "d_dis":{"n":"Doutrina: Dissuasão","c":"Doutrinas","cost":500,"h":16,"req":["misseis"]},
 "d_tot":{"n":"Doutrina: Mobilização total","c":"Doutrinas","cost":300,"h":10,"req":["d_mass"]},
 "d_irr":{"n":"Doutrina: Guerra irregular","c":"Doutrinas","cost":200,"h":8,"req":["fuzis"]},
 "d_conj":{"n":"Doutrina: Guerra conjunta","c":"Doutrinas","cost":600,"h":18,"req":["d_sup","d_mar"]}},
"d":{"blitz":{"n":"Blitzkrieg","k":"land","t":"d_blitz","fx":{"atk_land":0.2,"def_land":-0.05}},
 "defensiva":{"n":"Guerra defensiva","k":"land","t":"d_def","fx":{"def_land":0.2}},
 "desgaste":{"n":"Guerra de desgaste","k":"land","t":"d_desg","fx":{"atk_land":0.08,"def_land":0.08}},
 "massa":{"n":"Superioridade numérica","k":"land","t":"d_mass","fx":{"def_land":0.1,"atk_land":0.05}},
 "profundidade":{"n":"Defesa em profundidade","k":"land","t":"d_prof","fx":{"def_land":0.3,"atk_land":-0.05}},
 "mobilidade":{"n":"Mobilidade e velocidade","k":"land","t":"d_mob","fx":{"atk_land":0.25}},
 "superioridade":{"n":"Superioridade aérea","k":"air","t":"d_sup","fx":{"atk_air":0.15,"def_air":0.2}},
 "apoio":{"n":"Apoio aéreo às tropas","k":"air","t":"d_cas","fx":{"atk_air":0.1,"atk_land":0.05}},
 "bombardeio":{"n":"Bombardeio estratégico","k":"air","t":"d_bomb","fx":{"atk_air":0.25}},
 "controle":{"n":"Controle marítimo","k":"sea","t":"d_mar","fx":{"atk_sea":0.15,"def_sea":0.1}},
 "submarina":{"n":"Guerra submarina","k":"sea","t":"d_subw","fx":{"atk_sea":0.25}},
 "comboios":{"n":"Proteção de comboios","k":"sea","t":"d_comb","fx":{"def_sea":0.25,"inc":0.02}},
 "dissuasao":{"n":"Dissuasão","k":"strat","t":"d_dis","fx":{"def":0.1,"stab":3}},
 "mobilizacao":{"n":"Mobilização total","k":"strat","t":"d_tot","fx":{"atk":0.05,"def":0.05,"happy":-4}},
 "irregular":{"n":"Guerra irregular","k":"strat","t":"d_irr","fx":{"def":0.08}},
 "conjunta":{"n":"Guerra conjunta","k":"strat","t":"d_conj","fx":{"atk":0.1}}},
"ideo":{"Capitalismo":{"inc":0.1,"happy":-1},"Comunismo":{"prod":0.12,"inc":-0.05,"stab":4},"Fascismo":{"atk":0.1,"stab":5,"happy":-5},"Nazismo":{"atk":0.12,"stab":6,"happy":-8},
 "Democracia":{"happy":6,"res":0.05,"stab":-2},"Socialismo":{"happy":4,"res":0.05,"inc":-0.03},"Liberalismo":{"inc":0.08,"happy":2},"Nacionalismo":{"def":0.1,"stab":3}},
"gov":{"República":{"t":"Presidente","fx":{"happy":3}},"Monarquia":{"t":"Rei","fx":{"stab":6}},"Império":{"t":"Imperador","fx":{"atk":0.05,"stab":3}},"Ditadura":{"t":"Ditador","fx":{"stab":10,"happy":-6}},
 "República socialista":{"t":"Secretário-geral","fx":{"prod":0.06}},"Federação":{"t":"Presidente federal","fx":{"inc":0.05}},"Governo militar":{"t":"Chefe da junta","fx":{"atk":0.1,"happy":-8,"stab":4}}},
"min":{"defesa":{"n":"Ministro da Defesa","k":"def"},"economia":{"n":"Ministro da Economia","k":"inc"},"exterior":{"n":"Ministro das Relações Exteriores","k":"dip"},"infra":{"n":"Ministro da Infraestrutura","k":"build"},
 "educacao":{"n":"Ministro da Educação","k":"res"},"industria":{"n":"Ministro da Indústria","k":"prod"},"inteligencia":{"n":"Ministro da Inteligência","k":"spy"}},
"tr":{"nao_agressao":"Pacto de não agressão","defesa":"Defesa mútua","comercio":"Tratado de comércio","livre_comercio":"Livre comércio","pesquisa":"Acordo de pesquisa","militar":"Cooperação militar",
 "passagem":"Passagem militar","portos":"Acesso a portos","proibicao_adm":"Proibição de armas de destruição em massa"},
"trfx":{"comercio":{"inc":0.03},"livre_comercio":{"inc":0.05},"pesquisa":{"res":0.08},"militar":{"atk":0.04,"def":0.04},"portos":{"inc":0.02},"sancao":{"inc":-0.03}},
"org":{"alianca":"Aliança militar","comercial":"Organização comercial","economica":"União econômica","diplomatica":"Organização diplomática","federacao":"Federação de países","coalizao":"Coalizão de guerra"},
"orgfx":{"comercial":{"inc":0.04},"economica":{"inc":0.06},"alianca":{"def":0.05},"federacao":{"inc":0.03,"def":0.03},"diplomatica":{"dip":0.1},"coalizao":{"atk":0.05}},
"ops":{"info":{"n":"Coleta de informações","c":40,"h":6,"df":0,"lv":1},"desinfo":{"n":"Desinformação","c":80,"h":10,"df":0.05,"lv":1},"investigar":{"n":"Contraespionagem: investigar país","c":60,"h":8,"df":0,"lv":1},
 "sabotagem":{"n":"Sabotagem de instalação","c":120,"h":12,"df":0.1,"lv":2},"infiltracao":{"n":"Infiltração política","c":120,"h":16,"df":0.1,"lv":2},
 "industrial":{"n":"Espionagem industrial","c":150,"h":18,"df":0.15,"lv":3},"milicia":{"n":"Financiar milícias/rebeldes","c":200,"h":24,"df":0.15,"lv":3}},
"st":{"padrao":{"n":"Ataque frontal"},"blitz":{"n":"Blitzkrieg"},"cerco":{"n":"Cerco"},"desgaste":{"n":"Guerra de desgaste"},"surpresa":{"n":"Ataque surpresa"},"anfibio":{"n":"Desembarque anfíbio"},
 "bombardeio":{"n":"Bombardeio estratégico"},"nuclear":{"n":"Ataque nuclear"},"quimico":{"n":"Ataque químico"}},
"ter":{"Planície":1,"Floresta":1.15,"Montanha":1.4,"Deserto":1.05,"Pântano":1.2},
"grp":{"agr":"Agricultores","ope":"Operários","eng":"Engenheiros","cie":"Cientistas","com":"Comerciantes","ser":"Servidores públicos","sol":"Soldados","des":"Desempregados","dep":"Crianças e idosos"}
}$$::jsonb $j$;

-- ---------------------------------------------------------------------
-- AUXILIARES (internas, sem acesso direto pelo navegador)
-- ---------------------------------------------------------------------
create or replace function _v(j jsonb, k text) returns numeric language sql immutable as $$ select coalesce((j->>k)::numeric,0) $$;
create or replace function _add(s jsonb, a jsonb, f numeric default 1, lo numeric default null) returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(k, round(greatest(coalesce((s->>k)::numeric,0)+coalesce((a->>k)::numeric,0)*f, lo),3)),'{}'::jsonb)
  from jsonb_object_keys(coalesce(s,'{}'::jsonb)||coalesce(a,'{}'::jsonb)) k $$;
create or replace function _has(cid uuid, tk text) returns bool language sql stable as $$ select exists(select 1 from research where country_id=cid and tech=tk and done_at<=now()) $$;
create or replace function _nb(cid uuid, k text) returns int language sql stable as $$
  select count(*)::int from buildings b join territories t on t.id=b.territory_id where t.country_id=cid and b.kind=k and b.done_at<=now() $$;
create or replace function _nbt(tid uuid, k text) returns int language sql stable as $$ select count(*)::int from buildings where territory_id=tid and kind=k and done_at<=now() $$;
create or replace function _war(x uuid, y uuid) returns bool language sql stable as $$
  select exists(select 1 from wars where ended_at is null and ((attacker=x and defender=y) or (attacker=y and defender=x))) $$;
create or replace function _treaty(x uuid, y uuid, k text) returns bool language sql stable as $$
  select exists(select 1 from treaties where kind=k and ((a=x and b=y) or (a=y and b=x))) $$;
create or replace function _allied(x uuid, y uuid) returns bool language sql stable as $$
  select _treaty(x,y,'defesa') or exists(select 1 from org_members m1 join org_members m2 on m1.org_id=m2.org_id join orgs o on o.id=m1.org_id
    where m1.country_id=x and m2.country_id=y and o.kind in ('alianca','federacao','coalizao')) $$;
create or replace function _ev(m uuid, t text, o uuid default null, k text default 'info') returns void language sql as $$
  insert into events(match_id,kind,txt,only_for) values(m,k,t,o) $$;
create or replace function _done(m uuid, fn text, a jsonb default '{}') returns void language sql as $$
  insert into logs(user_id,fn,args) values(auth.uid(),fn,a); update matches set ver=ver+1 where id=m; $$;
create or replace function _name() returns text language sql volatile as $$
  select (array['Gen.','Cel.','Dr.','Sr.','Marechal'])[1+floor(random()*5)::int]||' '||(array['Alves','Volkov','Brandt','Moreau','Tanaka','Silva','Kovac','Ortega','Lindqvist','Rahman'])[1+floor(random()*10)::int] $$;
create or replace function _terrain() returns text language sql volatile as $$ select (array['Planície','Floresta','Montanha','Deserto','Pântano'])[1+floor(random()*5)::int] $$;
create or replace function _rres() returns jsonb language sql volatile as $$
  select jsonb_object_agg(k, case when k='food' then round((2+random()*4)::numeric,1) when random()<0.5 then round((0.5+random()*4.5)::numeric,1) else 0 end)
  from jsonb_object_keys(defs()->'res') k where not (defs()->'res'->k ? 'g') $$;

-- cobra dinheiro/recursos de um país (falha se faltar)
create or replace function _pay(cid uuid, m numeric, r jsonb) returns void language plpgsql set search_path=public,extensions as $$
declare cc countries; k text; v numeric;
begin
  select * into cc from countries where id=cid for update;
  if m<0 then raise exception 'Valor inválido'; end if;
  if cc.treasury < m then raise exception 'Dinheiro insuficiente (precisa de %, tem %)', round(m), round(cc.treasury); end if;
  for k,v in select key, value::numeric from jsonb_each_text(coalesce(r,'{}')) loop
    if v<0 then raise exception 'Valor inválido'; end if;
    if _v(cc.stock,k) < v then raise exception 'Falta %: precisa de %, tem %', coalesce(defs()->'res'->k->>'n',k), v, round(_v(cc.stock,k),1); end if;
    cc.stock := jsonb_set(cc.stock, array[k], to_jsonb(_v(cc.stock,k)-v));
  end loop;
  update countries set treasury=treasury-m, stock=cc.stock where id=cid;
end $$;

-- soma de todos os bônus: tecnologias, ideologia, governo, ministros, doutrinas, tratados e organizações
create or replace function fx(cid uuid) returns jsonb language plpgsql stable set search_path=public,extensions as $$
declare cc countries; d jsonb := defs(); r jsonb := '{}'; x jsonb;
begin
  select * into cc from countries where id=cid;
  if not found then return r; end if;
  for x in select d->'t'->q.tech->'fx' from research q where q.country_id=cid and q.done_at<=now() loop r := _add(r,x); end loop;
  r := _add(r, d->'ideo'->cc.ideology); r := _add(r, d->'gov'->cc.government->'fx');
  for x in select value from jsonb_each(coalesce(cc.ministers,'{}')) loop r := _add(r, jsonb_build_object(x->>'k', x->'b')); end loop;
  for x in select d->'d'->(value#>>'{}')->'fx' from jsonb_each(coalesce(cc.doctrines,'{}')) loop r := _add(r,x); end loop;
  for x in select d->'trfx'->q.kind from treaties q where cid in (q.a,q.b) loop r := _add(r,x); end loop;
  for x in select d->'orgfx'->o.kind from orgs o join org_members m on m.org_id=o.id where m.country_id=cid loop r := _add(r,x); end loop;
  return r;
end $$;

-- polígono desenhado → geometria validada
create or replace function _poly(j jsonb) returns geometry language plpgsql immutable set search_path=public,extensions as $$
declare pts geometry[]; g geometry;
begin
  if jsonb_typeof(j)<>'array' or jsonb_array_length(j)<3 or jsonb_array_length(j)>300 then raise exception 'Desenhe de 3 a 300 vértices'; end if;
  select array_agg(st_makepoint(least(180,greatest(-180,(v->>0)::float)), least(85,greatest(-85,(v->>1)::float))) order by i) into pts from jsonb_array_elements(j) with ordinality e(v,i);
  g := st_setsrid(st_makepolygon(st_makeline(pts || pts[1])),4326);
  if not st_isvalid(g) then raise exception 'Polígono inválido: as bordas não podem se cruzar'; end if;
  return g;
end $$;
create or replace function _free(m uuid, g geometry) returns void language plpgsql set search_path=public,extensions as $$
begin
  if exists(select 1 from territories t where t.match_id=m and st_intersects(t.geom,g) and st_relate(t.geom,g,'T********')) then
    raise exception 'O desenho invade um território já ocupado'; end if;
end $$;

-- jogador atual + limite de ações
create or replace function _me(p_match uuid, need_run bool default true) returns countries language plpgsql set search_path=public,extensions as $$
declare cc countries; n int;
begin
  if auth.uid() is null then raise exception 'Faça login'; end if;
  select count(*) into n from logs where user_id=auth.uid() and created_at>now()-interval '1 minute';
  if n>60 then raise exception 'Limite de ações por minuto atingido. Aguarde um pouco.'; end if;
  select * into cc from countries where match_id=p_match and owner=auth.uid() and alive for update;
  if not found then raise exception 'Você não tem um país ativo nesta partida'; end if;
  if need_run and (select status from matches where id=p_match)<>'running' then raise exception 'A partida ainda não começou'; end if;
  return cc;
end $$;

-- preço do mercado mundial: escassez, demanda (ordens e volume), guerras e choques de oferta
create or replace function npc_price(m uuid, it text) returns numeric language sql stable as $$
  with c as (select count(*) n, coalesce(sum((stock->>it)::numeric),0) s from countries where match_id=m and alive),
  o as (select coalesce(sum(case when side='buy' then qty else -qty end),0) net from orders where match_id=m and item=it and not black),
  tr as (select coalesce(sum(qty),0) q from trades where match_id=m and item=it and created_at>now()-interval '24 hours')
  select round((defs()->'res'->it->>'p')::numeric
    * greatest(0.35, 1.6 - 0.6*least(2, c.s/greatest(1,c.n*case when defs()->'res'->it ? 'g' then 30 else 100 end)))
    * (1 + 0.08*(select count(*) from wars w where w.match_id=m and w.ended_at is null and it in ('oil','iron','food','alu','coal','uranium','arms','veh','plane','shipg')))
    * (1 + least(0.5, greatest(-0.3, o.net/greatest(50, c.n*100))))
    * (1 + least(0.3, tr.q/greatest(200, c.n*400)))
    * coalesce((select (shocks->it->>'m')::numeric from matches where id=m and (shocks->it->>'until')::timestamptz>now()),1), 2)
  from c, o, tr $$;

-- recorta o desenho no espaço livre (encosta nos vizinhos sem invadir) e fica com a maior parte
create or replace function _fit(m uuid, g geometry) returns geometry language plpgsql set search_path=public,extensions as $$
declare o geometry;
begin
  select st_union(geom) into o from territories where match_id=m and st_intersects(geom, st_expand(g,1));
  if o is not null then g := st_difference(g, o); end if;
  select x.geom into g from st_dump(st_makevalid(g)) x where st_geometrytype(x.geom)='ST_Polygon' order by st_area(x.geom) desc limit 1;
  if g is null or st_isempty(g) then raise exception 'Não sobrou espaço livre nesse desenho'; end if;
  return st_setsrid(g,4326);
end $$;
-- =====================================================================
-- WORLD NATIONS — parte 2/3: motor do tempo (roda no servidor), contas, salas e estado
-- =====================================================================

-- resolve uma operação secreta
create or replace function _resolve_op(o ops) returns void language plpgsql set search_path=public,extensions as $$
declare d jsonb := defs(); me countries; tg countries; ps numeric; pd numeric; ok bool; v_txt text; v_tid uuid; v_tech text; v_bk text; n int; nm text := d->'ops'->o.kind->>'n';
begin
  select * into me from countries where id=o.country_id; select * into tg from countries where id=o.target;
  if not coalesce(me.alive,false) or not coalesce(tg.alive,false) then update ops set result='cancelada' where id=o.id; return; end if;
  ps := least(0.95,greatest(0.05, 0.55 + 0.12*(me.intel_level-tg.intel_level) + _v(fx(me.id),'spy') - _v(fx(tg.id),'spy')*0.5 - _v(d->'ops'->o.kind,'df')));
  ok := random()<ps;
  pd := least(0.9,greatest(0.05, 0.3 - 0.08*(me.intel_level-tg.intel_level) + case when ok then 0 else 0.25 end));
  if ok then
    case o.kind
    when 'info' then
      v_txt := format('🕵 Relatório sobre %s: tesouro %s, renda %s/h, estabilidade %s%%, %s unidades, %s tecnologias. Estoque: %s. (dados visíveis por 48h)', tg.name, round(tg.treasury), round(tg.income,1), round(tg.stability),
        (select count(*) from units where country_id=tg.id), (select count(*) from research where country_id=tg.id and done_at<=now()),
        coalesce((select string_agg(key||' '||round(value::numeric),', ') from jsonb_each_text(tg.stock)),'—'));
    when 'industrial' then
      select q.tech into v_tech from research q where q.country_id=tg.id and q.done_at<=now() and not exists(select 1 from research x where x.country_id=me.id and x.tech=q.tech) order by random() limit 1;
      if v_tech is null then v_txt := format('🕵 Espionagem industrial em %s: nenhum projeto útil encontrado.', tg.name);
      else insert into research(country_id,tech,match_id,done_at,notified) values(me.id,v_tech,o.match_id,now(),true);
        v_txt := format('🕵 Projetos de "%s" roubados de %s!', d->'t'->v_tech->>'n', tg.name); end if;
    when 'sabotagem' then
      delete from buildings where id=(select b.id from buildings b join territories t on t.id=b.territory_id where t.country_id=tg.id and b.done_at<=now() order by random() limit 1) returning kind into v_bk;
      v_txt := format('💥 Sabotagem em %s: %s destruída.', tg.name, coalesce(d->'b'->v_bk->>'n','nada'));
      perform _ev(o.match_id, format('💥 Explosão destrói %s em nosso território. Origem desconhecida.', coalesce(d->'b'->v_bk->>'n','uma instalação')), tg.id,'alerta');
    when 'infiltracao' then
      update countries set stability=greatest(0,stability-10), happiness=greatest(0,happiness-4) where id=tg.id;
      v_txt := format('🕵 Agentes infiltrados desestabilizam o governo de %s.', tg.name);
      perform _ev(o.match_id, '📰 Uma crise política misteriosa abala nosso governo.', tg.id,'alerta');
    when 'milicia' then
      select t.id into v_tid from territories t where t.country_id=tg.id and not st_contains(t.geom,tg.capital) order by random() limit 1;
      if v_tid is null then select t.id into v_tid from territories t where t.country_id=tg.id limit 1; end if;
      update territories set rebels=rebels+3+random()*4 where id=v_tid;
      update units set strength=strength*0.8 where territory_id=v_tid and country_id=tg.id;
      update countries set stability=greatest(0,stability-6) where id=tg.id;
      v_txt := format('🕵 Milícias financiadas por nós atacam %s em %s.', (select name from territories where id=v_tid), tg.name);
      perform _ev(o.match_id, format('🔥 Milícias armadas surgem em %s. Suspeita de financiamento estrangeiro.', (select name from territories where id=v_tid)), tg.id,'alerta');
    when 'desinfo' then
      update countries set infamy=infamy+10 where id=tg.id;
      v_txt := format('🕵 Campanha de desinformação contra %s foi um sucesso.', tg.name);
      perform _ev(o.match_id, format('📰 Escândalo internacional envolvendo %s (fontes duvidosas).', tg.name));
    when 'investigar' then
      update ops x set discovered=true where x.country_id=tg.id and x.target=me.id and not x.discovered and x.result is not null and x.created_at>now()-interval '10 days' and random()<0.6;
      get diagnostics n = row_count;
      if n>0 then
        v_txt := format('🔎 Investigação concluída: %s realizou %s operação(ões) secreta(s) contra nós!', tg.name, n);
        perform _ev(o.match_id, format('🔎 %s acusa %s de operações secretas em seu território, com provas.', me.name, tg.name),null,'alerta');
        update countries set infamy=infamy+5*n where id=tg.id;
      else v_txt := format('🔎 Investigação sobre %s: nenhuma prova encontrada.', tg.name); end if;
    else null;
    end case;
  else v_txt := format('🕵 A operação "%s" em %s fracassou.', nm, tg.name);
  end if;
  perform _ev(o.match_id, v_txt, me.id, 'intel');
  if o.kind<>'investigar' and random()<pd then
    update ops set discovered=true where id=o.id;
    update countries set infamy=infamy+5 where id=me.id;
    perform _ev(o.match_id, format('🚨 Agentes de %s foram capturados em %s (operação: %s)!', me.name, tg.name, nm),null,'alerta');
  end if;
  update ops set result=case when ok then 'sucesso' else 'fracasso' end where id=o.id;
end $$;

-- avança o mundo pelo tempo real decorrido (chamado por qualquer acesso e pelo pg_cron)
create or replace function _tick(p_match uuid) returns void language plpgsql set search_path=public,extensions as $$
declare mm matches; dt numeric; cc countries; oo ops; d jsonb := defs(); f jsonb; rr record; k text; v numeric; q numeric; mx numeric; inp text;
  v_nb jsonb; v_prod jsonb; v_gdp numeric; v_inc numeric; v_exp numeric; v_pop numeric; v_nterr int; unemp numeric; stt numeric; gr numeric; ev numeric;
  food_need numeric; oil_need numeric; goods_need numeric; famine bool; goods_ok bool; nw int; nf numeric; v_ind jsonb;
  lab numeric; rem numeric; edu numeric; soc numeric; edb numeric; base numeric; grp jsonb; ng jsonb; sat numeric; hap numeric; wk text; ws numeric;
  sol_n numeric; ntr int; norg int; nsan int; ndoc int; a_lo uuid; a_hi uuid; mvn numeric;
begin
  select * into mm from matches where id=p_match for update skip locked;
  if not found or mm.status<>'running' then return; end if;
  dt := extract(epoch from now()-mm.last_tick)/3600.0;
  if dt < 0.03 then return; end if;
  dt := least(dt, 72);

  for rr in update buildings b set notified=true where b.match_id=p_match and not b.notified and b.done_at<=now() returning b.country_id, b.kind, b.territory_id loop
    perform _ev(p_match, format('🏗 %s concluída em %s.', d->'b'->rr.kind->>'n', (select name from territories where id=rr.territory_id)), rr.country_id, 'obra');
  end loop;
  for rr in update research x set notified=true where x.match_id=p_match and not x.notified and x.done_at<=now() returning x.country_id, x.tech loop
    perform _ev(p_match, format('🔬 %s concluiu a pesquisa: %s.', (select name from countries where id=rr.country_id), d->'t'->rr.tech->>'n'), null, 'pesquisa');
  end loop;
  for rr in with up as (update units u set notified=true where u.match_id=p_match and not u.notified and u.ready_at<=now() returning u.country_id, u.kind)
            select country_id, kind, count(*) n from up group by 1,2 loop
    perform _ev(p_match, format('🎖 %s× %s prontas para o combate.', rr.n, d->'u'->rr.kind->>'n'), rr.country_id, 'militar');
  end loop;
  for oo in select * from ops where match_id=p_match and result is null and done_at<=now() loop perform _resolve_op(oo); end loop;

  -- contratos de fornecimento: entrega automática por hora
  for rr in select * from contracts where match_id=p_match and status in ('ativo','suspenso') loop
    if rr.ends_at<=now() then update contracts set status='concluído' where id=rr.id; continue; end if;
    q := rr.qty*dt;
    select least(q, _v(stock,rr.item)) into q from countries where id=rr.seller and alive;
    select least(q, greatest(0,treasury)/greatest(rr.price,0.01)) into q from countries where id=rr.buyer and alive;
    q := coalesce(q,0); if _war(rr.seller,rr.buyer) then q := 0; end if;
    if q>0 then
      update countries set stock=_add(stock,jsonb_build_object(rr.item,q),-1,0), treasury=treasury+q*rr.price where id=rr.seller;
      update countries set stock=_add(stock,jsonb_build_object(rr.item,q)), treasury=treasury-q*rr.price where id=rr.buyer;
      insert into trades(match_id,item,qty,price,seller,buyer) values(p_match,rr.item,round(q,2),rr.price,rr.seller,rr.buyer);
    end if;
    if q < rr.qty*dt*0.5 and rr.status='ativo' then
      perform _ev(p_match, format('📑 Contrato de %s suspenso: faltou mercadoria ou dinheiro.', d->'res'->rr.item->>'n'), rr.seller,'comercio');
      perform _ev(p_match, format('📑 Contrato de %s suspenso: faltou mercadoria ou dinheiro.', d->'res'->rr.item->>'n'), rr.buyer,'comercio');
    end if;
    update contracts set delivered=delivered+q, status=case when q >= rr.qty*dt*0.5 then 'ativo' else 'suspenso' end where id=rr.id;
  end loop;

  -- bots (países do computador) respondem propostas, constroem, pesquisam, recrutam e guerreiam
  for cc in select * from countries where match_id=p_match and alive and bot is not null loop
    begin perform _bot_act(p_match, cc, dt); exception when others then raise warning 'bot %: %', cc.name, sqlerrm; end;
  end loop;

  for cc in select * from countries where match_id=p_match and alive loop
    f := fx(cc.id); mvn := 0;
    select coalesce(jsonb_object_agg(x.kind,x.n),'{}') into v_nb from (select b.kind, count(*) n from buildings b join territories t on t.id=b.territory_id where t.country_id=cc.id and b.done_at<=now() group by b.kind) x;
    select count(*), coalesce(sum(t.pop),0) into v_nterr, v_pop from territories t where t.country_id=cc.id;
    if v_nterr=0 then update countries set alive=false where id=cc.id; continue; end if;
    select count(*) into nw from wars w where w.ended_at is null and cc.id in (w.attacker,w.defender);

    -- extração de recursos
    select coalesce(jsonb_object_agg(x.k,x.s),'{}') into v_prod from (
      select e.key k, sum(e.value::numeric * (1+0.5*(select count(*) from buildings b where b.territory_id=t.id and b.kind='mine' and b.done_at<=now()))
             * case when t.occupied is not null then 0.5 else 1 end * case when t.rebels>0 then 0.7 else 1 end) s
      from territories t, jsonb_each_text(t.res) e where t.country_id=cc.id group by e.key) x;
    v_prod := _add('{}', v_prod, 0.5*(1+_v(f,'prod')+0.08*least(5,_v(v_nb,'power'))));
    v_prod := _add(v_prod, jsonb_build_object('food', 3*_v(v_nb,'farm')*(1+_v(f,'food'))));

    -- indústria: fábricas transformam matéria-prima em produtos (divisão escolhida pelo jogador)
    nf := _v(v_nb,'factory') * (1+_v(f,'prod')+0.08*least(5,_v(v_nb,'power'))) * case when cc.focus='guerra' then 1.2 else 1 end;
    v_ind := case when coalesce(cc.industry,'{}')='{}' then '{"goods":0.4,"arms":0.4,"mach":0.2}'::jsonb else cc.industry end;
    for k, v in select key, value::numeric from jsonb_each_text(v_ind) loop
      continue when v<=0 or d->'res'->k->'rc' is null;
      mx := nf*v*dt;
      for inp, q in select key, value::numeric from jsonb_each_text(d->'res'->k->'rc') loop mx := least(mx, _v(cc.stock,inp)/q); end loop;
      if mx>0 then cc.stock := _add(cc.stock, d->'res'->k->'rc', -mx, 0); cc.stock := _add(cc.stock, jsonb_build_object(k,mx)); end if;
    end loop;

    -- consumo: comida, combustível, carvão das usinas, produtos industriais da população
    food_need := v_pop/1e6*0.15; goods_need := v_pop/1e6*0.04;
    select coalesce(sum(case when u.kind in ('armor','tank','fighter','bomber','heli','ship','sub') then 0.05 else 0 end),0) into oil_need from units u where u.country_id=cc.id;
    famine := _v(cc.stock,'food') + (_v(v_prod,'food')-food_need)*dt < 0;
    goods_ok := _v(cc.stock,'goods') >= goods_need*dt;
    cc.stock := _add(cc.stock, v_prod, dt, 0);
    cc.stock := _add(cc.stock, jsonb_build_object('food',food_need,'oil',oil_need,'coal',0.1*_v(v_nb,'power'),'goods',goods_need), -dt, 0);
    soc := least(2,greatest(0,_v(cc.budget,'social'))); edb := least(2,greatest(0,_v(cc.budget,'edu')));

    -- grupos sociais: cada grupo ocupa os empregos que existem (qualificados exigem educação)
    lab := v_pop*0.6; edu := lab*cc.education*0.35; rem := lab; ng := '{}';
    select coalesce(sum((d->'u'->u.kind->>'m')::numeric),0) into sol_n from units u where u.country_id=cc.id;
    select count(*) into ntr from treaties x where cc.id in (x.a,x.b) and x.kind in ('comercio','livre_comercio','portos');
    v := least(sol_n, rem); rem := rem-v; ng := ng || jsonb_build_object('sol',v);
    v := least(v_pop*0.01*cc.education + 60000*(_v(v_nb,'power')+_v(v_nb,'rail')+_v(v_nb,'port')+_v(v_nb,'airport')+_v(v_nb,'city')) + 20000*_v(v_nb,'road'), edu*0.6, rem); rem := rem-v; ng := ng || jsonb_build_object('eng',v);
    v := least(v_pop*0.002*cc.education + 20000*_v(v_nb,'school') + 60000*_v(v_nb,'univ') + 50000*_v(v_nb,'lab'), greatest(0, edu-_v(ng,'eng')), rem); rem := rem-v; ng := ng || jsonb_build_object('cie',v);
    v := least(v_pop*0.2 + 300000*_v(v_nb,'farm'), rem); rem := rem-v; ng := ng || jsonb_build_object('agr',v);
    v := least(v_pop*0.12 + 400000*_v(v_nb,'factory') + 200000*_v(v_nb,'mine') + 80000*_v(v_nb,'power'), rem); rem := rem-v; ng := ng || jsonb_build_object('ope',v);
    v := least(v_pop*0.07 + 60000*_v(v_nb,'hospital') + 40000*_v(v_nb,'school') + 10000*v_nterr, rem); rem := rem-v; ng := ng || jsonb_build_object('ser',v);
    v := least(v_pop*0.09 + 150000*_v(v_nb,'port') + 400000*_v(v_nb,'city') + 50000*ntr, rem); rem := rem-v; ng := ng || jsonb_build_object('com',v);
    ng := ng || jsonb_build_object('des', rem, 'dep', v_pop*0.4);
    unemp := rem/greatest(1,lab);

    select count(*) into norg from org_members where country_id=cc.id;
    select count(*) into nsan from treaties x where x.kind='sancao' and x.b=cc.id;
    select count(*) into ndoc from jsonb_object_keys(coalesce(cc.doctrines,'{}'));
    base := 50 - (cc.tax-0.2)*100 + _v(f,'happy') + 2*least(5,_v(v_nb,'hospital')) - case when famine then 25 else 0 end - 4*nw
          - case when cc.emergency then 8 else 0 end - case when cc.treasury<0 then 10 else 0 end + case when goods_ok then 5 else -6 end + soc*4;
    grp := coalesce(cc.groups,'{}'); hap := 0; wk := null; ws := 101;
    for k in select jsonb_object_keys(ng) loop
      sat := base + case k
        when 'agr' then 3*least(4,_v(v_nb,'farm')) + _v(f,'food')*10 - case when famine then 10 else 0 end
        when 'ope' then -unemp*40 + soc*3 - case when cc.focus='guerra' then 5 else 0 end + 2*least(3,_v(v_nb,'factory'))
        when 'eng' then 6 + edb*3 + 2*least(5,_v(v_nb,'univ'))
        when 'cie' then 4 + edb*6 + 3*least(4,_v(v_nb,'lab')) - case when cc.ideology in ('Fascismo','Nazismo') or cc.government in ('Ditadura','Governo militar') then 10 else 0 end
        when 'com' then 3*ntr + 2*norg - 8*nsan - 5*nw + case cc.border when 'aberta' then 5 when 'fechada' then -8 else 0 end
        when 'ser' then 5 - case when cc.treasury<0 then 15 else 0 end
        when 'sol' then case when cc.focus='guerra' then 6 else 0 end + 2*ndoc - greatest(0,cc.conscription-0.03)*150 + 3*nw - case when cc.treasury<0 then 15 else 0 end
        when 'des' then -25 + soc*12
        else 2*least(5,_v(v_nb,'hospital')) + soc*2 end;
      sat := least(100,greatest(0,sat));
      v := coalesce((grp->k->>'s')::numeric, 55); v := v + (sat-v)*least(1,0.15*dt);
      grp := jsonb_set(grp, array[k], jsonb_build_object('n', round(_v(ng,k)), 's', round(v,1)));
      hap := hap + v*_v(ng,k);
      if k<>'dep' and _v(ng,k) > v_pop*0.02 and v < ws then ws := v; wk := k; end if;
    end loop;
    cc.happiness := hap/greatest(1,v_pop);
    stt := 25 + cc.happiness*0.6 + _v(f,'stab') + case when cc.emergency then 15 else 0 end - case when cc.treasury<0 then 15 else 0 end - least(20,cc.infamy/10);
    cc.stability := cc.stability + (least(100,greatest(0,stt))-cc.stability)*least(1,0.06*dt);

    -- economia
    v_gdp := (v_pop/1e6*3 + 4*_v(v_nb,'factory') + 2*_v(v_nb,'power') + 0.6*_v(v_nb,'road') + 1.2*_v(v_nb,'rail') + 2*_v(v_nb,'port') + 1.5*_v(v_nb,'airport') + 3*_v(v_nb,'city') + 0.5*_v(v_nb,'mine'))
          * greatest(0.2, 1 + _v(f,'inc')) * (1 - 0.5*unemp) * case when cc.focus='guerra' then 0.9 else 1 end * case when goods_ok then 1 else 0.95 end;
    v_inc := v_gdp*cc.tax;
    select coalesce(sum((d->'u'->u.kind->>'c')::numeric*0.01),0) into v_exp from units u where u.country_id=cc.id;
    v_exp := v_exp + 0.05*(select count(*) from buildings b join territories t on t.id=b.territory_id where t.country_id=cc.id) + 0.4*cc.intel_level
           + case when cc.emergency then 1 else 0 end + case when cc.treasury<0 then -cc.treasury*0.002 else 0 end + v_pop/1e6*0.12*(soc+edb);
    cc.treasury := cc.treasury + (v_inc-v_exp)*dt;

    -- crescimento e migração interna (das regiões ruins para as cidades com emprego)
    gr := 0.00003*(1+_v(f,'growth')+0.05*least(5,_v(v_nb,'hospital')))*(cc.happiness/60) + (cc.happiness-50)*0.000001 - case when famine then 0.0004 else 0 end;
    update territories t set pop = round(least(greatest(t.pop, t.area*250 + 1e6 + 3e6*(select count(*) from buildings b where b.territory_id=t.id and b.kind='city' and b.done_at<=now())), t.pop*exp(gr*dt)))
      where t.country_id=cc.id;
    if v_nterr>1 then
      select t.id into a_hi from territories t where t.country_id=cc.id order by (select 3*count(*) filter (where b.kind='city') + 2*count(*) filter (where b.kind='factory') + count(*) filter (where b.kind in ('hospital','school','port'))
        from buildings b where b.territory_id=t.id and b.done_at<=now()) + case when st_contains(t.geom,cc.capital) then 3 else 0 end - 2*t.rebels - case when t.occupied is not null then 5 else 0 end desc limit 1;
      select t.id into a_lo from territories t where t.country_id=cc.id order by (select 3*count(*) filter (where b.kind='city') + 2*count(*) filter (where b.kind='factory') + count(*) filter (where b.kind in ('hospital','school','port'))
        from buildings b where b.territory_id=t.id and b.done_at<=now()) + case when st_contains(t.geom,cc.capital) then 3 else 0 end - 2*t.rebels - case when t.occupied is not null then 5 else 0 end asc limit 1;
      if a_lo<>a_hi then
        select pop*0.0004*dt into mvn from territories where id=a_lo;
        update territories set pop=pop-round(mvn) where id=a_lo; update territories set pop=pop+round(mvn) where id=a_hi;
      end if;
    end if;
    select coalesce(sum(pop),0) into v_pop from territories where country_id=cc.id;
    update countries set treasury=round(cc.treasury,2), stock=cc.stock, happiness=round(cc.happiness,2), stability=round(cc.stability,2), pop=v_pop, unemployment=round(unemp,3), groups=grp,
      education=round(least(0.95, 0.15 + (0.4*_v(v_nb,'school')+1.2*_v(v_nb,'univ')+0.8*_v(v_nb,'lab'))/greatest(1,v_pop/2e6)*0.5 + _v(f,'res')*0.3 + edb*0.06),3),
      gdp=round(v_gdp,2), income=round(v_inc,2), expenses=round(v_exp,2), infamy=round(greatest(0, cc.infamy - dt*0.05*(1+_v(f,'dip')*5)),2),
      mig=jsonb_build_object('in',0,'out',0,'int',round(mvn/dt),'from','{}'::jsonb)
      where id=cc.id;

    -- revolta de grupos sociais insatisfeitos
    if wk is not null and ws < 25 and random() < least(0.6, 0.06*dt) then
      case wk
        when 'ope' then update countries set treasury=treasury-greatest(0,v_inc*5) where id=cc.id;
          perform _ev(p_match, format('✊ Greve geral dos operários em %s (satisfação %s%%).', cc.name, round(ws)),null,'interno');
        when 'agr' then update countries set stock=jsonb_set(stock,'{food}',to_jsonb(round(_v(stock,'food')*0.7,1))) where id=cc.id;
          perform _ev(p_match, format('🚜 Agricultores bloqueiam estradas em %s e retêm a safra.', cc.name),null,'interno');
        when 'sol' then
          if ws<15 and cc.stability<45 then
            update countries set leader=_name(), party='Junta militar', government='Governo militar', leader_since=now(), stability=stability+15 where id=cc.id;
            perform _ev(p_match, format('🎖 GOLPE DE ESTADO em %s! Soldados insatisfeitos derrubam o governo.', cc.name),null,'alerta');
          else update units set strength=strength*0.9 where country_id=cc.id;
            perform _ev(p_match, format('🪖 Motim nos quartéis de %s.', cc.name),null,'interno'); end if;
        when 'cie', 'eng' then update countries set education=greatest(0.05,education-0.02) where id=cc.id;
          update territories set pop=pop-30000 where id=(select id from territories where country_id=cc.id order by pop desc limit 1);
          perform _ev(p_match, format('🎓 Fuga de cérebros: cientistas e engenheiros deixam %s.', cc.name),null,'interno');
        when 'com' then update countries set treasury=treasury-greatest(0,treasury*0.08) where id=cc.id;
          perform _ev(p_match, format('💸 Fuga de capitais em %s: comerciantes tiram dinheiro do país.', cc.name),null,'interno');
        when 'des' then delete from buildings where id=(select b.id from buildings b join territories t on t.id=b.territory_id where t.country_id=cc.id and b.done_at<=now() order by random() limit 1);
          perform _ev(p_match, format('🔥 Desempregados saqueiam e incendeiam prédios em %s.', cc.name),null,'interno');
        else update countries set stability=greatest(0,stability-5) where id=cc.id;
          perform _ev(p_match, format('🏛 Servidores públicos paralisam o Estado em %s.', cc.name),null,'interno');
      end case;
    end if;
    -- rebeldes / resistência nas regiões
    update territories t set rebels = greatest(0, t.rebels + dt*(case when cc.stability<40 or t.occupied is not null then 0.08 else -0.15 end)
        - dt*0.1*coalesce((select sum((d->'u'->u.kind->>'d')::numeric*u.strength) from units u where u.territory_id=t.id and u.country_id=cc.id),0))
      where t.country_id=cc.id and (t.rebels>0 or t.occupied is not null or cc.stability<40);
    for rr in update territories t set country_id=null, occupied=null, name=left('Rebeldes de '||t.name,40)
        where t.country_id=cc.id and t.rebels>=8 and not st_contains(t.geom,cc.capital) and not exists(select 1 from units u where u.territory_id=t.id and u.country_id=cc.id) returning t.name loop
      perform _ev(p_match, format('🏴 %s se rebelou contra %s e declarou independência.', rr.name, cc.name),null,'interno');
    end loop;
    -- instabilidade grave: revolta armada, golpe, guerra civil
    if cc.stability < 30 and random() < least(0.9,(30-cc.stability)/30*0.1*dt) then
      if cc.stability >= 15 then
        delete from buildings where id=(select b.id from buildings b join territories t on t.id=b.territory_id where t.country_id=cc.id and b.done_at<=now() order by random() limit 1);
        update territories set rebels=rebels+2+random()*3 where id=(select t.id from territories t where t.country_id=cc.id order by random() limit 1);
        perform _ev(p_match, format('🔥 Revolta regional em %s! Rebeldes armados atacam instalações.', cc.name),null,'interno');
      elsif cc.stability >= 6 or v_nterr < 3 then
        update countries set leader=_name(), party='Junta militar', government='Governo militar', leader_since=now(), stability=stability+20 where id=cc.id;
        perform _ev(p_match, format('🎖 GOLPE DE ESTADO em %s! Militares tomam o poder.', cc.name),null,'alerta');
      else
        update territories set country_id=null, occupied=null, rebels=4+random()*6, name=left('Rebeldes de '||name,40)
          where id in (select t.id from territories t where t.country_id=cc.id and not st_contains(t.geom,cc.capital) order by random() limit greatest(1,(v_nterr-1)/2));
        delete from units u using territories t where u.territory_id=t.id and t.country_id is null and u.country_id=cc.id;
        perform _ev(p_match, format('🏴 GUERRA CIVIL em %s! Regiões rebeldes declaram independência.', cc.name),null,'alerta');
      end if;
    end if;
    -- eventos aleatórios
    if random() < least(0.5, 0.01*dt) then
      ev := random();
      if ev<0.15 then
        update territories set res=jsonb_set(res,'{oil}',to_jsonb(_v(res,'oil')+2)) where id=(select t.id from territories t where t.country_id=cc.id order by random() limit 1);
        perform _ev(p_match, format('🛢 Descoberta de petróleo em %s!', cc.name),null,'evento');
      elsif ev<0.25 then
        update territories set res=jsonb_set(res,'{uranium}',to_jsonb(_v(res,'uranium')+2)) where id=(select t.id from territories t where t.country_id=cc.id order by random() limit 1);
        perform _ev(p_match, '☢ (SECRETO) Geólogos encontraram uma nova jazida de urânio em nosso território.', cc.id,'evento');
      elsif ev<0.40 then
        update countries set treasury=treasury-greatest(0,treasury*0.15), stability=greatest(0,stability-5) where id=cc.id;
        perform _ev(p_match, format('📉 Crise econômica atinge %s.', cc.name),null,'evento');
      elsif ev<0.50 then
        update territories set pop=round(pop*case when _has(cc.id,'med1') then 0.99 else 0.97 end) where country_id=cc.id;
        update countries set happiness=greatest(0,happiness-5) where id=cc.id;
        perform _ev(p_match, format('🦠 Epidemia em %s.', cc.name),null,'evento');
      elsif ev<0.60 then
        update countries set stock=jsonb_set(stock,'{food}',to_jsonb(round(_v(stock,'food')*0.5,1))) where id=cc.id;
        perform _ev(p_match, format('🌾 Crise alimentar em %s: safras perdidas.', cc.name),null,'evento');
      elsif ev<0.70 then
        update countries set stability=greatest(0,stability-8) where id=cc.id;
        perform _ev(p_match, format('📰 Escândalo político abala o governo de %s.', cc.name),null,'evento');
      elsif ev<0.80 then
        update research set done_at=now() where country_id=cc.id and tech=(select x.tech from research x where x.country_id=cc.id and x.done_at>now() order by x.done_at limit 1);
        perform _ev(p_match, format('💡 Descoberta científica em %s.', cc.name),null,'evento');
      elsif ev<0.90 then
        delete from buildings where id=(select b.id from buildings b join territories t on t.id=b.territory_id where t.country_id=cc.id order by random() limit 1);
        update territories set pop=round(pop*0.99) where country_id=cc.id;
        perform _ev(p_match, format('🌋 Desastre natural atinge %s.', cc.name),null,'evento');
      else
        update countries set treasury=treasury+v_gdp*8 where id=cc.id;
        perform _ev(p_match, format('📈 Boom econômico em %s!', cc.name),null,'evento');
      end if;
    end if;
    if not exists(select 1 from stats s where s.country_id=cc.id and s.t>now()-interval '55 minutes') then
      insert into stats(country_id,pop,treasury,gdp,mil,stab) values(cc.id, v_pop, round(cc.treasury,2), round(v_gdp,2),
        (select coalesce(sum(((d->'u'->u.kind->>'a')::numeric+(d->'u'->u.kind->>'d')::numeric)*u.strength),0) from units u where u.country_id=cc.id), round(cc.stability,2));
    end if;
  end loop;

  -- migração internacional: pessoas saem de países ruins (guerra, fome, miséria) para países melhores com fronteira aberta
  for rr in with a as (select c.id, c.name, c.pop, c.border,
        (select count(*) from wars w where w.ended_at is null and c.id in (w.attacker,w.defender)) nwar,
        c.happiness*0.6 + least(30, c.gdp/greatest(1,c.pop/1e6)*5) + c.stability*0.2
        - 15*(select count(*) from wars w where w.ended_at is null and c.id in (w.attacker,w.defender)) - case when _v(c.stock,'food')<1 then 20 else 0 end sc
      from countries c where c.match_id=p_match and c.alive)
    select o.id oid, o.name oname, o.pop opop, o.border ob, o.sc oat, o.nwar, x.id did, x.name dname,
      (x.sc-o.sc)*case x.border when 'aberta' then 1.5 else 0.6 end
        / nullif(sum((x.sc-o.sc)*case x.border when 'aberta' then 1.5 else 0.6 end) over (partition by o.id),0) share
    from a o join a x on x.id<>o.id and x.sc>o.sc+5 and x.border<>'fechada'
  loop
    q := rr.opop * (0.00002 + 0.00006*greatest(0,(55-rr.oat)/55) + 0.0001*rr.nwar) * coalesce(rr.share,0) * dt * case when rr.ob='fechada' then 0.3 else 1 end;
    continue when q < 1;
    update territories set pop=greatest(0,pop-round(q*pop/greatest(1,rr.opop))) where country_id=rr.oid;
    update territories set pop=pop+round(q) where id=coalesce((select t.id from territories t join countries c on c.id=t.country_id where t.country_id=rr.did and st_contains(t.geom,c.capital) limit 1),
      (select t.id from territories t where t.country_id=rr.did order by t.pop desc limit 1));
    update countries set mig=jsonb_set(coalesce(mig,'{}'),'{out}',to_jsonb(round(_v(mig,'out')+q/dt))) where id=rr.oid;
    update countries set mig=jsonb_set(jsonb_set(coalesce(mig,'{}'),'{in}',to_jsonb(round(_v(mig,'in')+q/dt))),array['from',rr.oname],to_jsonb(round(q/dt))) where id=rr.did;
    if q/dt > 1500 and random() < least(1,0.05*dt) then
      perform _ev(p_match, format('🧳 Onda migratória: cerca de %s pessoas por hora deixam %s rumo a %s.', round(q/dt), rr.oname, rr.dname),null,'evento');
    end if;
  end loop;

  update territories set rebels=least(15,rebels+0.05*dt) where match_id=p_match and country_id is null;
  update territories set occupied=null where match_id=p_match and occupied in (select id from countries where match_id=p_match and not alive);
  if not exists(select 1 from price_hist where match_id=p_match and t>now()-interval '55 minutes') then
    insert into price_hist(match_id,item,p) select p_match,rk,npc_price(p_match,rk) from jsonb_object_keys(d->'res') rk;
  end if;
  if random() < least(0.4, 0.015*dt) then
    k := (array['oil','food','iron','coal','uranium','rare','arms','goods','alu','copper'])[1+floor(random()*10)::int];
    v := case when random()<0.6 then 1.6+random()*0.8 else 0.5+random()*0.2 end;
    update matches set shocks=jsonb_set(coalesce(shocks,'{}'),array[k],jsonb_build_object('m',round(v,2),'until',now()+((8+random()*16)::int)*interval '1 hour')) where id=p_match;
    perform _ev(p_match, case when v>1 then format('📈 Choque no mercado: escassez mundial de %s, preços disparam.', d->'res'->k->>'n') else format('📉 Excesso de %s no mercado mundial: preços despencam.', d->'res'->k->>'n') end, null,'comercio');
  end if;
  if random() < least(0.3, 0.002*dt) then
    update countries set treasury=treasury-greatest(0,treasury*0.1) where match_id=p_match and alive;
    perform _ev(p_match,'🌍 CRISE ECONÔMICA MUNDIAL: mercados despencam em todo o planeta.',null,'alerta');
  end if;
  update matches set last_tick=now(), ver=ver+1 where id=p_match;
end $$;

create or replace function _tick_all() returns void language plpgsql set search_path=public,extensions as $$
declare i uuid; begin for i in select id from matches where status='running' loop perform _tick(i); end loop; end $$;

-- ---------------------------------------------------------------------
-- CONTAS E SALAS
-- ---------------------------------------------------------------------
create or replace function _new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,username) values(new.id, coalesce(nullif(new.raw_user_meta_data->>'username',''),'jogador_'||substr(new.id::text,1,6))) on conflict do nothing;
  return new;
exception when unique_violation then
  insert into public.profiles(id,username) values(new.id,'jogador_'||substr(new.id::text,1,8)) on conflict do nothing; return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function _new_user();

create or replace function set_username(p_name text) returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'Faça login'; end if;
  if length(trim(p_name)) not between 3 and 24 then raise exception 'Nome deve ter de 3 a 24 caracteres'; end if;
  insert into profiles(id,username) values(auth.uid(),trim(p_name)) on conflict(id) do update set username=excluded.username;
exception when unique_violation then raise exception 'Esse nome já está em uso';
end $$;

create or replace function my_matches() returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('user',(select username from profiles where id=auth.uid()),
   'matches',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'name',m.name,'code',m.code,'status',m.status,'host',m.host=auth.uid(),'prep_ends',m.prep_ends,'created',m.created_at,
     'country',(select c.name from countries c where c.match_id=m.id and c.owner=auth.uid() order by c.alive desc limit 1),
     'players',(select count(*) from players x where x.match_id=m.id)) order by m.created_at desc)
    from matches m join players p on p.match_id=m.id and p.user_id=auth.uid()),'[]'::jsonb)) $$;

create or replace function create_match(p_name text) returns uuid language plpgsql security definer set search_path=public,extensions as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Faça login'; end if;
  insert into matches(name,code,host,prep_ends) values(left(coalesce(nullif(trim(p_name),''),'Nova partida'),60), upper(substr(md5(random()::text),1,6)), auth.uid(), now()+interval '24 hours') returning id into v_id;
  insert into players(match_id,user_id) values(v_id,auth.uid());
  perform _ev(v_id,'🏛 Sala criada. A janela de preparação de 24 horas começou.',null,'sistema');
  return v_id;
end $$;

create or replace function join_match(p_code text) returns uuid language plpgsql security definer set search_path=public,extensions as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Faça login'; end if;
  select id into v_id from matches where code=upper(trim(p_code));
  if v_id is null then raise exception 'Código de sala inválido'; end if;
  if not is_member(v_id) then
    insert into players(match_id,user_id) values(v_id,auth.uid());
    perform _ev(v_id, format('👤 %s entrou na sala.', coalesce((select username from profiles where id=auth.uid()),'Um jogador')),null,'sistema');
    update matches set ver=ver+1 where id=v_id;
  end if;
  return v_id;
end $$;

create or replace function start_match(p_match uuid) returns void language plpgsql security definer set search_path=public,extensions as $$
declare mm matches;
begin
  select * into mm from matches where id=p_match for update;
  if not found or mm.host<>auth.uid() then raise exception 'Apenas o anfitrião pode iniciar'; end if;
  if mm.status<>'lobby' then raise exception 'A partida já começou'; end if;
  if now()<mm.prep_ends then raise exception 'A preparação de 24h ainda não terminou'; end if;
  if not exists(select 1 from countries where match_id=p_match) then raise exception 'Nenhum país foi criado ainda'; end if;
  update matches set status='running', started_at=now(), last_tick=now(), ver=ver+1 where id=p_match;
  perform _ev(p_match,'🌍 A partida começou! O relógio mundial está correndo.',null,'alerta');
end $$;

-- ---------------------------------------------------------------------
-- ESTADO DO MUNDO (uma chamada traz tudo o que o jogador pode ver)
-- ---------------------------------------------------------------------
create or replace function get_state(p_match uuid) returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_me uuid; v_lvl int; d jsonb := defs(); v_out jsonb;
begin
  if not is_member(p_match) then raise exception 'Você não participa desta partida'; end if;
  begin perform _tick(p_match); exception when others then raise warning 'tick: %', sqlerrm; end;
  select id, intel_level into v_me, v_lvl from countries where match_id=p_match and owner=auth.uid() and alive;
  select jsonb_build_object('now', now(), 'me', v_me, 'uid', auth.uid(),
    'match', (select to_jsonb(m) from matches m where m.id=p_match),
    'players', (select coalesce(jsonb_agg(jsonb_build_object('id',p.user_id,'name',pr.username)),'[]') from players p left join profiles pr on pr.id=p.user_id where p.match_id=p_match),
    'countries', (select coalesce(jsonb_agg(case when c.id=v_me or exists(select 1 from ops o where o.country_id=v_me and o.target=c.id and o.kind='info' and o.result='sucesso' and o.done_at>now()-interval '48 hours')
        then q.j else q.j - array['treasury','stock','income','expenses','tax','conscription','ministers','intel_level','intel_name','focus','emergency','groups','industry','budget'] end),'[]')
      from countries c, lateral (select (to_jsonb(c) - 'capital') || jsonb_build_object(
        'capital', case when c.capital is null then null else jsonb_build_array(round(st_x(c.capital)::numeric,4), round(st_y(c.capital)::numeric,4)) end,
        'techs', (select count(*) from research r where r.country_id=c.id and r.done_at<=now()),
        'mil', (select coalesce(round(sum(((d->'u'->u.kind->>'a')::numeric+(d->'u'->u.kind->>'d')::numeric)*u.strength),1),0) from units u where u.country_id=c.id),
        'area', (select coalesce(sum(t.area),0) from territories t where t.country_id=c.id),
        'nterr', (select count(*) from territories t where t.country_id=c.id)) j) q where c.match_id=p_match),
    'territories', (select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'c',t.country_id,'n',t.name,'g',st_asgeojson(t.geom,3)::jsonb,'a',t.area,'p',round(t.pop),'r',t.res,'te',t.terrain,'o',t.occupied,'rb',round(t.rebels,1),
        'pt',jsonb_build_array(round(st_x(st_pointonsurface(t.geom))::numeric,3),round(st_y(st_pointonsurface(t.geom))::numeric,3)))),'[]') from territories t where t.match_id=p_match),
    'units', (select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'c',u.country_id,'k',u.kind,'t',u.territory_id,'s',round(u.strength,2),'r',u.ready_at)),'[]') from units u where u.match_id=p_match),
    'buildings', (select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'k',b.kind,'t',b.territory_id,'d',b.done_at)),'[]') from buildings b where b.match_id=p_match),
    'research', (select coalesce(jsonb_agg(jsonb_build_object('t',r.tech,'d',r.done_at)),'[]') from research r where r.country_id=v_me),
    'treaties', (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from treaties x where x.match_id=p_match),
    'wars', (select coalesce(jsonb_agg(to_jsonb(w)),'[]') from wars w where w.match_id=p_match and (w.ended_at is null or w.ended_at>now()-interval '7 days')),
    'orgs', (select coalesce(jsonb_agg(to_jsonb(o)||jsonb_build_object('members',(select coalesce(jsonb_agg(m.country_id),'[]') from org_members m where m.org_id=o.id))),'[]') from orgs o where o.match_id=p_match),
    'proposals', (select coalesce(jsonb_agg(to_jsonb(p) order by p.id desc),'[]') from proposals p where p.match_id=p_match and v_me in (p.from_c,p.to_c) and (p.status='pendente' or p.created_at>now()-interval '2 days')),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'c',case when o.black and o.country_id<>v_me then null else o.country_id end,'mine',o.country_id=v_me,'item',o.item,'qty',o.qty,'price',o.price,'black',o.black,'side',o.side,'org',o.org) order by o.price),'[]')
      from orders o where o.match_id=p_match and (not o.black or coalesce(v_lvl,0)>=1) and (o.org is null or o.country_id=v_me or exists(select 1 from org_members m where m.org_id=o.org and m.country_id=v_me))),
    'trades', (select coalesce(jsonb_agg(jsonb_build_object('i',x.item,'p',x.price,'q',x.qty,'t',x.created_at,'s',x.seller,'b',x.buyer) order by x.id),'[]') from (select * from trades where match_id=p_match order by id desc limit 600) x),
    'contracts', (select coalesce(jsonb_agg(to_jsonb(x) order by x.id desc),'[]') from contracts x where x.match_id=p_match and v_me in (x.seller,x.buyer) and (x.status in ('ativo','suspenso') or x.created_at>now()-interval '3 days')),
    'ph', (select coalesce(jsonb_object_agg(item, arr),'{}') from (select item, jsonb_agg(jsonb_build_array(extract(epoch from t)::bigint, p) order by t) arr from price_hist where match_id=p_match and t>now()-interval '7 days' group by item) x),
    'shocks', (select shocks from matches where id=p_match),
    'prices', (select jsonb_object_agg(k, npc_price(p_match,k)) from jsonb_object_keys(d->'res') k),
    'events', (select coalesce(jsonb_agg(to_jsonb(e) order by e.id desc),'[]') from (select * from events where match_id=p_match and (only_for is null or only_for=v_me) order by id desc limit 150) e),
    'ops', (select coalesce(jsonb_agg(to_jsonb(o) order by o.id desc),'[]') from (select * from ops where country_id=v_me order by id desc limit 40) o),
    'stats', (select coalesce(jsonb_agg(jsonb_build_object('t',s.t,'pop',s.pop,'tr',s.treasury,'gdp',s.gdp,'mil',s.mil,'st',s.stab) order by s.t),'[]') from (select * from stats where country_id=v_me order by t desc limit 200) s)
  ) into v_out;
  return v_out;
end $$;
-- =====================================================================
-- WORLD NATIONS — parte 3/3: ações dos jogadores (todas validadas no servidor)
-- =====================================================================

create or replace function create_country(p_match uuid, p jsonb) returns uuid language plpgsql security definer set search_path=public,extensions as $$
declare g geometry; cap geometry; v_a numeric; cid uuid; tid uuid; old uuid; o geometry; sh numeric; kind text := 'litoral'; fct numeric := 1; ctr geometry; mx numeric := 3000000; popf numeric := 1;
begin
  if not is_member(p_match) then raise exception 'Entre na partida primeiro'; end if;
  select id into old from countries where match_id=p_match and owner=auth.uid();
  if old is not null then
    if (select alive from countries where id=old) then raise exception 'Você já possui um país nesta partida'; end if;
    update countries set owner=null where id=old;
  end if;
  if coalesce(trim(p->>'name'),'')='' then raise exception 'Dê um nome ao país'; end if;
  if coalesce(p->>'color','') !~ '^#[0-9a-fA-F]{6}$' then raise exception 'Cor inválida'; end if;
  g := _poly(p->'poly');
  if jsonb_typeof(p->'capital')<>'array' then raise exception 'Marque a capital dentro do território'; end if;
  cap := st_setsrid(st_makepoint((p->'capital'->>0)::float,(p->'capital'->>1)::float),4326);
  if not st_contains(g,cap) then raise exception 'A capital precisa ficar dentro do território'; end if;
  -- o lugar define o tamanho: ilha isolada encolhe, litoral fica normal, interior (cercado de vizinhos) cresce
  if exists(select 1 from territories where match_id=p_match) then
    if not exists(select 1 from territories where match_id=p_match and st_dwithin(geom::geography, g::geography, 600000)) then
      kind := 'ilha isolada'; fct := 0.65; mx := 1200000; popf := 0.6;
    else
      select st_union(geom) into o from territories where match_id=p_match and st_dwithin(geom::geography, g::geography, 100000);
      if o is not null then
        sh := st_length(st_intersection(st_exteriorring(g), st_buffer(o::geography, 40000)::geometry)::geography) / nullif(st_length(st_exteriorring(g)::geography),0);
        if sh >= 0.35 then kind := 'interior'; fct := 1.35; mx := 6000000; popf := 1.4; end if;
      end if;
    end if;
    if fct<>1 then ctr := st_centroid(g); g := st_scale(g, st_makepoint(fct,fct), ctr); cap := st_scale(cap, st_makepoint(fct,fct), ctr); end if;
    g := _fit(p_match, g);
  end if;
  if not st_contains(g,cap) then cap := st_pointonsurface(g); end if;
  v_a := st_area(g::geography)/1e6;
  if v_a<15000 or v_a>mx then raise exception 'Área final de % km² (%): precisa ficar entre 15 mil e % km²', round(v_a), kind, mx; end if;
  insert into countries(match_id,owner,name,flag,color,capital_name,capital,ideology,government,leader,party,stock)
  values(p_match,auth.uid(),left(trim(p->>'name'),40),
    case when p->>'flag' like 'data:image/%' then left(p->>'flag',30000) else left(coalesce(p->>'flag','🏳'),16) end,
    p->>'color', left(coalesce(nullif(trim(p->>'capital_name'),''),'Capital'),40), cap, left(coalesce(p->>'ideology','Democracia'),40), left(coalesce(p->>'government','República'),40),
    left(coalesce(nullif(trim(p->>'leader'),''),_name()),40), left(p->>'party',40), '{"food":150,"wood":80,"iron":60,"oil":20,"coal":30,"copper":10,"arms":20,"goods":15,"mach":6}')
  returning id into cid;
  insert into territories(match_id,country_id,name,geom,area,pop,res,terrain)
  values(p_match,cid,left(coalesce(nullif(trim(p->>'capital_name'),''),'Núcleo'),40),g,round(v_a),round((5+random()*55)*1e6*popf),_rres(),_terrain()) returning id into tid;
  insert into buildings(match_id,country_id,territory_id,kind,done_at,notified) values(p_match,cid,tid,'farm',now(),true),(p_match,cid,tid,'farm',now(),true),(p_match,cid,tid,'mine',now(),true),(p_match,cid,tid,'factory',now(),true);
  insert into units(match_id,country_id,kind,territory_id,ready_at,notified) select p_match,cid,'inf',tid,now(),true from generate_series(1,4);
  update countries set pop=(select pop from territories where id=tid) where id=cid;
  perform _ev(p_match, format('🏳 Nasce a nação %s (%s, %s) — território %s de %s km².', trim(p->>'name'), coalesce(p->>'government','República'), coalesce(p->>'ideology','Democracia'), kind, round(v_a)),null,'diplo');
  perform _done(p_match,'create_country',jsonb_build_object('name',p->>'name','kind',kind));
  return cid;
end $$;

create or replace function claim_territory(p_match uuid, p_poly jsonb, p_name text) returns uuid language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; g geometry; v_a numeric; tid uuid;
begin
  mc := _me(p_match);
  g := _poly(p_poly);
  if not exists(select 1 from territories t where t.country_id=mc.id and st_dwithin(t.geom::geography,g::geography,300000)) then raise exception 'A nova região precisa estar a até 300 km do seu território'; end if;
  g := _fit(p_match, g);
  v_a := st_area(g::geography)/1e6;
  if v_a<5000 or v_a>800000 then raise exception 'A parte livre da região tem % km²: precisa ter entre 5 mil e 800 mil', round(v_a); end if;
  perform _pay(mc.id, round(80+v_a/800), '{}');
  insert into territories(match_id,country_id,name,geom,area,pop,res,terrain)
  values(p_match,mc.id,left(coalesce(nullif(trim(p_name),''),'Nova região'),40),g,round(v_a),round(v_a*(5+random()*35)),_rres(),_terrain()) returning id into tid;
  perform _ev(p_match, format('🗺 %s anexou a região %s (%s km²).', mc.name, coalesce(nullif(trim(p_name),''),'Nova região'), round(v_a)),null,'diplo');
  perform _done(p_match,'claim',jsonb_build_object('area',round(v_a)));
  return tid;
end $$;

create or replace function set_policy(p_match uuid, p jsonb) returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; d jsonb := defs(); k text; v text;
begin
  mc := _me(p_match, false);
  if p ? 'tax' then update countries set tax=least(0.7,greatest(0,(p->>'tax')::numeric)) where id=mc.id; end if;
  if p ? 'conscription' then update countries set conscription=least(0.15,greatest(0.005,(p->>'conscription')::numeric)) where id=mc.id; end if;
  if p ? 'focus' then
    if p->>'focus' not in ('civil','guerra') then raise exception 'Foco inválido'; end if;
    update countries set focus=p->>'focus' where id=mc.id;
    perform _ev(p_match, format('🏭 %s adotou economia de %s.', mc.name, case when p->>'focus'='guerra' then 'guerra' else 'paz' end),null,'interno');
  end if;
  if p ? 'emergency' then
    update countries set emergency=(p->>'emergency')::bool where id=mc.id;
    perform _ev(p_match, format('🚨 %s %s estado de emergência.', mc.name, case when (p->>'emergency')::bool then 'declarou' else 'encerrou' end),null,'interno');
  end if;
  for k in select jsonb_object_keys(coalesce(p->'doctrines','{}')) loop
    v := p->'doctrines'->>k;
    if coalesce(v,'')='' then update countries set doctrines=doctrines-k where id=mc.id; continue; end if;
    if d->'d'->v is null or d->'d'->v->>'k'<>k then raise exception 'Doutrina inválida'; end if;
    if not _has(mc.id, d->'d'->v->>'t') then raise exception 'Pesquise "%" primeiro', d->'t'->(d->'d'->v->>'t')->>'n'; end if;
    update countries set doctrines=jsonb_set(coalesce(doctrines,'{}'), array[k], to_jsonb(v)) where id=mc.id;
  end loop;
  if p ? 'border' then
    if p->>'border' not in ('aberta','controlada','fechada') then raise exception 'Política de fronteira inválida'; end if;
    update countries set border=p->>'border' where id=mc.id;
    perform _ev(p_match, format('🛂 %s definiu fronteiras %s para imigrantes.', mc.name, case p->>'border' when 'aberta' then 'abertas' when 'fechada' then 'fechadas' else 'controladas' end),null,'interno');
  end if;
  if p ? 'industry' then
    if exists(select 1 from jsonb_object_keys(p->'industry') kk where d->'res'->kk->'rc' is null) then raise exception 'Produto inválido'; end if;
    if (select coalesce(sum(least(1,greatest(0,value::numeric))),0) from jsonb_each_text(p->'industry'))>1.001 then raise exception 'A divisão das fábricas passa de 100%%'; end if;
    update countries set industry=(select coalesce(jsonb_object_agg(key, least(1,greatest(0,value::numeric))),'{}') from jsonb_each_text(p->'industry')) where id=mc.id;
  end if;
  if p ? 'budget' then
    update countries set budget=jsonb_build_object('social',least(2,greatest(0,coalesce((p->'budget'->>'social')::numeric,0))),'edu',least(2,greatest(0,coalesce((p->'budget'->>'edu')::numeric,0)))) where id=mc.id;
  end if;
  if p ? 'leader' then update countries set leader=left(coalesce(nullif(trim(p->>'leader'),''),leader),40) where id=mc.id; end if;
  if p ? 'party' then update countries set party=left(p->>'party',40) where id=mc.id; end if;
  if p ? 'portrait' then
    if p->>'portrait' not like 'data:image/%' then raise exception 'Imagem inválida'; end if;
    update countries set portrait=left(p->>'portrait',40000) where id=mc.id; end if;
  if p ? 'flag' then update countries set flag=case when p->>'flag' like 'data:image/%' then left(p->>'flag',30000) else left(p->>'flag',16) end where id=mc.id; end if;
  if p ? 'color' and p->>'color' ~ '^#[0-9a-fA-F]{6}$' then update countries set color=p->>'color' where id=mc.id; end if;
  if p ? 'ideology' or p ? 'government' then
    if (select status from matches where id=p_match)='running' then
      perform _pay(mc.id,300,'{}'); update countries set stability=greatest(0,stability-15) where id=mc.id; end if;
    update countries set ideology=left(coalesce(nullif(trim(p->>'ideology'),''),ideology),40), government=left(coalesce(nullif(trim(p->>'government'),''),government),40) where id=mc.id;
    perform _ev(p_match, format('⚖ Reforma política em %s: %s / %s.', mc.name, coalesce(p->>'ideology',mc.ideology), coalesce(p->>'government',mc.government)),null,'interno');
  end if;
  perform _done(p_match,'policy',p - 'portrait' - 'flag');
end $$;

create or replace function appoint_minister(p_match uuid, p_role text, p_name text) returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; d jsonb := defs();
begin
  mc := _me(p_match);
  if d->'min'->p_role is null then raise exception 'Cargo inválido'; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'Informe o nome do ministro'; end if;
  perform _pay(mc.id,60,'{}');
  update countries set ministers=jsonb_set(coalesce(ministers,'{}'), array[p_role], jsonb_build_object('n',left(trim(p_name),40),'k',d->'min'->p_role->>'k','b',round((0.02+random()*0.08)::numeric,3))) where id=mc.id;
  perform _done(p_match,'minister',jsonb_build_object('r',p_role));
end $$;

create or replace function elections(p_match uuid) returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries;
begin
  mc := _me(p_match);
  if not (mc.government in ('República','Federação') or mc.ideology in ('Democracia','Liberalismo')) then raise exception 'Seu sistema de governo não realiza eleições'; end if;
  if mc.leader_since > now()-interval '24 hours' then raise exception 'Aguarde 24h desde a última posse'; end if;
  if random()*100 < mc.happiness+10 then
    update countries set stability=least(100,stability+10), leader_since=now() where id=mc.id;
    perform _ev(p_match, format('🗳 Eleições em %s: %s foi reeleito.', mc.name, mc.leader),null,'interno');
  else
    update countries set leader=_name(), party='Oposição', leader_since=now(), stability=greatest(0,stability-5) where id=mc.id;
    perform _ev(p_match, format('🗳 Eleições em %s: o governo perdeu! A oposição assume.', mc.name),null,'interno');
  end if;
  perform _done(p_match,'elections');
end $$;

create or replace function build(p_match uuid, p_terr uuid, p_kind text) returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; d jsonb := defs(); bj jsonb; hrs numeric;
begin
  mc := _me(p_match); bj := d->'b'->p_kind;
  if bj is null then raise exception 'Construção inválida'; end if;
  if not exists(select 1 from territories where id=p_terr and country_id=mc.id) then raise exception 'Construa apenas no seu território'; end if;
  if bj->>'t' is not null and not _has(mc.id,bj->>'t') then raise exception 'Requer a pesquisa: %', d->'t'->(bj->>'t')->>'n'; end if;
  if (select count(*) from buildings where territory_id=p_terr and kind=p_kind)>=10 then raise exception 'Limite de 10 por região'; end if;
  if (select count(*) from buildings b join territories t on t.id=b.territory_id where t.country_id=mc.id and b.done_at>now()) >= 3+_nb(mc.id,'factory')/2 then
    raise exception 'Muitas obras simultâneas (mais fábricas = mais obras)'; end if;
  perform _pay(mc.id,(bj->>'c')::numeric,bj->'r');
  hrs := (bj->>'h')::numeric * greatest(0.4, 1 - _v(fx(mc.id),'build') - case when _nbt(p_terr,'road')+_nbt(p_terr,'rail')>0 then 0.15 else 0 end);
  insert into buildings(match_id,country_id,territory_id,kind,done_at) values(p_match,mc.id,p_terr,p_kind,now()+hrs*interval '1 hour');
  perform _done(p_match,'build',jsonb_build_object('k',p_kind));
end $$;

create or replace function research_start(p_match uuid, p_tech text) returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; d jsonb := defs(); tj jsonb; q text; sp numeric;
begin
  mc := _me(p_match); tj := d->'t'->p_tech;
  if tj is null then raise exception 'Pesquisa inválida'; end if;
  if exists(select 1 from research where country_id=mc.id and tech=p_tech) then raise exception 'Já pesquisada ou em andamento'; end if;
  for q in select jsonb_array_elements_text(coalesce(tj->'req','[]')) loop
    if not _has(mc.id,q) then raise exception 'Requer: %', d->'t'->q->>'n'; end if; end loop;
  if (select count(*) from research where country_id=mc.id and done_at>now()) >= 2+least(2,_nb(mc.id,'lab')) then raise exception 'Todas as vagas de pesquisa estão ocupadas'; end if;
  perform _pay(mc.id,(tj->>'cost')::numeric,'{}');
  sp := 1 + _v(fx(mc.id),'res') + 0.05*least(10,_nb(mc.id,'school')) + 0.15*least(6,_nb(mc.id,'univ')) + 0.25*least(4,_nb(mc.id,'lab')) + mc.education*0.3;
  insert into research(country_id,tech,match_id,done_at) values(mc.id,p_tech,p_match,now()+((tj->>'h')::numeric/sp)*interval '1 hour');
  if coalesce((tj->>'wmd')::bool,false) then
    update countries set infamy=infamy+10 where id=mc.id;
    if exists(select 1 from treaties where kind='proibicao_adm' and mc.id in (a,b)) and random()<0.6 then
      update countries set infamy=infamy+30, stability=greatest(0,stability-10) where id=mc.id;
      perform _ev(p_match, format('🔎 Inspetores internacionais detectaram um programa proibido (%s) em %s, violando o tratado!', tj->>'n', mc.name),null,'alerta');
    elsif random()<0.3 then perform _ev(p_match, format('❓ Rumores de um programa de armas de destruição em massa em %s.', mc.name),null,'alerta'); end if;
  end if;
  perform _done(p_match,'research',jsonb_build_object('t',p_tech));
end $$;

create or replace function recruit(p_match uuid, p_kind text, p_terr uuid, p_qty int default 1) returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; d jsonb := defs(); uj jsonb; mp numeric; used numeric; hrs numeric; q int := least(20,greatest(1,coalesce(p_qty,1)));
begin
  mc := _me(p_match); uj := d->'u'->p_kind;
  if uj is null then raise exception 'Unidade inválida'; end if;
  if not exists(select 1 from territories where id=p_terr and country_id=mc.id) then raise exception 'Recrute em uma região sua'; end if;
  if uj->>'t' is not null and not _has(mc.id,uj->>'t') then raise exception 'Requer a pesquisa: %', d->'t'->(uj->>'t')->>'n'; end if;
  if uj->>'k'='air' and _nbt(p_terr,'airport')=0 then raise exception 'Unidades aéreas exigem aeroporto na região'; end if;
  if uj->>'k'='sea' and _nbt(p_terr,'port')=0 then raise exception 'Unidades navais exigem porto na região'; end if;
  if p_kind in ('art','armor','tank') and _nb(mc.id,'factory')=0 then raise exception 'Equipamento pesado exige ao menos uma fábrica'; end if;
  select coalesce(sum(pop),0)*mc.conscription into mp from territories where country_id=mc.id;
  select coalesce(sum((d->'u'->kind->>'m')::numeric),0) into used from units where country_id=mc.id;
  if used + q*(uj->>'m')::numeric > mp then raise exception 'Mão de obra insuficiente (livre: %). Aumente o alistamento.', round(mp-used); end if;
  perform _pay(mc.id,(uj->>'c')::numeric*q, _add('{}',uj->'r',q));
  hrs := (uj->>'h')::numeric * greatest(0.3, 1 - 0.1*_nbt(p_terr,'base') - 0.05*least(6,_nb(mc.id,'factory')) - case when mc.focus='guerra' then 0.25 else 0 end);
  insert into units(match_id,country_id,kind,territory_id,ready_at) select p_match,mc.id,p_kind,p_terr,now()+hrs*interval '1 hour' from generate_series(1,q);
  if uj->>'k'='strat' then
    update countries set infamy=infamy+8*q where id=mc.id;
    perform _ev(p_match, format('☢ %s está produzindo armas estratégicas (%s).', mc.name, uj->>'n'),null,'alerta');
  end if;
  perform _done(p_match,'recruit',jsonb_build_object('k',p_kind,'q',q));
end $$;

create or replace function move_units(p_match uuid, p_ids bigint[], p_target uuid) returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; d jsonb := defs(); tt territories; n int;
begin
  mc := _me(p_match);
  select * into tt from territories where id=p_target and match_id=p_match;
  if not found then raise exception 'Destino inválido'; end if;
  if tt.country_id is distinct from mc.id and not (tt.country_id is not null and (_allied(mc.id,tt.country_id) or _treaty(mc.id,tt.country_id,'passagem') or _treaty(mc.id,tt.country_id,'militar'))) then
    raise exception 'Sem permissão de passagem para esse território (para invadir, use Atacar)'; end if;
  update units u set territory_id=p_target, ready_at=now() + (st_distance(st_pointonsurface(o.geom)::geography, st_pointonsurface(tt.geom)::geography)/1000
      / ((d->'u'->u.kind->>'s')::numeric * case when _nbt(o.id,'rail')>0 then 1.5 when _nbt(o.id,'road')>0 then 1.2 else 1 end)) * interval '1 hour'
    from territories o where o.id=u.territory_id and u.id=any(p_ids) and u.country_id=mc.id and u.ready_at<=now() and u.territory_id<>p_target;
  get diagnostics n = row_count;
  if n=0 then raise exception 'Nenhuma unidade pronta selecionada'; end if;
  perform _done(p_match,'move',jsonb_build_object('n',n));
end $$;

create or replace function declare_war(p_match uuid, p_target uuid) returns void language plpgsql security definer set search_path=public,extensions as $$
begin perform _declare_war(p_match, _me(p_match), p_target); end $$;
create or replace function _declare_war(p_match uuid, mc countries, p_target uuid) returns void language plpgsql set search_path=public,extensions as $$
declare tc countries; x uuid;
begin
  select * into tc from countries where id=p_target and match_id=p_match and alive;
  if not found or tc.id=mc.id then raise exception 'Alvo inválido'; end if;
  if _war(mc.id,tc.id) then raise exception 'Vocês já estão em guerra'; end if;
  if _allied(mc.id,tc.id) then raise exception 'Vocês são aliados: cancele a defesa mútua / saia da aliança antes'; end if;
  if _treaty(mc.id,tc.id,'nao_agressao') then
    update countries set infamy=infamy+15, stability=greatest(0,stability-10) where id=mc.id;
    perform _ev(p_match, format('💔 %s rompeu o pacto de não agressão com %s!', mc.name, tc.name),null,'alerta');
  end if;
  delete from treaties where ((a=mc.id and b=tc.id) or (a=tc.id and b=mc.id)) and kind<>'sancao';
  insert into wars(match_id,attacker,defender) values(p_match,mc.id,tc.id);
  update countries set infamy=infamy+5 where id=mc.id;
  perform _ev(p_match, format('⚔ %s declarou guerra a %s!', mc.name, tc.name),null,'guerra');
  for x in select distinct y from (
      select case when q.a=tc.id then q.b else q.a end y from treaties q where q.kind='defesa' and tc.id in (q.a,q.b)
      union select m2.country_id from org_members m1 join orgs o on o.id=m1.org_id and o.kind in ('alianca','federacao','coalizao') join org_members m2 on m2.org_id=m1.org_id where m1.country_id=tc.id) z
    where y not in (mc.id,tc.id) and not _allied(mc.id,y) loop
    if not _war(mc.id,x) then
      insert into wars(match_id,attacker,defender) values(p_match,mc.id,x);
      perform _ev(p_match, format('🛡 %s entra na guerra em defesa de %s contra %s.', (select name from countries where id=x), tc.name, mc.name),null,'guerra');
    end if;
  end loop;
  perform _done(p_match,'war',jsonb_build_object('t',p_target));
end $$;

create or replace function attack(p_match uuid, p_target uuid, p_strat text default 'padrao', p_ids bigint[] default null) returns jsonb language plpgsql security definer set search_path=public,extensions as $$
begin return _attack(p_match, _me(p_match), p_target, p_strat, p_ids); end $$;
create or replace function _attack(p_match uuid, mc countries, p_target uuid, p_strat text, p_ids bigint[]) returns jsonb language plpgsql set search_path=public,extensions as $$
declare dc countries; tt territories; d jsonb := defs(); fa jsonb; fd jsonb; atk_p numeric := 0; def_p numeric; att bigint[]; ratio numeric;
  win bool := false; st text := coalesce(p_strat,'padrao'); amph bool; hasarm bool; cas_a numeric := 1; cas_d numeric := 1; v_txt text; newcap geometry; oldname text;
begin
  
  if d->'st'->st is null then raise exception 'Estratégia inválida'; end if;
  select * into tt from territories where id=p_target and match_id=p_match for update;
  if not found or tt.country_id=mc.id then raise exception 'Alvo inválido'; end if;
  if tt.country_id is not null then
    select * into dc from countries where id=tt.country_id;
    if not _war(mc.id,dc.id) then raise exception 'Declare guerra a % antes de atacar', dc.name; end if;
  end if;
  oldname := coalesce(dc.name,'rebeldes');
  fa := fx(mc.id); fd := case when dc.id is null then '{}'::jsonb else fx(dc.id) end;
  amph := st='anfibio' and exists(select 1 from units u where u.country_id=mc.id and u.ready_at<=now() and d->'u'->u.kind->>'k'='sea');
  select array_agg(u.id) into att from units u join territories o on o.id=u.territory_id
   where u.country_id=mc.id and u.ready_at<=now() and (p_ids is null or u.id=any(p_ids))
     and case d->'u'->u.kind->>'k'
          when 'strat' then (st='nuclear' and u.kind='nuke') or (st='quimico' and u.kind='chem')
          when 'air' then st not in ('nuclear','quimico')
          else st not in ('nuclear','quimico','bombardeio') end
     and st_dwithin(o.geom::geography, tt.geom::geography, case d->'u'->u.kind->>'k' when 'air' then 1500000 when 'strat' then 4000000 when 'sea' then 800000 else case when amph then 800000 else 400000 end end);
  if att is null then raise exception 'Nenhuma unidade pronta ao alcance (terrestre 400 km, naval/anfíbio 800 km, aérea 1500 km)'; end if;
  if st in ('nuclear','quimico') then att := att[1:1]; end if;

  select coalesce(sum((d->'u'->u.kind->>'a')::numeric*u.strength*(1+_v(fa,'atk')+_v(fa,'atk_'||(d->'u'->u.kind->>'k')))),0), coalesce(bool_or(u.kind in ('tank','armor')),false)
    into atk_p, hasarm from units u where u.id=any(att);
  def_p := 1 + coalesce(tt.pop,0)/1e7 + coalesce(tt.rebels,0)*1.5;
  select def_p + coalesce(sum((d->'u'->u.kind->>'d')::numeric*u.strength*(1+_v(fd,'def')+_v(fd,'def_'||(d->'u'->u.kind->>'k')))),0) into def_p
    from units u where u.territory_id=tt.id and u.country_id<>mc.id and d->'u'->u.kind->>'k'<>'strat';
  if dc.id is not null then
    select def_p + coalesce(sum((d->'u'->u.kind->>'d')::numeric*u.strength*0.5),0) into def_p from units u join territories o on o.id=u.territory_id
      where u.country_id=dc.id and d->'u'->u.kind->>'k'='air' and u.territory_id<>tt.id and st_dwithin(o.geom::geography,tt.geom::geography,1500000);
    def_p := def_p * (0.7 + dc.stability/333);
  end if;
  def_p := def_p * coalesce((d->'ter'->>tt.terrain)::numeric,1) * (1 + 0.25*_nbt(tt.id,'base'));
  atk_p := atk_p * (0.7 + mc.stability/333) * case when mc.treasury<0 then 0.8 else 1 end * case when _v(mc.stock,'oil')<1 and hasarm then 0.8 else 1 end;
  case st
    when 'blitz' then atk_p := atk_p * case when hasarm then 1.3 else 0.95 end; cas_a := 1.2;
    when 'cerco' then atk_p := atk_p * 1.1; cas_d := 1.5;
    when 'desgaste' then atk_p := atk_p * 0.9; cas_a := 0.7; cas_d := 1.5;
    when 'surpresa' then atk_p := atk_p * case when exists(select 1 from wars w where w.ended_at is null and w.attacker=mc.id and w.defender=dc.id and w.started_at>now()-interval '6 hours') then 1.35 else 0.9 end;
    when 'anfibio' then atk_p := atk_p * 0.8;
    else null;
  end case;
  atk_p := atk_p * (0.85 + random()*0.3);
  ratio := atk_p/greatest(def_p,0.1);

  if st in ('nuclear','quimico') then
    delete from units where id=any(att);
    if st='nuclear' then
      delete from units where territory_id=tt.id; delete from buildings where territory_id=tt.id;
      update territories set pop=round(pop*0.5), rebels=0 where id=tt.id;
      update countries set infamy=infamy+60 where id=mc.id;
      v_txt := format('☢☢ %s lançou um ATAQUE NUCLEAR contra %s (%s)! O mundo condena.', mc.name, oldname, tt.name);
    else
      update units set strength=strength*0.4 where territory_id=tt.id;
      update territories set pop=round(pop*0.9) where id=tt.id;
      update countries set infamy=infamy+35 where id=mc.id;
      v_txt := format('☣ %s usou armas químicas contra %s (%s)!', mc.name, oldname, tt.name);
    end if;
    if dc.id is not null then update countries set stability=greatest(0,stability-20), happiness=greatest(0,happiness-15) where id=dc.id; end if;
    win := true;
  elsif st='bombardeio' then
    if ratio>0.8 then
      delete from buildings where id in (select b.id from buildings b where b.territory_id=tt.id and b.done_at<=now() order by random() limit 2);
      update units set strength=strength*0.85 where territory_id=tt.id and country_id<>mc.id;
      if dc.id is not null then update countries set stability=greatest(0,stability-4) where id=dc.id; end if;
      win := true;
    end if;
    update units set strength=strength*greatest(0.5,1-0.15/greatest(ratio,0.1)), ready_at=now()+interval '3 hours' where id=any(att);
    v_txt := format('💣 %s bombardeou %s (%s): %s. (força %s × %s)', mc.name, tt.name, oldname, case when win then 'alvos destruídos' else 'repelido pela defesa' end, round(atk_p,1), round(def_p,1));
  else
    if ratio>1 then
      win := true;
      update units set strength=strength*greatest(0.2,1-0.25*cas_a/ratio), ready_at=now()+interval '4 hours' where id=any(att);
      if st='cerco' or ratio>2 then delete from units where territory_id=tt.id and country_id<>mc.id;
      else
        update units u set strength=strength*0.4, ready_at=now()+interval '6 hours',
          territory_id=(select x.id from territories x where x.country_id=u.country_id and x.id<>tt.id order by st_distance(x.geom,tt.geom) limit 1)
          where u.territory_id=tt.id and u.country_id<>mc.id;
        delete from units where territory_id is null and match_id=p_match;
      end if;
      update territories set country_id=mc.id, occupied=dc.id, rebels=0 where id=tt.id;
      update units set territory_id=tt.id where id=any(att) and d->'u'->kind->>'k'='land';
      if dc.id is not null then
        if not exists(select 1 from territories where country_id=dc.id) then
          update countries set alive=false where id=dc.id;
          update wars set ended_at=now() where ended_at is null and dc.id in (attacker,defender);
          delete from orders where country_id=dc.id;
          perform _ev(p_match, format('🏴 %s foi completamente conquistado por %s!', dc.name, mc.name),null,'guerra');
        elsif st_contains(tt.geom, dc.capital) then
          select st_pointonsurface(x.geom) into newcap from territories x where x.country_id=dc.id order by x.area desc limit 1;
          update countries set capital=newcap, stability=greatest(0,stability-25) where id=dc.id;
          perform _ev(p_match, format('🏛 A capital de %s caiu! O governo fugiu para outra região.', dc.name),null,'guerra');
        end if;
      end if;
    else
      update units set strength=strength*greatest(0.3,1-least(0.6,0.3*cas_a/greatest(ratio,0.2))), ready_at=now()+interval '4 hours' where id=any(att);
      update units set strength=strength*greatest(0.3,1-0.15*cas_d*ratio) where territory_id=tt.id and country_id<>mc.id;
      if tt.country_id is null then update territories set rebels=greatest(0,rebels-ratio*2) where id=tt.id; end if;
    end if;
    v_txt := format('⚔ Batalha por %s: %s (%s) contra %s — %s. (força %s × %s)', tt.name, mc.name, d->'st'->st->>'n', oldname,
      case when win then 'VITÓRIA, território conquistado' else 'ataque repelido' end, round(atk_p,1), round(def_p,1));
  end if;
  delete from units where strength<0.15 and match_id=p_match;
  perform _ev(p_match, v_txt, null, 'guerra');
  perform _done(p_match,'attack',jsonb_build_object('t',p_target,'s',st));
  return jsonb_build_object('win',win,'atk',round(atk_p,1),'def',round(def_p,1),'msg',v_txt);
end $$;

-- território passa de x para y (acordos, paz, ultimatos)
create or replace function _cede(tid uuid, x uuid, y uuid) returns void language plpgsql set search_path=public,extensions as $$
begin
  if not exists(select 1 from territories where id=tid and country_id=x) then raise exception 'Um dos territórios não pertence mais a quem deveria cedê-lo'; end if;
  if (select st_contains(t.geom,c.capital) from territories t, countries c where t.id=tid and c.id=x) then raise exception 'Não é possível ceder a região da capital'; end if;
  update territories set country_id=y, occupied=null where id=tid;
  update units u set territory_id=(select t.id from territories t where t.country_id=x order by random() limit 1) where u.territory_id=tid and u.country_id=x;
end $$;
create or replace function _deal(x uuid, y uuid, tm jsonb) returns void language plpgsql set search_path=public,extensions as $$
declare tid uuid; m numeric := coalesce((tm->>'pay')::numeric,0);
begin
  for tid in select (jsonb_array_elements_text(coalesce(tm->'give','[]')))::uuid loop perform _cede(tid,x,y); end loop;
  for tid in select (jsonb_array_elements_text(coalesce(tm->'take','[]')))::uuid loop perform _cede(tid,y,x); end loop;
  if m>0 then perform _pay(x,m,'{}'); update countries set treasury=treasury+m where id=y;
  elsif m<0 then perform _pay(y,-m,'{}'); update countries set treasury=treasury-m where id=x; end if;
end $$;

create or replace function propose(p_match uuid, p_to uuid, p_kind text, p_terms jsonb default '{}') returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; tc countries; d jsonb := defs();
begin
  mc := _me(p_match);
  select * into tc from countries where id=p_to and match_id=p_match and alive;
  if not found or tc.id=mc.id then raise exception 'Destino inválido'; end if;
  if not (d->'tr' ? p_kind or p_kind in ('paz','acordo','ultimato','alianca','contrato')) then raise exception 'Tipo de proposta inválido'; end if;
  if p_kind='contrato' and (d->'res'->(p_terms->>'item') is null or coalesce((p_terms->>'qty')::numeric,0) not between 0.1 and 1000 or coalesce((p_terms->>'price')::numeric,0)<=0
     or coalesce((p_terms->>'hours')::int,0) not between 1 and 240 or coalesce(p_terms->>'dir','') not in ('vendo','compro')) then raise exception 'Contrato inválido'; end if;
  if p_kind='paz' and not _war(mc.id,tc.id) then raise exception 'Vocês não estão em guerra'; end if;
  if p_kind<>'paz' and _war(mc.id,tc.id) and p_kind<>'ultimato' then raise exception 'Em guerra só é possível propor paz ou ultimato'; end if;
  if p_kind='alianca' and not exists(select 1 from org_members where org_id=(p_terms->>'org')::uuid and country_id=mc.id) then raise exception 'Você não é membro dessa organização'; end if;
  if d->'tr' ? p_kind and _treaty(mc.id,tc.id,p_kind) then raise exception 'Esse tratado já existe'; end if;
  if (select count(*) from proposals where from_c=mc.id and to_c=tc.id and status='pendente')>=5 then raise exception 'Muitas propostas pendentes para esse país'; end if;
  insert into proposals(match_id,from_c,to_c,kind,terms) values(p_match,mc.id,tc.id,p_kind,coalesce(p_terms,'{}'));
  perform _ev(p_match, format('📨 %s enviou uma proposta: %s.', mc.name, coalesce(d->'tr'->>p_kind, initcap(p_kind))), tc.id, 'diplo');
  if p_kind='ultimato' then perform _ev(p_match, format('⚠ %s enviou um ULTIMATO a %s.', mc.name, tc.name),null,'alerta'); end if;
  perform _done(p_match,'propose',jsonb_build_object('k',p_kind));
end $$;

create or replace function respond(p_match uuid, p_id bigint, p_accept bool) returns void language plpgsql security definer set search_path=public,extensions as $$
begin perform _respond(p_match, _me(p_match), p_id, p_accept); end $$;
create or replace function _respond(p_match uuid, mc countries, p_id bigint, p_accept bool) returns void language plpgsql set search_path=public,extensions as $$
declare pp proposals; fc countries; d jsonb := defs(); nm text;
begin
  
  select * into pp from proposals where id=p_id and status='pendente' and match_id=p_match for update;
  if not found then raise exception 'Proposta não encontrada'; end if;
  if pp.from_c=mc.id and not p_accept then update proposals set status='cancelada' where id=pp.id; perform _done(p_match,'respond'); return; end if;
  if pp.to_c<>mc.id then raise exception 'Esta proposta não é para você'; end if;
  select * into fc from countries where id=pp.from_c;
  if not fc.alive then raise exception 'O proponente não existe mais'; end if;
  if not p_accept then
    update proposals set status='recusada' where id=pp.id;
    perform _ev(p_match, format('❌ %s recusou sua proposta (%s).', mc.name, coalesce(d->'tr'->>pp.kind,pp.kind)), fc.id,'diplo');
    if pp.kind='ultimato' then perform _ev(p_match, format('%s rejeitou o ultimato de %s.', mc.name, fc.name),null,'alerta'); end if;
  else
    if d->'tr' ? pp.kind then
      if not _treaty(fc.id,mc.id,pp.kind) then insert into treaties(match_id,a,b,kind) values(p_match,fc.id,mc.id,pp.kind); end if;
      perform _ev(p_match, format('✍ Tratado assinado: %s entre %s e %s.', d->'tr'->>pp.kind, fc.name, mc.name),null,'diplo');
    elsif pp.kind='contrato' then
      insert into contracts(match_id,seller,buyer,item,qty,price,ends_at) values(p_match, case when pp.terms->>'dir'='vendo' then fc.id else mc.id end,
        case when pp.terms->>'dir'='vendo' then mc.id else fc.id end, pp.terms->>'item', (pp.terms->>'qty')::numeric, (pp.terms->>'price')::numeric, now()+((pp.terms->>'hours')::int)*interval '1 hour');
      perform _ev(p_match, format('📑 Contrato de fornecimento: %s/h de %s entre %s e %s por %sh.', pp.terms->>'qty', d->'res'->(pp.terms->>'item')->>'n', fc.name, mc.name, pp.terms->>'hours'),null,'comercio');
    elsif pp.kind='alianca' then
      insert into org_members(org_id,country_id) values((pp.terms->>'org')::uuid, mc.id) on conflict do nothing;
      select name into nm from orgs where id=(pp.terms->>'org')::uuid;
      perform _ev(p_match, format('🤝 %s entrou na organização %s.', mc.name, nm),null,'diplo');
    else
      if pp.kind='paz' then
        if not _war(fc.id,mc.id) then raise exception 'A guerra já terminou'; end if;
        update wars set ended_at=now() where ended_at is null and ((attacker=fc.id and defender=mc.id) or (attacker=mc.id and defender=fc.id));
        update territories set occupied=null where (country_id=fc.id and occupied=mc.id) or (country_id=mc.id and occupied=fc.id);
      end if;
      perform _deal(fc.id,mc.id,pp.terms);
      perform _ev(p_match, format('🕊 %s entre %s e %s aceito.', case pp.kind when 'paz' then 'Tratado de paz' when 'ultimato' then 'Ultimato' else 'Acordo' end, fc.name, mc.name),null,'diplo');
    end if;
    update proposals set status='aceita' where id=pp.id;
  end if;
  perform _done(p_match,'respond');
end $$;

create or replace function cancel_treaty(p_match uuid, p_id bigint) returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; x treaties; d jsonb := defs();
begin
  mc := _me(p_match);
  select * into x from treaties where id=p_id and match_id=p_match and mc.id in (a,b);
  if not found then raise exception 'Tratado não encontrado'; end if;
  if x.kind='sancao' and x.a<>mc.id then raise exception 'Só quem aplicou a sanção pode suspendê-la'; end if;
  delete from treaties where id=x.id;
  perform _ev(p_match, format('📜 %s encerrou: %s com %s.', mc.name, coalesce(d->'tr'->>x.kind,'sanções'), (select name from countries where id=case when x.a=mc.id then x.b else x.a end)),null,'diplo');
  perform _done(p_match,'cancel_treaty');
end $$;

create or replace function sanction(p_match uuid, p_target uuid) returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; tn text;
begin
  mc := _me(p_match);
  select name into tn from countries where id=p_target and match_id=p_match and alive and id<>mc.id;
  if tn is null then raise exception 'Alvo inválido'; end if;
  if exists(select 1 from treaties where kind='sancao' and a=mc.id and b=p_target) then
    delete from treaties where kind='sancao' and a=mc.id and b=p_target;
    perform _ev(p_match, format('📜 %s suspendeu as sanções contra %s.', mc.name, tn),null,'diplo');
  else
    insert into treaties(match_id,a,b,kind) values(p_match,mc.id,p_target,'sancao');
    perform _ev(p_match, format('🚫 %s aplicou sanções econômicas contra %s.', mc.name, tn),null,'diplo');
  end if;
  perform _done(p_match,'sanction');
end $$;

create or replace function gift(p_match uuid, p_to uuid, p_money numeric default 0, p_res jsonb default '{}', p_units bigint[] default null, p_secret bool default false) returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; tn text; v_m numeric := greatest(0,coalesce(p_money,0)); n int := 0;
begin
  mc := _me(p_match);
  select name into tn from countries where id=p_to and match_id=p_match and alive and id<>mc.id;
  if tn is null then raise exception 'Destino inválido'; end if;
  perform _pay(mc.id, v_m, coalesce(p_res,'{}'));
  update countries set treasury=treasury+v_m, stock=_add(stock,coalesce(p_res,'{}')) where id=p_to;
  if p_units is not null then
    update units set country_id=p_to, ready_at=now()+interval '12 hours', territory_id=(select t.id from territories t where t.country_id=p_to order by t.area desc limit 1)
      where id=any(p_units) and country_id=mc.id and ready_at<=now();
    get diagnostics n = row_count;
  end if;
  if p_secret then
    perform _ev(p_match, format('🤫 %s enviou ajuda secreta: 💰%s, recursos e %s unidades.', mc.name, round(v_m), n), p_to, 'diplo');
  else
    perform _ev(p_match, format('🎁 %s enviou ajuda a %s (💰%s, %s unidades).', mc.name, tn, round(v_m), n),null,'diplo');
  end if;
  perform _done(p_match,'gift');
end $$;

create or replace function surrender(p_match uuid, p_enemy uuid) returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; v_r numeric;
begin
  mc := _me(p_match);
  if not _war(mc.id,p_enemy) then raise exception 'Vocês não estão em guerra'; end if;
  update wars set ended_at=now() where ended_at is null and ((attacker=mc.id and defender=p_enemy) or (attacker=p_enemy and defender=mc.id));
  update territories set occupied=null where country_id=p_enemy and occupied=mc.id;
  v_r := greatest(0, mc.treasury*0.25);
  update countries set treasury=treasury-v_r, stability=greatest(0,stability-15) where id=mc.id;
  update countries set treasury=treasury+v_r where id=p_enemy;
  perform _ev(p_match, format('🏳 %s se rendeu a %s e pagou 💰%s em reparações. Os territórios ocupados foram anexados.', mc.name, (select name from countries where id=p_enemy), round(v_r)),null,'guerra');
  perform _done(p_match,'surrender');
end $$;

create or replace function create_org(p_match uuid, p jsonb) returns uuid language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; v_id uuid;
begin
  mc := _me(p_match);
  if defs()->'org'->(p->>'kind') is null then raise exception 'Tipo inválido'; end if;
  if coalesce(trim(p->>'name'),'')='' then raise exception 'Dê um nome à organização'; end if;
  perform _pay(mc.id,100,'{}');
  insert into orgs(match_id,name,flag,descr,rules,kind,leader) values(p_match,left(trim(p->>'name'),50),left(coalesce(p->>'flag','🏛'),16),left(p->>'descr',400),left(p->>'rules',400),p->>'kind',mc.id) returning id into v_id;
  insert into org_members(org_id,country_id) values(v_id,mc.id);
  perform _ev(p_match, format('🏛 Fundada a organização %s (%s) por %s.', trim(p->>'name'), defs()->'org'->>(p->>'kind'), mc.name),null,'diplo');
  perform _done(p_match,'create_org');
  return v_id;
end $$;

create or replace function org_action(p_match uuid, p_org uuid, p_act text, p_country uuid default null) returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; oo orgs;
begin
  mc := _me(p_match);
  select * into oo from orgs where id=p_org and match_id=p_match;
  if not found then raise exception 'Organização não encontrada'; end if;
  if p_act='sair' then
    delete from org_members where org_id=p_org and country_id=mc.id;
    if oo.leader=mc.id then
      update orgs set leader=(select country_id from org_members where org_id=p_org limit 1) where id=p_org;
      delete from orgs where id=p_org and leader is null;
    end if;
    perform _ev(p_match, format('🚪 %s deixou %s.', mc.name, oo.name),null,'diplo');
  elsif p_act in ('expulsar','lider') then
    if oo.leader is distinct from mc.id then raise exception 'Apenas o líder pode fazer isso'; end if;
    if not exists(select 1 from org_members where org_id=p_org and country_id=p_country) or p_country=mc.id then raise exception 'Membro inválido'; end if;
    if p_act='expulsar' then delete from org_members where org_id=p_org and country_id=p_country;
      perform _ev(p_match, format('⛔ %s foi expulso de %s.', (select name from countries where id=p_country), oo.name),null,'diplo');
    else update orgs set leader=p_country where id=p_org; end if;
  else raise exception 'Ação inválida'; end if;
  perform _done(p_match,'org');
end $$;

create or replace function market(p_match uuid, p_act text, p jsonb) returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; d jsonb := defs(); oo orders; q numeric; pr numeric; tot numeric; it text := p->>'item'; v_org uuid;
begin
  mc := _me(p_match);
  q := round(coalesce((p->>'qty')::numeric,0),1);
  if p_act in ('sell','bid','npc_buy','npc_sell','black_buy','black_sell') and d->'res'->it is null then raise exception 'Produto inválido'; end if;
  if p_act<>'cancel' and (q<=0 or q>100000) then raise exception 'Quantidade inválida'; end if;
  if p_act in ('sell','bid') then
    pr := round((p->>'price')::numeric,2);
    if pr is null or pr<=0 then raise exception 'Preço inválido'; end if;
    if coalesce((p->>'black')::bool,false) and mc.intel_level<1 then raise exception 'O mercado negro exige um serviço secreto (nível 1+)'; end if;
    v_org := nullif(p->>'org','')::uuid;
    if v_org is not null and not exists(select 1 from org_members where org_id=v_org and country_id=mc.id) then raise exception 'Você não é membro dessa organização'; end if;
    if p_act='sell' then perform _pay(mc.id,0,jsonb_build_object(it,q)); else perform _pay(mc.id,round(q*pr,2),'{}'); end if;
    insert into orders(match_id,country_id,item,qty,price,black,side,org)
    values(p_match,mc.id,it,q,pr,coalesce((p->>'black')::bool,false) and p_act='sell',case when p_act='sell' then 'sell' else 'buy' end,v_org);
  elsif p_act='cancel' then
    delete from orders where id=(p->>'id')::bigint and country_id=mc.id returning * into oo;
    if oo.id is null then raise exception 'Oferta não encontrada'; end if;
    if oo.side='buy' then update countries set treasury=treasury+round(oo.qty*oo.price,2) where id=mc.id;
    else update countries set stock=_add(stock,jsonb_build_object(oo.item,oo.qty)) where id=mc.id; end if;
  elsif p_act in ('buy','fill') then
    select * into oo from orders where id=(p->>'id')::bigint and match_id=p_match for update;
    if not found or oo.country_id=mc.id or oo.side<>(case when p_act='buy' then 'sell' else 'buy' end) then raise exception 'Oferta indisponível'; end if;
    if oo.org is not null and not exists(select 1 from org_members where org_id=oo.org and country_id=mc.id) then raise exception 'Oferta exclusiva para membros de outra organização'; end if;
    if oo.black and mc.intel_level<1 then raise exception 'Requer serviço secreto'; end if;
    if not oo.black and (_war(mc.id,oo.country_id) or exists(select 1 from treaties where kind='sancao' and ((a=mc.id and b=oo.country_id) or (a=oo.country_id and b=mc.id)))) then
      raise exception 'Comércio bloqueado por guerra ou sanções'; end if;
    q := least(q,oo.qty); tot := round(q*oo.price,2);
    if p_act='buy' then
      perform _pay(mc.id,tot,'{}');
      update countries set treasury=treasury+tot where id=oo.country_id;
      if oo.black and random()<0.15 then perform _ev(p_match, format('🚨 Carga clandestina de %s apreendida! Mercadoria perdida.', d->'res'->oo.item->>'n'), mc.id,'alerta');
      else update countries set stock=_add(stock,jsonb_build_object(oo.item,q)) where id=mc.id; end if;
    else
      perform _pay(mc.id,0,jsonb_build_object(oo.item,q));
      update countries set treasury=treasury+tot where id=mc.id;
      update countries set stock=_add(stock,jsonb_build_object(oo.item,q)) where id=oo.country_id;
    end if;
    if oo.qty-q<=0.01 then delete from orders where id=oo.id; else update orders set qty=qty-q where id=oo.id; end if;
    if not oo.black then
      insert into trades(match_id,item,qty,price,seller,buyer) values(p_match,oo.item,q,oo.price,
        case when p_act='buy' then oo.country_id else mc.id end, case when p_act='buy' then mc.id else oo.country_id end);
      perform _ev(p_match, format('📦 %s %s %s de %s por 💰%s.', mc.name, case when p_act='buy' then 'comprou' else 'vendeu' end, q, d->'res'->oo.item->>'n', tot), oo.country_id,'comercio');
    elsif random()<0.1 then
      update countries set infamy=infamy+5 where id=mc.id;
      perform _ev(p_match, format('🕵 Rede de contrabando exposta: %s negociou %s no mercado negro.', mc.name, d->'res'->oo.item->>'n'),null,'alerta');
    end if;
  elsif p_act='npc_buy' then
    pr := round(npc_price(p_match,it)*1.25,2); tot := round(q*pr,2);
    perform _pay(mc.id,tot,'{}');
    update countries set stock=_add(stock,jsonb_build_object(it,q)) where id=mc.id;
    insert into trades(match_id,item,qty,price,npc,buyer) values(p_match,it,q,pr,true,mc.id);
  elsif p_act='npc_sell' then
    pr := round(npc_price(p_match,it)*0.8,2);
    perform _pay(mc.id,0,jsonb_build_object(it,q));
    update countries set treasury=treasury+round(q*pr,2) where id=mc.id;
    insert into trades(match_id,item,qty,price,npc,seller) values(p_match,it,q,pr,true,mc.id);
  elsif p_act in ('black_buy','black_sell') then
    if mc.intel_level<1 then raise exception 'O mercado negro exige um serviço secreto (nível 1+)'; end if;
    if p_act='black_buy' then
      if it not in ('arms','veh','plane','uranium','rare','oil','alu') then raise exception 'Os contrabandistas não oferecem esse produto'; end if;
      pr := round(npc_price(p_match,it)*1.7,2); perform _pay(mc.id, round(q*pr,2), '{}');
      if random()<0.12 then perform _ev(p_match, format('🕶 Golpe! Os contrabandistas sumiram com 💰%s e não entregaram %s.', round(q*pr), d->'res'->it->>'n'), mc.id,'alerta');
      else update countries set stock=_add(stock,jsonb_build_object(it,q)) where id=mc.id; end if;
    else
      pr := round(npc_price(p_match,it)*0.9,2); perform _pay(mc.id,0,jsonb_build_object(it,q));
      update countries set treasury=treasury+round(q*pr,2) where id=mc.id;
    end if;
    if random()<0.08 then update countries set infamy=infamy+5 where id=mc.id;
      perform _ev(p_match, format('🕵 Investigação internacional expõe contrabando de %s ligado a %s.', d->'res'->it->>'n', mc.name),null,'alerta'); end if;
  else raise exception 'Ação inválida'; end if;
  perform _done(p_match,'market',jsonb_build_object('a',p_act));
end $$;

create or replace function intel(p_match uuid, p_act text, p jsonb default '{}') returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; oj jsonb; tgt uuid;
begin
  mc := _me(p_match);
  if p_act='upgrade' then
    if mc.intel_level>=4 then raise exception 'Nível máximo (Elite)'; end if;
    perform _pay(mc.id, 150*(mc.intel_level+1)*(mc.intel_level+1), '{}');
    update countries set intel_level=intel_level+1, intel_name=coalesce(nullif(left(trim(p->>'name'),40),''),intel_name,'Serviço Secreto Nacional') where id=mc.id;
  elsif p_act='op' then
    oj := defs()->'ops'->(p->>'kind'); tgt := (p->>'target')::uuid;
    if oj is null then raise exception 'Operação inválida'; end if;
    if mc.intel_level < (oj->>'lv')::int then raise exception 'Requer serviço secreto nível %', oj->>'lv'; end if;
    if tgt=mc.id or not exists(select 1 from countries where id=tgt and match_id=p_match and alive) then raise exception 'Alvo inválido'; end if;
    if (select count(*) from ops where country_id=mc.id and result is null) >= 1+mc.intel_level then raise exception 'Agentes insuficientes: aguarde as operações em andamento'; end if;
    perform _pay(mc.id,(oj->>'c')::numeric,'{}');
    insert into ops(match_id,country_id,target,kind,done_at) values(p_match,mc.id,tgt,p->>'kind',now()+(oj->>'h')::numeric*interval '1 hour');
  else raise exception 'Ação inválida'; end if;
  perform _done(p_match,'intel',jsonb_build_object('a',p_act));
end $$;

create or replace function cancel_contract(p_match uuid, p_id bigint) returns void language plpgsql security definer set search_path=public,extensions as $$
declare mc countries; x contracts;
begin
  mc := _me(p_match);
  select * into x from contracts where id=p_id and match_id=p_match and mc.id in (seller,buyer) and status in ('ativo','suspenso');
  if not found then raise exception 'Contrato não encontrado'; end if;
  update contracts set status='cancelado' where id=x.id;
  update countries set infamy=infamy+2 where id=mc.id;
  perform _ev(p_match, format('📑 %s rompeu um contrato de %s.', mc.name, defs()->'res'->x.item->>'n'), case when x.seller=mc.id then x.buyer else x.seller end,'comercio');
  perform _done(p_match,'cancel_contract');
end $$;

-- ---------------------------------------------------------------------
-- SALA: apagar e bots
-- ---------------------------------------------------------------------
create or replace function delete_match(p_match uuid) returns void language plpgsql security definer set search_path=public,extensions as $$
begin
  if not exists(select 1 from matches where id=p_match and host=auth.uid()) then raise exception 'Apenas o dono da sala pode apagá-la'; end if;
  delete from matches where id=p_match;
end $$;

create or replace function _bot_name() returns text language sql volatile as $$
  select (array['Val','Mor','Kar','Ost','Bel','Tir','Nov','Sar','Lun','Dra','Ves','Cor','Alt','Bra','Zan','Eld','Fen','Gal','Hor','Ism','Jor','Kel','Mar','Nor','Pel','Quel','Rav','Sol','Tar','Ur'])[1+floor(random()*30)::int]
      || (array['dória','ávia','ânia','istão','ária','lândia','burgo','ena','ica','óvia','essa','ard','ir','one','ális'])[1+floor(random()*15)::int] $$;

-- o dono da sala cria um país controlado pelo computador em espaço livre (de preferência perto dos outros)
create or replace function add_bot(p_match uuid, p_kind text default 'equilibrado') returns uuid language plpgsql security definer set search_path=public,extensions as $$
declare mm matches; g geometry; ctr geometry; pts geometry[]; i int; r numeric; a numeric; tries int := 0; v_a numeric := 0; cid uuid; tid uuid; nm text; base territories; ok bool := false;
begin
  select * into mm from matches where id=p_match;
  if not found or mm.host<>auth.uid() then raise exception 'Apenas o dono da sala pode adicionar bots'; end if;
  if p_kind not in ('pacifico','equilibrado','agressivo') then raise exception 'Tipo de bot inválido'; end if;
  if (select count(*) from countries where match_id=p_match and bot is not null and alive) >= 12 then raise exception 'Máximo de 12 bots por sala'; end if;
  while not ok and tries < 20 loop
    tries := tries + 1; base := null;
    select * into base from territories where match_id=p_match order by random() limit 1;
    if base.id is not null and random() < 0.8 then
      a := random()*2*pi(); r := 9 + random()*8;
      ctr := st_setsrid(st_makepoint(least(170,greatest(-170, st_x(st_centroid(base.geom)) + cos(a)*r*1.3)), least(65,greatest(-55, st_y(st_centroid(base.geom)) + sin(a)*r))),4326);
    else ctr := st_setsrid(st_makepoint(-150+random()*300, -50+random()*110),4326); end if;
    r := 3.5 + random()*3; pts := '{}';
    for i in 0..13 loop
      a := i*2*pi()/14;
      pts := pts || st_makepoint(st_x(ctr) + cos(a)*r*(0.7+random()*0.45)/cos(radians(st_y(ctr))), st_y(ctr) + sin(a)*r*(0.7+random()*0.45));
    end loop;
    g := st_setsrid(st_makepolygon(st_makeline(pts || pts[1])),4326);
    continue when not st_isvalid(g);
    begin g := _fit(p_match, g); exception when others then continue; end;
    v_a := st_area(g::geography)/1e6;
    ok := v_a between 60000 and 3000000;
  end loop;
  if not ok then raise exception 'Não achei espaço livre para o bot. Tente de novo.'; end if;
  nm := _bot_name();
  insert into countries(match_id,owner,bot,name,flag,color,capital_name,capital,ideology,government,leader,party,stock)
  values(p_match, null, p_kind, nm, (array['🦁','🐺','🦅','🐉','⚔','🌙','☀','🌲','⛰','🐻','🦂','🐍','⭐','🔱','🛡','🌊'])[1+floor(random()*16)::int],
    '#'||lpad(to_hex(floor(random()*16777215)::int),6,'0'), _bot_name(), st_pointonsurface(g),
    (array['Capitalismo','Comunismo','Democracia','Socialismo','Liberalismo','Nacionalismo','Fascismo'])[1+floor(random()*7)::int],
    (array['República','Monarquia','Império','Ditadura','Federação','República socialista'])[1+floor(random()*6)::int], _name(), 'Partido Nacional',
    '{"food":150,"wood":80,"iron":60,"oil":20,"coal":30,"copper":10,"arms":20,"goods":15,"mach":6}') returning id into cid;
  insert into territories(match_id,country_id,name,geom,area,pop,res,terrain)
  values(p_match, cid, (select capital_name from countries where id=cid), g, round(v_a), round((5+random()*40)*1e6), _rres(), _terrain()) returning id into tid;
  insert into buildings(match_id,country_id,territory_id,kind,done_at,notified) values(p_match,cid,tid,'farm',now(),true),(p_match,cid,tid,'farm',now(),true),(p_match,cid,tid,'mine',now(),true),(p_match,cid,tid,'factory',now(),true);
  insert into units(match_id,country_id,kind,territory_id,ready_at,notified) select p_match,cid,'inf',tid,now(),true from generate_series(1,4);
  update countries set pop=(select pop from territories where id=tid) where id=cid;
  perform _ev(p_match, format('🤖 Nasce a nação %s, controlada pelo computador (%s).', nm, case p_kind when 'pacifico' then 'pacífica' when 'agressivo' then 'agressiva' else 'equilibrada' end),null,'diplo');
  update matches set ver=ver+1 where id=p_match;
  return cid;
end $$;

create or replace function remove_bot(p_match uuid, p_country uuid) returns void language plpgsql security definer set search_path=public,extensions as $$
declare nm text;
begin
  if not exists(select 1 from matches where id=p_match and host=auth.uid()) then raise exception 'Apenas o dono da sala pode remover bots'; end if;
  select name into nm from countries where id=p_country and match_id=p_match and bot is not null;
  if nm is null then raise exception 'Bot não encontrado'; end if;
  delete from territories where country_id=p_country;
  delete from countries where id=p_country;
  perform _ev(p_match, format('🤖 %s foi retirado do mundo.', nm),null,'diplo');
  update matches set ver=ver+1 where id=p_match;
end $$;

-- cérebro do bot: roda a cada ciclo do mundo
create or replace function _bot_act(p_match uuid, cc countries, dt numeric) returns void language plpgsql set search_path=public,extensions as $$
declare d jsonb := defs(); pp proposals; fc countries; e countries; t territories; acc bool; k text; tk text; n int; v numeric; mymil numeric; omil numeric; tid uuid; agr numeric;
begin
  agr := case cc.bot when 'agressivo' then 1 when 'pacifico' then 0 else 0.5 end;
  select coalesce(sum(((d->'u'->u.kind->>'a')::numeric+(d->'u'->u.kind->>'d')::numeric)*u.strength),0) into mymil from units u where u.country_id=cc.id;
  -- 1) responde propostas recebidas
  for pp in select * from proposals where to_c=cc.id and status='pendente' and match_id=p_match loop
    select * into fc from countries where id=pp.from_c;
    select coalesce(sum(((d->'u'->u.kind->>'a')::numeric+(d->'u'->u.kind->>'d')::numeric)*u.strength),0) into omil from units u where u.country_id=fc.id;
    acc := case
      when pp.kind='paz' then mymil < omil*1.1 or random() < 0.3
      when pp.kind='ultimato' then mymil < omil*0.5
      when pp.kind='contrato' then random() < 0.6
      when pp.kind='acordo' then coalesce((pp.terms->>'pay')::numeric,0) > 0 and jsonb_array_length(coalesce(pp.terms->'take','[]'))=0
      when pp.kind in ('defesa','militar','passagem','alianca') then fc.infamy < 40 and random() < 0.7 - agr*0.3
      else fc.infamy < 60 and random() < 0.8 end;
    begin perform _respond(p_match, cc, pp.id, acc); exception when others then update proposals set status='recusada' where id=pp.id; end;
  end loop;
  if random() > least(1, dt*2) then return; end if;           -- age mais ou menos a cada 30 minutos
  -- 2) economia: comida, excedentes
  select * into cc from countries where id=cc.id;
  if _v(cc.stock,'food') < 40 then
    v := npc_price(p_match,'food')*1.25*50;
    if cc.treasury > v then update countries set treasury=treasury-v, stock=_add(stock,'{"food":50}') where id=cc.id; end if;
  end if;
  for k in select key from jsonb_each_text(cc.stock) where value::numeric > 300 and not (d->'res'->key ? 'g') loop
    update countries set treasury=treasury+npc_price(p_match,k)*0.8*100, stock=_add(stock,jsonb_build_object(k,100),-1,0) where id=cc.id;
  end loop;
  -- 3) obras
  select * into cc from countries where id=cc.id;
  if cc.treasury > 180 and (select count(*) from buildings b join territories x on x.id=b.territory_id where x.country_id=cc.id and b.done_at>now()) < 2 then
    k := case when _v(cc.stock,'food') < 60 then 'farm' when _nb(cc.id,'factory') < 2 + floor(cc.pop/2e7) then 'factory'
      when cc.happiness < 50 then (array['hospital','school'])[1+floor(random()*2)::int]
      when agr > 0.6 and random() < 0.3 then 'base'
      else (array['farm','mine','road','school','factory','hospital','power','rail','port','univ','lab','city'])[1+floor(random()*12)::int] end;
    select * into t from territories where country_id=cc.id order by random() limit 1;
    if t.id is not null and (d->'b'->k->>'t' is null or _has(cc.id, d->'b'->k->>'t')) then
      begin
        perform _pay(cc.id, (d->'b'->k->>'c')::numeric, d->'b'->k->'r');
        insert into buildings(match_id,country_id,territory_id,kind,done_at) values(p_match,cc.id,t.id,k,now()+((d->'b'->k->>'h')::numeric)*interval '1 hour');
      exception when others then null; end;
    end if;
  end if;
  -- 4) pesquisa (agressivos preferem militar; nunca armas de destruição em massa)
  select * into cc from countries where id=cc.id;
  if cc.treasury > 250 and not exists(select 1 from research where country_id=cc.id and done_at>now()) then
    select x.key into tk from jsonb_each(d->'t') x
      where not exists(select 1 from research r where r.country_id=cc.id and r.tech=x.key) and not coalesce((x.value->>'wmd')::bool,false)
        and not exists(select 1 from jsonb_array_elements_text(coalesce(x.value->'req','[]')) q where not _has(cc.id,q))
      order by (x.value->>'cost')::numeric * case when agr > 0.6 and x.value->>'c' in ('Militar','Doutrinas') then 0.5 else 1 end + random()*100 limit 1;
    if tk is not null then begin
      perform _pay(cc.id,(d->'t'->tk->>'cost')::numeric,'{}');
      insert into research(country_id,tech,match_id,done_at) values(cc.id,tk,p_match,now()+((d->'t'->tk->>'h')::numeric)*interval '1 hour');
    exception when others then null; end; end if;
  end if;
  -- 5) exército
  select * into cc from countries where id=cc.id;
  select count(*) into n from units where country_id=cc.id;
  if n < 4 + cc.pop/1e7*(1+agr*2) and cc.treasury > 60 then
    k := case when _has(cc.id,'tanques') and _v(cc.stock,'veh')>=2 and _v(cc.stock,'arms')>=2 then 'tank'
      when _has(cc.id,'artilharia') and random()<0.3 and _v(cc.stock,'arms')>=3 then 'art' else 'inf' end;
    select * into t from territories where country_id=cc.id order by st_contains(geom,cc.capital) desc, random() limit 1;
    begin
      perform _pay(cc.id,(d->'u'->k->>'c')::numeric, d->'u'->k->'r');
      insert into units(match_id,country_id,kind,territory_id,ready_at) values(p_match,cc.id,k,t.id,now()+((d->'u'->k->>'h')::numeric)*interval '1 hour');
    exception when others then
      if _v(cc.stock,'arms') < 1 and cc.treasury > 150 then
        update countries set treasury=treasury-npc_price(p_match,'arms')*1.25*3, stock=_add(stock,'{"arms":3}') where id=cc.id; end if;
    end;
  end if;
  -- 6) guerra: agressivos atacam vizinhos fracos; quem está perdendo pede paz
  select * into cc from countries where id=cc.id;
  if agr > 0 and random() < agr*0.08 and not exists(select 1 from wars w where w.ended_at is null and cc.id in (w.attacker,w.defender)) then
    e := null;
    select c.* into e from countries c where c.match_id=p_match and c.alive and c.id<>cc.id and not _allied(cc.id,c.id)
      and not exists(select 1 from treaties x where x.kind in ('nao_agressao','comercio','livre_comercio') and ((x.a=cc.id and x.b=c.id) or (x.a=c.id and x.b=cc.id)))
      and exists(select 1 from territories a, territories b where a.country_id=cc.id and b.country_id=c.id and st_dwithin(a.geom::geography,b.geom::geography,300000))
      and (select coalesce(sum(((d->'u'->u.kind->>'a')::numeric+(d->'u'->u.kind->>'d')::numeric)*u.strength),0) from units u where u.country_id=c.id) < mymil*0.6
      order by random() limit 1;
    if e.id is not null then perform _declare_war(p_match, cc, e.id); end if;
  end if;
  for e in select c.* from countries c join wars w on w.ended_at is null and ((w.attacker=cc.id and w.defender=c.id) or (w.defender=cc.id and w.attacker=c.id)) where c.alive loop
    if (select count(*) from units u where u.country_id=cc.id and u.ready_at<=now()) >= 3 and random() < 0.5 then
      tid := null;
      select x.id into tid from territories x, territories mine where x.country_id=e.id and mine.country_id=cc.id
        and exists(select 1 from units u where u.territory_id=mine.id and u.country_id=cc.id and u.ready_at<=now())
        and st_dwithin(x.geom::geography, mine.geom::geography, 400000)
        order by st_distance(x.geom::geography, mine.geom::geography) limit 1;
      if tid is not null then
        begin perform _attack(p_match, cc, tid, case when _has(cc.id,'motorizacao') then 'blitz' else 'padrao' end, null); exception when others then null; end;
      end if;
    end if;
    select coalesce(sum(((d->'u'->u.kind->>'a')::numeric+(d->'u'->u.kind->>'d')::numeric)*u.strength),0) into omil from units u where u.country_id=e.id;
    if mymil < omil*0.5 and random() < 0.2 and not exists(select 1 from proposals where from_c=cc.id and to_c=e.id and status='pendente') then
      insert into proposals(match_id,from_c,to_c,kind,terms) values(p_match,cc.id,e.id,'paz','{"pay":0}');
      perform _ev(p_match, format('📨 %s enviou uma proposta: Tratado de paz.', cc.name), e.id, 'diplo');
    end if;
  end loop;
  -- 7) diplomacia: os pacíficos procuram acordos com jogadores
  if random() < 0.1*(1-agr) then
    e := null;
    select c.* into e from countries c where c.match_id=p_match and c.alive and c.id<>cc.id and c.owner is not null and not _war(cc.id,c.id)
      and not exists(select 1 from treaties x where x.kind='comercio' and ((x.a=cc.id and x.b=c.id) or (x.a=c.id and x.b=cc.id)))
      and not exists(select 1 from proposals p where p.from_c=cc.id and p.to_c=c.id and p.status='pendente') order by random() limit 1;
    if e.id is not null then
      insert into proposals(match_id,from_c,to_c,kind,terms) values(p_match,cc.id,e.id,(array['comercio','nao_agressao','pesquisa'])[1+floor(random()*3)::int],'{}');
      perform _ev(p_match, format('📨 %s enviou uma proposta diplomática.', cc.name), e.id, 'diplo');
    end if;
  end if;
end $$;

-- funções internas (começam com _) não podem ser chamadas pelo navegador
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like '\_%' loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig); end loop; end $$;

-- mundo evolui sozinho a cada 10 min (requer extensão pg_cron; sem ela o tempo é recalculado a cada acesso)
do $$ begin
  create extension if not exists pg_cron;
  perform cron.schedule('world-nations-tick','*/10 * * * *','select public._tick_all()');
exception when others then raise notice 'pg_cron indisponível (%). Ative em Database > Extensions e rode este bloco de novo.', sqlerrm; end $$;
