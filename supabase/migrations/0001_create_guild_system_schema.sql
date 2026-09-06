-- 落雨梨花 幫會管理系統
-- 已透過 Supabase MCP 套用到專案 ggjdradkqlsncilqkovd
-- 結構與醉心亭（zxt-signup / 專案 xltdagmzsycnqbflovff）相同

create table public.roster_members (
  id         bigint generated always as identity primary key,
  category   text not null check (category = any (array['member','guest','trial'])),
  name       text not null,
  job        text,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
create index idx_roster_members_cat on public.roster_members (category, sort_order);

create table public.access_requests (
  email        text primary key,
  role_name    text,
  requested_at timestamptz not null default now(),
  status       text not null default '待審核' check (status = any (array['待審核','已核准','已拒絕'])),
  category     text not null default '幫眾'   check (category = any (array['管理','文書','幫眾']))
);

create table public.attendance_records (
  id         bigint generated always as identity primary key,
  date_label text not null,
  name       text not null,
  job        text,
  status     text not null default '出勤' check (status = any (array['出勤','請假','臨時請假'])),
  updated_at timestamptz not null default now(),
  unique (date_label, name)
);
create index idx_attendance_date on public.attendance_records (date_label);

create table public.attendance_deadlines (
  date_label        text primary key,
  deadline_time     text,
  temp_unlock_until bigint
);

create table public.roster_slots (
  id         bigint generated always as identity primary key,
  date_label text not null,
  session    text not null default '1',
  grp        text not null,
  team       text not null,
  slot       text not null,
  name       text,
  job        text,
  note       text,
  updated_at timestamptz not null default now(),
  unique (date_label, session, grp, team, slot)
);
create index idx_roster_slots_key on public.roster_slots (date_label, session);

create table public.roster_commanders (
  id         bigint generated always as identity primary key,
  date_label text not null,
  session    text not null default '1',
  grp        text not null,
  name       text,
  unique (date_label, session, grp)
);

create table public.date_labels (
  label      text primary key,
  created_at timestamptz not null default now()
);

create table public.app_settings (
  key        text primary key,
  value      text,
  updated_at timestamptz not null default now()
);

create table public.activity_log (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  actor_email text,
  actor_role  text,
  description text not null
);
create index idx_activity_log_time on public.activity_log (created_at desc);

create table public.video_uploads (
  id            bigint generated always as identity primary key,
  date_label    text not null,
  name          text not null,
  job           text,
  video_url     text,
  visibility    text not null default 'private' check (visibility = any (array['public','private'])),
  uploaded_at   timestamptz,
  updated_at    timestamptz not null default now(),
  url1          text,
  url2          text,
  uploaded_at1  timestamptz,
  uploaded_at2  timestamptz,
  unique (date_label, name)
);
create index idx_video_uploads_date on public.video_uploads (date_label);

create table public.video_activity_log (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  actor_email text,
  actor_role  text,
  description text not null
);
create index idx_video_activity_time on public.video_activity_log (created_at desc);

-- 全部開 RLS 且刻意不建立任何 policy：
-- 前端一律走 Edge Function，函式用 service_role 連線會繞過 RLS，
-- 拿 anon key 直接打 REST API 的人什麼都讀不到。
alter table public.roster_members       enable row level security;
alter table public.access_requests      enable row level security;
alter table public.attendance_records   enable row level security;
alter table public.attendance_deadlines enable row level security;
alter table public.roster_slots         enable row level security;
alter table public.roster_commanders    enable row level security;
alter table public.date_labels          enable row level security;
alter table public.app_settings         enable row level security;
alter table public.activity_log         enable row level security;
alter table public.video_uploads        enable row level security;
alter table public.video_activity_log   enable row level security;
