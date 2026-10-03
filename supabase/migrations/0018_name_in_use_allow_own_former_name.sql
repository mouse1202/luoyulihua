-- 改回原名被自己的硬擋擋掉了。
--
-- A 改成 B 之後，rename_player 會留一筆別名「A = B」（戰績不改寫，靠別名換算）。
-- 之後 B 想改回 A，name_in_use('A') 查到那筆別名就回「曾用名對照」，
-- 整個申請在送出的那一步就被拒絕。
--
-- 實測：「我掉線了」想改回「窩杯酌橘辣」→ 擋下；「我被素了」想改回「結冰水」→ 擋下。
--
-- 但那筆別名指的就是申請人自己 —— 那不是「別人在用」，是他自己的舊名字。
-- rename_player（0013 migration）本來就處理得了這種情況：發現新名字是一筆
-- 指回舊名字的別名時，會把那筆拆掉、反過來記，而不是當成換算。
--
-- 所以多一個參數 p_for：「這個名字是要給誰用的」。別名指向 p_for 自己的時候
-- 不算被佔用，其他情況照舊擋。沒帶 p_for 就是原本的行為（一律擋）。
--
-- 其他幾張表不用做這個例外：A 改成 B 的時候，名單、出勤、影片、登入身分裡的
-- A 都已經被改成 B 了，A 不會留在那些表上。只有別名會留著。

drop function if exists public.name_in_use(text);

create or replace function public.name_in_use(p_name text, p_for text default '')
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
  v_for text := btrim(coalesce(p_for, ''));
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

  -- 別名指向 p_for 自己 → 那是他自己的舊名字，改回去是允許的
  if exists (select 1 from public.player_aliases
              where alias_name = v
                and (v_for = '' or canonical_name is distinct from v_for)) then
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

revoke all on function public.name_in_use(text, text) from public, anon, authenticated;
