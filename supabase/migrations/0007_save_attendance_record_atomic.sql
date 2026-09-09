-- 出勤狀態的「先讀舊值、再寫新值」改成一個不會被插隊的動作。
--
-- 原本 Edge Function 是分兩步：先 select 舊狀態、再 upsert 新狀態。
-- 兩個請求靠得夠近時，兩邊都會在對方寫進去之前讀到「這個人還沒有紀錄」，
-- 於是操作記錄兩筆都寫成「設為 X」，看不出前一個狀態是什麼。
-- 實際發生過（相隔 248ms 的兩筆都寫「設為」）：
--   15:30:03.075  冷沁莓 設為「X」
--   15:30:03.323  冷沁莓 設為「請假」
--
-- 資料本身不會壞（upsert 是後寫的贏），壞的是稽核記錄 ——
-- 要查「誰把我的請假改掉」的時候查不準。
--
-- 這裡用 advisory lock 把同一個 (日期, 姓名) 序列化，並回傳舊狀態，
-- 讓呼叫端能寫出正確的「從 A 改成 B」。

create or replace function public.save_attendance_record(
  p_date   text,
  p_name   text,
  p_job    text,
  p_status text
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old text;
begin
  -- 交易結束自動釋放；只鎖同一個人的同一天，不影響其他人同時登記
  perform pg_advisory_xact_lock(hashtextextended(p_date || '|' || p_name, 0));

  select status into v_old
    from public.attendance_records
   where date_label = p_date and name = p_name;

  insert into public.attendance_records (date_label, name, job, status, updated_at)
  values (p_date, p_name, p_job, p_status, now())
  on conflict (date_label, name) do update
     set status     = excluded.status,
         job        = excluded.job,
         updated_at = excluded.updated_at;

  return v_old;   -- 之前沒有紀錄就回 null
end $$;

-- 只有 Edge Function（service_role）能呼叫，維持「anon 什麼都碰不到」
revoke all on function public.save_attendance_record(text, text, text, text)
  from public, anon, authenticated;
