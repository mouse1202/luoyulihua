-- 改名的兩個問題，一起處理。
--
-- 一、衝突時是死路
--   「改名」是把舊名字的紀錄搬到新名字上。新名字在同一個場次已經有同類紀錄
--   就會撞在一起，所以本來整個不做、只把衝突列出來，但沒有任何往下走的辦法。
--
--   實際遇到的例子：名單上正確的名字是「鏡蜃魑影」，早期打成「鏡影魑影」，
--   0910／0912／1001 三場兩個名字各有一筆出勤，而且兩邊都是「X」——
--   內容一模一樣的重複登記，直接刪掉舊的那份什麼都不會少。
--
--   所以衝突現在會標出 same（兩邊內容是不是一樣）。全部都一樣的話，
--   帶 p_merge => true 再呼叫一次就會把舊名字那份重複的刪掉再改名。
--   只要有一筆內容不一樣就還是不做 —— 那種要人自己看過決定留哪個。
--
-- 二、兩個不同的人被當成同一個人
--   同一場戰鬥裡如果兩個名字都在場上，那必然是兩個人，不可能是誰改名。
--   實際遇到的例子：「玖壹壹」（碎夢）與「我掉線了」（潮光）在 0910 第一場、
--   第二場、0912 兩場全都同時出現，但因為兩人都傳了 0912 的影片才剛好被
--   衝突檢查擋下來。那天要是只有一個人傳影片，這個改名就會過，兩個人的
--   戰績、出勤、排表就合成一個了。
--
--   所以加一道硬擋：同場出現過就直接拒絕，p_merge 也沒有用。

drop function if exists public.rename_player(text, text, text);

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
  v_battles   jsonb;
  n_roster int; n_att int; n_slots int; n_cmd int; n_vid int; n_access int; n_repoint int;
  n_del_att int := 0; n_del_vid int := 0; n_del_acc int := 0;
begin
  p_old := btrim(p_old);
  p_new := btrim(p_new);

  if p_old = '' or p_new = '' then
    return jsonb_build_object('success', false, 'message', '名字不能是空白');
  end if;

  -- 新名字如果本身已經是別的名字的別名，直接指到最終的那個，避免串成一條鏈
  select canonical_name into v_resolved from public.player_aliases where alias_name = p_new;
  if v_resolved is not null then
    p_new := v_resolved;
  end if;

  if p_old = p_new then
    return jsonb_build_object('success', false, 'message', '新舊名字一樣');
  end if;

  -- 同一組名字同時被改兩次時序列化
  perform pg_advisory_xact_lock(hashtextextended(p_old || '|' || p_new, 0));

  -- ── 硬擋：同一場戰鬥裡兩個名字都在場 ──────────────────────
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

  -- ── 衝突：新名字在同一個場次已經有同類紀錄 ─────────────────
  -- same = 兩邊內容一樣（重複登記），可以直接刪掉舊的那份
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
    -- 兩邊都在名單上代表是兩個現役成員，永遠不能自動合併
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

    -- 沒帶 p_merge，或有內容不一樣的衝突 → 不動，把情況回報回去
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

    -- 全部都是重複登記：把舊名字那一份刪掉
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

  -- 本來指向舊名字的別名要一起改指到新名字
  update public.player_aliases set canonical_name = p_new where canonical_name = p_old;
  get diagnostics n_repoint = row_count;

  -- 戰績不動，改記一筆別名
  insert into public.player_aliases (alias_name, canonical_name, created_by)
  values (p_old, p_new, coalesce(p_actor, ''))
  on conflict (alias_name)
    do update set canonical_name = excluded.canonical_name,
                  created_by     = excluded.created_by,
                  created_at     = now();

  return jsonb_build_object(
    'success', true,
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
