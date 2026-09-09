-- 二職：一個人除了主職，還能登記一個可以頂替的職業。
--
-- 跟醉心亭（zxt-signup）同一套做法：
--   roster_members.job2  = 這個人的二職，可以留空
--   roster_slots.is_second = 這一格是不是「用二職排上的」
--
-- is_second 看起來可以從 job2 推算出來（主職不是這格職業、但二職是），
-- 為什麼還要存？因為那是「排這一格當下」的事實。之後這個人把二職改掉、
-- 或整個從名單移除，已經排好的歷史排表還是要看得出他當時是用二職上的。

alter table public.roster_members
  add column if not exists job2 text not null default '';

alter table public.roster_slots
  add column if not exists is_second boolean not null default false;
