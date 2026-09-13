-- 戰績要記「這是那一天的第幾場」。
--
-- 本來是從 battle_time 那一欄推出來的（裡面寫「第一場」／「第二場」），
-- 但那一欄本來是給時間用的，格式全看上傳的人怎麼填。0912 那兩場填的是
-- 「29vs62」「52vs35」（擊敗數），結果兩場都被判成第一場，第二場就套到
-- 第一場的排表，有換隊的人全部歸錯隊。
--
-- 改成獨立一欄，空白＝沿用舊的推斷方式。
alter table public.battles add column if not exists session text;

alter table public.battles drop constraint if exists battles_session_check;
alter table public.battles add constraint battles_session_check
  check (session is null or session in ('1', '2'));

comment on column public.battles.session is
  '那一天的第幾場（''1''／''2''），對應 roster_slots.session。空白代表沒指定，由 battle_time 的「第一場／第二場」推斷。';
