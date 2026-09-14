-- 改回以前用過的名字時，改名會被擋成「新舊名字一樣」。
--
-- 實例：9/10 做過一次「心笑 → 夢幻」，系統記下別名 心笑 = 夢幻。
-- 之後他又改回「心笑」，在名字對照按「夢幻 → 心笑」：
-- rename_player 發現新名字「心笑」是別名，就換算成它的正名「夢幻」，
-- 結果新舊一樣，整個拒絕。
--
-- 換算的本意是避免別名串成一條鏈（A→B 之後又 C→A，要直接記 C→B）。
-- 但如果那個別名指回的正是這次的舊名字，代表的是「改回原名」，
-- 要做的是把那筆別名拆掉、反過來記，而不是換算。
--
-- 拆別名要等所有檢查都通過之後才做 —— 函式是用回傳值表示失敗、不是丟例外，
-- 提早刪的話改名被擋下來別名也已經沒了。

create or replace function public.rename_player(
  p_old   text,
  p_new   text,
  p_actor text default '',
  p_merge boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conflicts jsonb;
  v_blocking  jsonb;
  v_same      jsonb;
  v_resolved  text;
  v_reverse   boolean := false;
  v_battles   jsonb;
  n_roster int; n_att int; n_slots int; n_cmd int; n_vid int; n_access int; n_repoint int;
  n_del_att int := 0; n_del_vid int := 0; n_del_acc int := 0;
begin
  p_old := btrim(p_old);
  p_new := btrim(p_new);

  if p_old = '' or p_new = '' then
    return jsonb_build_object('success', false, 'message', '名字不能是空白');
  end if;

  select canonical_name into v_resolved from public.player_aliases where alias_name = p_new;
  if v_resolved is not null then
    if v_resolved = p_old then
      -- 改回以前的名字：那筆「新名字 = 舊名字」的別名要拆掉，後面反過來記
      v_reverse := true;
    else
      -- 新名字本身是別人的別名：直接指到最終的正名，避免串成鏈
      p_new := v_resolved;
    end if;
  end if;

  if p_old = p_new then
    return jsonb_build_object('success', false, 'message', '新舊名字一樣');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_old || '|' || p_new, 0));

  select coalesce(jsonb_agg(distinct
           b.battle_date || case when coalesce(b.battle_time,'') = '' then ''
                                 else ' ' || b.battle_time end
           || ' vs ' || b.opp_guild), '[]'::jsonb)
    into v_battles
    from public.battle_players x
    join public.battle_players y on y.battle_id = x.battle_id
    join public.battles b        on b.id = x.battle_id
   where x.name = p_old and x.side = 'my'
     and y.name = p_new and y.side = 'my';

  if jsonb_array_length(v_battles) > 0 then
    return jsonb_build_object(
      'success', false,
      'sameBattle', v_battles,
      'message', '「' || p_old || '」和「' || p_new || '」同時出現在同一場戰鬥裡，'
                 || '這是兩個人，不能改名合併'
    );
  end if;

  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_conflicts from (
    select jsonb_build_object(
             'type', '出勤', 'detail', a.date_label,
             'same', (a.status is not distinct from b.status),
             'oldValue', a.status, 'newValue', b.status) as x
      from public.attendance_records a
      join public.attendance_records b
        on b.date_label = a.date_label and b.name = p_new
     where a.name = p_old
    union all
    select jsonb_build_object(
             'type', '影片', 'detail', v.date_label,
             'same', (coalesce(v.url1,'') = coalesce(w.url1,'')
                      and coalesce(v.url2,'') = coalesce(w.url2,'')),
             'oldValue', coalesce(v.url1,'') || ' / ' || coalesce(v.url2,''),
             'newValue', coalesce(w.url1,'') || ' / ' || coalesce(w.url2,''))
      from public.video_uploads v
      join public.video_uploads w
        on w.date_label = v.date_label and w.name = p_new
     where v.name = p_old
    union all
    select jsonb_build_object(
             'type', '登入身分', 'detail', p_new,
             'same', (r.status is not distinct from s.status
                      and r.category is not distinct from s.category),
             'oldValue', coalesce(r.category,'') || '／' || coalesce(r.status,''),
             'newValue', coalesce(s.category,'') || '／' || coalesce(s.status,''))
      from public.access_requests r
      join public.access_requests s on s.name = p_new
     where r.name = p_old
    union all
    select jsonb_build_object(
             'type', '名單', 'detail', p_new, 'same', false,
             'oldValue', m.category, 'newValue', n.category)
      from public.roster_members m
      join public.roster_members n on n.name = p_new
     where m.name = p_old
  ) t;

  if jsonb_array_length(v_conflicts) > 0 then
    select coalesce(jsonb_agg(c), '[]'::jsonb) into v_blocking
      from jsonb_array_elements(v_conflicts) c
     where (c ->> 'same') is distinct from 'true';
    select coalesce(jsonb_agg(c), '[]'::jsonb) into v_same
      from jsonb_array_elements(v_conflicts) c
     where (c ->> 'same') = 'true';

    if not p_merge or jsonb_array_length(v_blocking) > 0 then
      return jsonb_build_object(
        'success', false,
        'conflicts', v_conflicts,
        'mergeable', v_same,
        'blocking', v_blocking,
        'canMerge', (jsonb_array_length(v_blocking) = 0),
        'message', '「' || p_new || '」已經有資料了，先處理掉才能改名'
      );
    end if;

    delete from public.attendance_records a
     where a.name = p_old
       and exists (select 1 from public.attendance_records b
                    where b.date_label = a.date_label and b.name = p_new);
    get diagnostics n_del_att = row_count;

    delete from public.video_uploads v
     where v.name = p_old
       and exists (select 1 from public.video_uploads w
                    where w.date_label = v.date_label and w.name = p_new);
    get diagnostics n_del_vid = row_count;

    delete from public.access_requests r
     where r.name = p_old
       and exists (select 1 from public.access_requests s where s.name = p_new);
    get diagnostics n_del_acc = row_count;
  end if;

  -- 檢查全部通過了，現在才拆掉那筆反方向的別名。
  -- 一定要在下面「改指別名」之前拆，不然它會被改成「心笑 = 心笑」指向自己。
  if v_reverse then
    delete from public.player_aliases where alias_name = p_new;
  end if;

  update public.roster_members     set name = p_new where name = p_old;
  get diagnostics n_roster = row_count;
  update public.attendance_records set name = p_new where name = p_old;
  get diagnostics n_att = row_count;
  update public.roster_slots       set name = p_new where name = p_old;
  get diagnostics n_slots = row_count;
  update public.roster_commanders  set name = p_new where name = p_old;
  get diagnostics n_cmd = row_count;
  update public.video_uploads      set name = p_new where name = p_old;
  get diagnostics n_vid = row_count;
  update public.access_requests    set name = p_new where name = p_old;
  get diagnostics n_access = row_count;

  update public.player_aliases set canonical_name = p_new where canonical_name = p_old;
  get diagnostics n_repoint = row_count;

  insert into public.player_aliases (alias_name, canonical_name, created_by)
  values (p_old, p_new, coalesce(p_actor, ''))
  on conflict (alias_name)
    do update set canonical_name = excluded.canonical_name,
                  created_by     = excluded.created_by,
                  created_at     = now();

  return jsonb_build_object(
    'success', true,
    'reversedAlias', v_reverse,
    'merged', (n_del_att + n_del_vid + n_del_acc),
    'mergedAttendance', n_del_att, 'mergedVideos', n_del_vid, 'mergedAccess', n_del_acc,
    'roster', n_roster, 'attendance', n_att, 'slots', n_slots,
    'commanders', n_cmd, 'videos', n_vid, 'access', n_access,
    'aliasRepointed', n_repoint,
    'battles', (select count(*) from public.battle_players
                 where name = p_old and side = 'my')
  );
end $$;

revoke all on function public.rename_player(text, text, text, boolean)
  from public, anon, authenticated;
