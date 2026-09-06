-- 出勤狀態「臨時請假」改名為「X」。
--
-- 這是存進資料庫的實際字串（不是只有畫面顯示），所以 check 約束要一起換。
-- 順序：先拆約束 → 改資料 → 再裝回新的約束，不然中間那步會被舊約束擋下來。
--
-- 對應改動：
--   index.html  ATTENDANCE_STATUS_OPTIONS / 統計標籤「X 數」
--   lylhapi     exportAttendanceAll 的表頭「X數」與計數 key

alter table public.attendance_records
  drop constraint attendance_records_status_check;

update public.attendance_records
   set status = 'X'
 where status = '臨時請假';

alter table public.attendance_records
  add constraint attendance_records_status_check
  check (status = any (array['出勤', '請假', 'X']));
