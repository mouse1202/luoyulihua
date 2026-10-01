-- 同一場戰績裡出現兩份一模一樣的名單。
--
-- 實例：10/01 約戰 vs 夏夜淺酌（file_name 20261001_212955_橫戈_仗劍.csv）
-- battle_players 有 240 筆、但只有 120 個人，兩份的每一個數字都一樣，
-- id 也分成乾淨的兩段（3451–3570 與 3571–3690）＝ 兩次各自完整的寫入。
--
-- 原因跟名單被存成三份是同一個：saveBattle 是「先把這場的名單刪光，再整份寫入」，
-- 刪與寫是兩個獨立的請求。同一場被連送兩次（按兩下「存進資料庫」、或是送出後
-- 以為沒反應又按一次）就會變成 刪①→刪②→寫①→寫② —— 兩份都留下來。
--
-- 影響的是「人」而不是「場」：battles 的勝敗與擊殺數是從送上來的 payload 算的，
-- 沒有被灌水（my_kills 仍是 315，不是 630）。但累積統計會把那 120 個人各算兩場、
-- 各項數據乘以二，戰報畫面上每個人也會出現兩行。
--
-- 兩道一起補：
--   一、唯一索引 —— 同一場、同一邊、同一個人（含職業）只能有一筆。
--       就算以後還有沒想到的路徑，資料庫這一關過不去。
--   二、save_battle_players() —— 刪與寫包在同一個交易裡，並用 battle_id 上
--       advisory lock。同一場同時被送兩次會排隊，後面那次的刪除會清掉前面那次，
--       最後剛好留一份，不會互相插隊、也不會因為唯一索引而報錯。

create unique index if not exists battle_players_unique_person
  on public.battle_players (battle_id, side, name, job);

create or replace function public.save_battle_players(
  p_battle_id uuid,
  p_rows      jsonb
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  -- 同一場同時被送兩次時序列化。鎖是交易層級的，函式結束就自動放掉。
  perform pg_advisory_xact_lock(hashtextextended(p_battle_id::text, 0));

  delete from public.battle_players where battle_id = p_battle_id;

  insert into public.battle_players (
    battle_id, side, guild_name, name, job,
    kills, assists, res, pvp, bld, heal, tank, heavy, feather, bone
  )
  select
    p_battle_id,
    case when r ->> 'side' = 'opp' then 'opp' else 'my' end,
    coalesce(btrim(r ->> 'guildName'), ''),
    btrim(r ->> 'name'),
    coalesce(btrim(r ->> 'job'), ''),
    round(coalesce((r ->> 'kills')::numeric, 0))::int,
    round(coalesce((r ->> 'assists')::numeric, 0))::int,
    round(coalesce((r ->> 'res')::numeric, 0))::int,
    coalesce((r ->> 'pvp')::numeric, 0),
    coalesce((r ->> 'bld')::numeric, 0),
    coalesce((r ->> 'heal')::numeric, 0),
    coalesce((r ->> 'tank')::numeric, 0),
    round(coalesce((r ->> 'heavy')::numeric, 0))::int,
    round(coalesce((r ->> 'feather')::numeric, 0))::int,
    round(coalesce((r ->> 'bone')::numeric, 0))::int
  from jsonb_array_elements(p_rows) r
  where coalesce(btrim(r ->> 'name'), '') <> '';

  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.save_battle_players(uuid, jsonb)
  from public, anon, authenticated;
