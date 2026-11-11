/* 「已退出」從「把資料刪光」改成「記一筆」。

   原本沒有「已退出」這個狀態，它是推論出來的：名字對照那一頁看一個人
   還剩幾筆出勤＋影片，歸零才算處理完 —— 所以「已退出」按鈕唯一做的事
   就是把出勤與影片刪掉。資料一刪就回不來了，而且影片其實跟排表、戰績
   一樣是已經發生過的歷史。

   現在改成什麼都不刪，只在這張表記下「這個人退了、已經處理過」。
   名字對照那一頁改看這張表，不再看「還剩幾筆」。

   名字就是識別碼（整套系統都是這樣，沒有外鍵），所以 name 直接當主鍵。
   按錯了可以取消（unmarkPlayerLeft 把那一列刪掉）。
   人回來了就重新加進名單，那時他本來就不算「對不上的名字」了，
   這裡留著的那一列不影響任何事。 */

create table if not exists public.left_players (
  name    text primary key,
  left_at timestamptz not null default now(),
  left_by text not null default ''
);

-- 跟其他資料表一樣：開 RLS、不給任何 policy，只有 Edge Function 的
-- service_role 進得來。前端永遠不直接碰資料庫。
alter table public.left_players enable row level security;
