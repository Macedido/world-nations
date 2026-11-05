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
