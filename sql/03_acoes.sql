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
declare mc countries; tc countries; x uuid;
begin
  mc := _me(p_match);
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
declare mc countries; dc countries; tt territories; d jsonb := defs(); fa jsonb; fd jsonb; atk_p numeric := 0; def_p numeric; att bigint[]; ratio numeric;
  win bool := false; st text := coalesce(p_strat,'padrao'); amph bool; hasarm bool; cas_a numeric := 1; cas_d numeric := 1; v_txt text; newcap geometry; oldname text;
begin
  mc := _me(p_match);
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
declare mc countries; pp proposals; fc countries; d jsonb := defs(); nm text;
begin
  mc := _me(p_match);
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

-- funções internas (começam com _) não podem ser chamadas pelo navegador
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like '\_%' loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig); end loop; end $$;

-- mundo evolui sozinho a cada 10 min (requer extensão pg_cron; sem ela o tempo é recalculado a cada acesso)
do $$ begin
  create extension if not exists pg_cron;
  perform cron.schedule('world-nations-tick','*/10 * * * *','select public._tick_all()');
exception when others then raise notice 'pg_cron indisponível (%). Ative em Database > Extensions e rode este bloco de novo.', sqlerrm; end $$;
