/* 登入身分多一個「指揮」，功能權限表跟著多一欄。

   這個「指揮」是登入身分（access_requests.category），
   跟排表工具下拉用的那份「指揮名單」（commander_names）是兩回事 ——
   同名但沒有關聯，一個管的是登入後能用什麼，一個管的是排表選得到誰。

   權限預設全部不給：新欄位 default false，現有 40 列都會是 false。
   要給什麼由總管理自己在「功能權限」那一格勾。

   指揮有自己的密碼（app_secrets 的 pw_commander），跟管理、匯出一樣
   只存雜湊、不寫在程式或 migration 裡，所以不在這個檔案中。 */

alter table public.access_requests drop constraint access_requests_category_check;
alter table public.access_requests
  add constraint access_requests_category_check
  check (category = any (array['管理','文書','幫眾','俱樂部','指揮']));

alter table public.role_permissions
  add column commander boolean not null default false;
