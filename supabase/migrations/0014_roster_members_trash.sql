-- 名單每次存檔都是「整份刪掉再寫入」，刪掉的東西以前沒有任何地方留底。
-- 9/17 22:25 一次送出空白的主名單，69 人整批消失，免費方案又沒有備份可還原。
-- 從現在起每一筆被刪掉的名單列都先抄一份到這裡，保留 60 天。
create table if not exists public.roster_members_trash (
  id          bigserial primary key,
  deleted_at  timestamptz not null default now(),
  txid        bigint not null default txid_current(),
  category    text,
  name        text,
  job         text,
  job2        text,
  sort_order  int
);
alter table public.roster_members_trash enable row level security;
create index if not exists idx_roster_trash_time on public.roster_members_trash (deleted_at desc);

create or replace function public.roster_members_to_trash()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.roster_members_trash (category, name, job, job2, sort_order)
  values (old.category, old.name, old.job, old.job2, old.sort_order);
  delete from public.roster_members_trash where deleted_at < now() - interval '60 days';
  return old;
end $$;

drop trigger if exists trg_roster_members_trash on public.roster_members;
create trigger trg_roster_members_trash
  before delete on public.roster_members
  for each row execute function public.roster_members_to_trash();

revoke all on function public.roster_members_to_trash() from public, anon, authenticated;
