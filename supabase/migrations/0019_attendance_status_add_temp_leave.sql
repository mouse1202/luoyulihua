-- 出勤狀態多一個「臨時請假」，變成四種：出勤／請假／臨時請假／X。
--
-- 注意歷史：0006 migration 曾經把「臨時請假」整個改名成「X」，當時是
-- 「同一件事換個名字」。這次不一樣 —— 是要在 X 之外再多一種，兩者並存：
--   請假     ＝ 事前就說不來
--   臨時請假 ＝ 當天臨時才說不來
--   X        ＝ 沒說一聲就沒出現
-- 所以舊資料一律不動，既有的 X 還是 X，不會被改回「臨時請假」。
--
-- status 是存進資料庫的實際字串，所以 check 約束要一起放寬。
-- 順序：先拆約束 → 再裝回新的（這次沒有要改資料，所以中間不用 update）。
--
-- 對應改動：
--   index.html  ATTENDANCE_STATUS_OPTIONS、統計多一個「臨時請假」框、
--               排表工具左側多一個「臨時請假」窗格
--   lylhapi     exportAttendanceAll 的表頭與計數多一欄

alter table public.attendance_records
  drop constraint attendance_records_status_check;

alter table public.attendance_records
  add constraint attendance_records_status_check
  check (status = any (array['出勤', '請假', '臨時請假', 'X']));
