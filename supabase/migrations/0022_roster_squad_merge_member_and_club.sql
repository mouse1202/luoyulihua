-- 主名單跟俱樂部合併成一份名單，身分用新的 squad 欄位（身分組）區分。
--
-- 為什麼不是繼續用 category：使用者要的是「一個人身上掛一個身分組」，而且多了
-- 第三種「幫眾&俱樂部」。category 同時扮演「這個人在哪一份名單」跟「他是誰」兩個
-- 角色，硬塞第三種值會讓名單的讀寫（listByCategory / saveByCategory 都是整份覆寫）
-- 變成三份要互相對齊，很容易存壞。拆成兩個欄位之後：
--   category = 這個人在哪一份名單（member / guest / trial）
--   squad    = 身分組（幫眾 / 俱樂部 / 幫眾&俱樂部），只有 member 這份有
--
-- 搬法：先標身分組，再把 club 併進 member。順序不能反 —— 反了就分不出誰原本是俱樂部。
--
-- 出勤紀錄完全不動：attendance_records 是用「名字」存的，跟名單分類無關。
--
-- 對應改動：
--   lylhapi     listByCategory / saveByCategory / getAttendanceCandidates
--               / getRosterAttendeesForDate 都要帶 squad
--   index.html  名單管理合併成一區＋多一欄身分組、出勤系統合併成一區、
--               俱樂部全員調整改成依身分組挑人、排表左欄改成三組

alter table public.roster_members add column if not exists squad text;

update public.roster_members set squad = '俱樂部' where category = 'club';
update public.roster_members set squad = '幫眾'   where category = 'member';
update public.roster_members set category = 'member' where category = 'club';

-- 兩份名單的 sort_order 各自從 0 開始，合併後會撞號，重編一次（幫眾在前、俱樂部在後）
with ord as (
  select id, row_number() over (order by (squad = '俱樂部'), sort_order, id) - 1 as rn
    from public.roster_members where category = 'member')
update public.roster_members m set sort_order = ord.rn from ord where ord.id = m.id;

alter table public.roster_members drop constraint if exists roster_members_squad_check;
alter table public.roster_members add constraint roster_members_squad_check
  check (squad is null or squad = any (array['幫眾', '俱樂部', '幫眾&俱樂部']));
