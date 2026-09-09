-- 玩家改名：現況資料直接改掉，歷史戰績改用別名對照。
--
-- 為什麼分兩種處理方式：
--   名單／出勤／排表／指揮／影片／登入身分 是「當下狀態」，沒有東西會把它們
--   覆蓋回去，直接改最單純。
--
--   戰績（battle_players）是從遊戲匯出的 CSV 反覆匯入的歷史紀錄。直接改寫它，
--   下次重新匯入同一份 CSV 又會把舊名字寫回來，改了等於白改。而且那場當下他
--   本來就叫那個名字，改寫歷史也不太對。所以戰績留著不動，改成記一筆別名，
--   讀取的時候再換算成現在的名字。
--
-- 遊戲的 CSV 裡只有名字、沒有玩家 ID，所以「A 改名成 B」這件事系統無法自己
-- 推論，一定要有人講一次 —— 這張表就是把那句話記下來。

create table if not exists public.player_aliases (
  alias_name     text primary key,          -- 曾經用過的名字
  canonical_name text not null,             -- 現在的名字
  created_at     timestamptz not null default now(),
  created_by     text not null default ''
);

create index if not exists idx_player_aliases_canonical
  on public.player_aliases (canonical_name);

-- 跟其他表一樣：開 RLS 但不給任何 policy，只有 Edge Function（service_role）進得來
alter table public.player_aliases enable row level security;


-- 改名本體。回傳每張表各改了幾筆，衝突時不做任何事、直接把衝突列出來。
create or replace function public.rename_player(
  p_old text,
  p_new text,
  p_actor text default ''
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conflicts jsonb;
  v_resolved  text;
  n_roster int; n_att int; n_slots int; n_cmd int; n_vid int; n_access int; n_repoint int;
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

  -- 衝突檢查：新名字已經有資料的話先不動，讓人自己決定怎麼併
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_conflicts from (
    select jsonb_build_object('type', '出勤', 'detail', a.date_label) as x
      from public.attendance_records a
     where a.name = p_old
       and exists (select 1 from public.attendance_records b
                    where b.date_label = a.date_label and b.name = p_new)
    union all
    select jsonb_build_object('type', '影片', 'detail', v.date_label)
      from public.video_uploads v
     where v.name = p_old
       and exists (select 1 from public.video_uploads w
                    where w.date_label = v.date_label and w.name = p_new)
    union all
    select jsonb_build_object('type', '登入身分', 'detail', p_new)
     where exists (select 1 from public.access_requests where name = p_old)
       and exists (select 1 from public.access_requests where name = p_new)
    union all
    select jsonb_build_object('type', '名單', 'detail', p_new)
     where exists (select 1 from public.roster_members where name = p_old)
       and exists (select 1 from public.roster_members where name = p_new)
  ) t;

  if jsonb_array_length(v_conflicts) > 0 then
    return jsonb_build_object(
      'success', false,
      'conflicts', v_conflicts,
      'message', '「' || p_new || '」已經有資料了，先處理掉才能改名'
    );
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
    'roster', n_roster, 'attendance', n_att, 'slots', n_slots,
    'commanders', n_cmd, 'videos', n_vid, 'access', n_access,
    'aliasRepointed', n_repoint,
    'battles', (select count(*) from public.battle_players
                 where name = p_old and side = 'my')
  );
end $$;

revoke all on function public.rename_player(text, text, text)
  from public, anon, authenticated;
