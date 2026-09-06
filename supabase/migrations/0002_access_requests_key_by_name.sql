-- 登入識別從 Gmail 改成角色名稱
-- role_name 升格為主鍵，email 降為選填的歷史欄位（前端不再顯示、也不再要求填寫）

alter table public.access_requests drop constraint access_requests_pkey;
alter table public.access_requests rename column role_name to name;

-- 舊資料若有沒填名字的，用 email 帳號部分補上，避免主鍵建不起來
update public.access_requests
   set name = split_part(email, '@', 1)
 where name is null or btrim(name) = '';

alter table public.access_requests alter column name set not null;
alter table public.access_requests add primary key (name);
alter table public.access_requests alter column email drop not null;
