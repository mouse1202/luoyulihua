-- 出勤狀態多一個「黃牌」，變成五種：出勤／請假／臨時請假／X／黃牌。
--
-- 跟 0019 加「臨時請假」是同一類改動：放寬 check 約束，舊資料一律不動。
-- （0006 那次是「同一件事換名字」，會改資料；這次不是。）
--
-- 黃牌跟其他四種不一樣的地方：它不是本人登記的，是管理／文書給的處分。
-- 所以前端多兩條規則，資料庫這邊管不到，記在這裡以免以後找不到：
--   1. 只有管理／文書選得動（一般幫眾看得到但是灰色的，才知道自己被記了）
--   2. 「全員調整」的下拉不放黃牌 —— 處分是對個人的，不該一次蓋一整組
--
-- 排表那邊不用改：getRosterAttendeesForDate 本來就只收「出勤」，
-- 黃牌自動不會被排進格子。
--
-- 對應改動：
--   index.html  ATTENDANCE_STATUS_OPTIONS、統計多一個「黃牌數」框、
--               PRIVILEGED_ONLY_STATUSES、CLERK_LOCKED_ALLOWED、
--               updateRosterPoolHint_ 的「不列入」人數
--   lylhapi     exportAttendanceAll 的表頭與計數多一欄

alter table public.attendance_records
  drop constraint attendance_records_status_check;

alter table public.attendance_records
  add constraint attendance_records_status_check
  check (status = any (array['出勤', '請假', '臨時請假', 'X', '黃牌']));
