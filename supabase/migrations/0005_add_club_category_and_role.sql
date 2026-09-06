-- 名單多一個分類「俱樂部成員」（club），權限多一個身分組「俱樂部」
-- 兩者都是新增，套用時現有資料不受影響

alter table public.roster_members drop constraint roster_members_category_check;
alter table public.roster_members
  add constraint roster_members_category_check
  check (category = any (array['member','guest','trial','club']));

alter table public.access_requests drop constraint access_requests_category_check;
alter table public.access_requests
  add constraint access_requests_category_check
  check (category = any (array['管理','文書','幫眾','俱樂部']));
