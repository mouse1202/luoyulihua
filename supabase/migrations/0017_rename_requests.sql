-- 改名申請：幫眾自己送，管理在後台按同意。
--
-- 真正的改名動作還是 rename_player（0008／0012／0013 migration）——
-- 名單、出勤、排表、指揮、影片、登入身分直接改掉，戰績記一筆曾用名對照。
-- 這一份只加前面那一段：誰想改成什麼、誰同意了。
--
-- 跟管理自己用的「名字對照 → 改名」差在一道硬擋：
-- 新名字只要在現有資料裡出現過就不給送，也不給同意。
-- 管理那條路留著合併的選項（內容一模一樣的重複登記可以併），
-- 但那種要人判斷，不是幫眾自助該碰的。

create table if not exists public.rename_requests (
  id          bigint generated always as identity primary key,
  requester   text not null,            -- 送出申請的人（＝舊名字，只能改自己的）
  old_name    text not null,
  new_name    text not null,
  reason      text not null default '',
  status      text not null default '待審核'
              check (status in ('待審核', '已同意', '已退回')),
  created_at  timestamptz not null default now(),
  reviewed_by text,
  reviewed_at timestamptz,
  review_note text not null default ''
);

alter table public.rename_requests enable row level security;

-- 一個人同時只能有一筆待審核的。送第二筆之前要先取消或等管理處理掉。
create unique index if not exists rename_requests_one_pending
  on public.rename_requests (requester)
  where status = '待審核';

create index if not exists rename_requests_status_idx
  on public.rename_requests (status, created_at desc);

-- 這個名字現在有沒有人在用。
--
-- 回 { inUse: bool, where: [...] }，where 是人看的說明，撞到哪幾項就列哪幾項。
--
-- 查這幾張：
--   · 名單 —— 已經有一個現役的他
--   · 登入身分 —— 已經有人用這個名字登入
--   · 曾用名 —— 這個名字是別人改名前用過的，對照會打架
--   · 出勤／影片 —— 有他的紀錄，改過去會撞在一起
--
-- 排表、指揮、戰績不查：那些是歷史，留著不動是刻意的，而且外援、路人
-- 本來就會出現在排表與戰績裡，拿來擋會把一堆正常的名字擋掉。
create or replace function public.name_in_use(p_name text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
-- 用 array_append 不用 ||：text[] || 未標型別的字串字面值會被當成陣列字面值解析，
-- 「登入身分」不是合法的陣列字面值，執行時會炸。
declare
  v text := btrim(p_name);
  v_where text[] := '{}';
  v_cat text;
begin
  if v = '' then
    return jsonb_build_object('inUse', false, 'where', '[]'::jsonb);
  end if;

  select string_agg(distinct
           case category
             when 'member' then '主名單'
             when 'guest'  then '外援'
             when 'trial'  then '試訓'
             when 'club'   then '俱樂部成員'
             else category
           end, '、')
    into v_cat
    from public.roster_members where name = v;
  if v_cat is not null then
    v_where := array_append(v_where, '名單（' || v_cat || '）');
  end if;

  if exists (select 1 from public.access_requests where name = v) then
    v_where := array_append(v_where, '登入身分');
  end if;

  if exists (select 1 from public.player_aliases where alias_name = v) then
    v_where := array_append(v_where, '曾用名對照');
  end if;

  if exists (select 1 from public.attendance_records where name = v) then
    v_where := array_append(v_where, '出勤紀錄');
  end if;

  if exists (select 1 from public.video_uploads where name = v) then
    v_where := array_append(v_where, '影片紀錄');
  end if;

  return jsonb_build_object(
    'inUse', array_length(v_where, 1) is not null,
    'where', to_jsonb(v_where)
  );
end $$;

revoke all on function public.name_in_use(text) from public, anon, authenticated;
