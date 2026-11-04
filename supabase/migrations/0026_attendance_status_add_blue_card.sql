-- 出勤狀態多一個「藍牌」，變成六種：出勤／請假／臨時請假／X／黃牌／藍牌。
--
-- 藍牌 ＝ 人有來、打到一半就消失不見了。
--
-- 跟黃牌的共同點（所以規則整組照抄）：
--   1. 不是本人登記的，是管理／文書記上去的，所以只有這兩種身分設得動。
--   2. 「全員調整」的下拉不放它，也不會被整批覆蓋 —— 這是對個人的紀錄，
--      一次蓋一整組人沒有道理。
--   3. 排表工具不收它：候選名單只收「出勤」，藍牌自動不會被排進格子。
--      （中途消失是事後才知道的事，本來就不是預先排表要考慮的。）
--
-- 跟黃牌不一樣的地方：沒有。出勤率上兩者一樣 —— 算進應出席的分母、
-- 不算出勤，因為那一場他沒打完。
--
-- 一個差別在時間點：中途消失是比賽當下才發生的，常常已經過了調整截止時間，
-- 所以藍牌也要放進 CLERK_LOCKED_ALLOWED，不然鎖表後文書記不上去。
--
-- 同時要改的地方（跟 0023 加黃牌時同一組）：
--   index.html  ATTENDANCE_STATUS_OPTIONS、PRIVILEGED_ONLY_STATUSES、
--               BULK_KEEP_STATUSES、CLERK_LOCKED_ALLOWED、統計多一個「藍牌數」框、
--               .attendance-row-blue 底色、排表的可排人數、出勤率那一頁的欄位與公式
--   index.ts    STATS_MARK（出勤率用的一字元代號）、匯出的 STATUSES
alter table public.attendance_records
  drop constraint if exists attendance_records_status_check;

alter table public.attendance_records
  add constraint attendance_records_status_check
  check (status = any (array['出勤', '請假', '臨時請假', 'X', '黃牌', '藍牌']));
