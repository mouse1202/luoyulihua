-- 戰績加「總進度」與「攻塔進度」四個欄位（我方／敵方各一組）。
--
-- 這四個數字遊戲匯出的 CSV 裡沒有，是打完之後人看著結算畫面自己記的。
-- 以前沒有地方放，所以是借「時間」欄跟「備註」欄塞進去的 ——
-- 例如 10/03 緣心云醉 時間欄寫「57vs41」、備註欄寫「88vs82」。
-- 借來的欄位有別的用途（時間欄會拿去推斷第幾場、備註欄是自由文字），
-- 混在一起遲早會對不上，所以開正式欄位。
--
-- 允許 null：null 代表「還沒填」，跟「填了 0」不一樣。舊資料一律留空，
-- 之後在「修改戰績」裡自己補。CSV 重傳不會動到這四欄 —— saveBattle 的
-- upsert 只會蓋它有送的欄位，沒送的保持原樣。

alter table public.battles
  add column if not exists my_total  int,
  add column if not exists opp_total int,
  add column if not exists my_tower  int,
  add column if not exists opp_tower int;

comment on column public.battles.my_total  is '我方總進度（人工填，null＝還沒填）';
comment on column public.battles.opp_total is '敵方總進度（人工填，null＝還沒填）';
comment on column public.battles.my_tower  is '我方攻塔進度（人工填，null＝還沒填）';
comment on column public.battles.opp_tower is '敵方攻塔進度（人工填，null＝還沒填）';
