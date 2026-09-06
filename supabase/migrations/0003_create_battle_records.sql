-- 戰績紀錄：吃遊戲匯出的 CSV
--
-- 一場戰鬥 = battles 一列 + battle_players 多列（雙方所有人）。
-- 傷害類欄位在匯入時已經除以 10000 換算成「萬」，跟遊戲介面顯示一致。

create table public.battles (
  id           uuid primary key default gen_random_uuid(),
  battle_date  text not null,                       -- 20260504
  battle_time  text not null default '',            -- 185736 或 2156
  my_guild     text not null default '',
  opp_guild    text not null default '',
  battle_type  text not null default '幫戰' check (battle_type = any (array['幫戰','約戰','其他'])),
  my_kills     int  not null default 0,
  opp_kills    int  not null default 0,
  result       text not null default '' check (result = any (array['勝','敗','平',''])),
  -- 選填：對應到出勤系統的日期／場次標籤，之後要做「出勤 × 戰績」才有得接
  date_label   text,
  file_name    text not null default '',
  note         text not null default '',
  created_at   timestamptz not null default now(),
  -- 同一場不要因為重複上傳而變成兩筆
  unique (battle_date, battle_time, my_guild, opp_guild)
);
create index idx_battles_date on public.battles (battle_date desc);

create table public.battle_players (
  id         bigint generated always as identity primary key,
  battle_id  uuid not null references public.battles(id) on delete cascade,
  side       text not null check (side = any (array['my','opp'])),
  guild_name text not null default '',
  name       text not null,
  job        text not null default '',
  kills      int     not null default 0,
  assists    int     not null default 0,
  res        int     not null default 0,   -- 復活
  pvp        numeric not null default 0,   -- PVP 傷害（萬）
  bld        numeric not null default 0,   -- 建築傷害（萬）
  heal       numeric not null default 0,   -- 治療（萬）
  tank       numeric not null default 0,   -- 承傷（萬）
  heavy      int     not null default 0,
  feather    int     not null default 0,
  bone       int     not null default 0
);
create index idx_battle_players_battle on public.battle_players (battle_id);
create index idx_battle_players_name   on public.battle_players (name);

-- 跟其他表一樣：開 RLS 但不給 policy，唯一入口是 Edge Function
alter table public.battles        enable row level security;
alter table public.battle_players enable row level security;
