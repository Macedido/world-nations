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
