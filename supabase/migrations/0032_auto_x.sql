-- 分得出「系統自動補的 X」和「人工點的 X」。
--
-- 為什麼要這個：
-- 一個人改了遊戲裡的名字之後，管理常常是直接到「管理名單」把名字換掉。
-- 對系統來說那是「走了一個人、來了一個新人」，於是 markPreJoinAbsent_
-- 會把這個「新人」加入之前的每一場都補一筆 X（不補的話，沒有紀錄的
-- 場次會被當成「出勤」，出勤率會灌水 —— 見 0030 之前的設計）。
-- 結果就是：改名的人前面三十幾場全變 X，而他真正的歷史被孤立在舊名字下。
-- 11/12～11/14 連續發生五次（流沙包丶、小管家、京圈大小姐，另外還有
-- 一批待確認），每次都要人工下 SQL 才救得回來。
--
-- 有了這個欄位，系統就記得哪些 X 是它自己猜的，可以一鍵撤銷：
-- 「他其實是改名」→ 清掉自動補的 X → 走正常改名繼承歷史。
--
-- 注意：只有「系統猜的」才是 true。人只要手動動過那一格，就不再是猜的，
-- 所以 save_attendance_record 寫入時一律把它清成 false（見下面）。

alter table public.attendance_records
  add column if not exists auto_x boolean not null default false;

/* 回填以前補的。
   認法：同一個人、同一個 updated_at、一次二十幾到三十幾筆 X。
   這種形狀只有批次寫入才做得出來 —— 人工是一格一格點的，每一次
   都是獨立的交易、各自有自己的 now()，不可能好幾筆共用同一個時間戳；
   「全員調整」也是一場次對很多人，每人各一筆、時間戳也各自不同。
   門檻放 10 是保守值（目前每批都是 31～33 筆）。 */
with batches as (
  select name, updated_at
    from public.attendance_records
   where status = 'X'
   group by name, updated_at
  having count(*) >= 10
)
update public.attendance_records a
   set auto_x = true
  from batches b
 where a.name = b.name
   and a.updated_at = b.updated_at
   and a.status = 'X';

/* 人工寫入時把標記清掉：只要有人真的去點過那一格，
   那一筆就是人說的，不能再被「一鍵撤銷」掃掉。
   除了多一個 auto_x = false，其餘跟 0007 完全一樣。 */
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
  perform pg_advisory_xact_lock(hashtextextended(p_date || '|' || p_name, 0));

  select status into v_old
    from public.attendance_records
   where date_label = p_date and name = p_name;

  insert into public.attendance_records (date_label, name, job, status, updated_at, auto_x)
  values (p_date, p_name, p_job, p_status, now(), false)
  on conflict (date_label, name) do update
     set status     = excluded.status,
         job        = excluded.job,
         updated_at = excluded.updated_at,
         auto_x     = false;

  return v_old;
end $$;

revoke all on function public.save_attendance_record(text, text, text, text)
  from public, anon, authenticated;
