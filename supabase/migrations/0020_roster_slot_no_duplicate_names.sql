-- 同一天、同一場，一個人只能排一個位置。
--
-- 實際發生過：1017幫戰 第一場，「抹黑丶」同時佔了
--   團一進攻／一隊 第3位（id=14972，龍吟）
--   團一進攻／二隊 第2位（id=14977，龍吟）
-- 兩格都不是二職。等於畫面上 57 格「有人」，實際只有 56 個人，
-- 而那天本來就缺人（109 人裡 16 請假、34 位俱樂部被整批設成 X，可排只有 59），
-- 所以這一筆重複直接讓一個龍吟位空轉。
--
-- 怎麼跑出來的：前端本來就會把排過的人從其他格的選單拿掉，但姓名選單是自訂的
-- 彈出清單，已經打開著的那一份是舊的 —— 另一格同時被選走時這份不會重畫，
-- 還是點得下去。全站歷史只有這一筆，所以是很邊緣的時序問題，不是常態。
--
-- 這一版用「部分唯一索引」擋，但那個做法會誤殺正常的搬動操作，
-- 下一個 migration（0021）會把它換成延遲到 commit 才檢查的 constraint trigger。
-- 這裡留著是因為清資料那段已經跑過了。

-- 先把那一筆清掉，不然索引建不起來。只清第二格的姓名，職業（龍吟）留著，
-- 那一格就回到「空的龍吟位」，要排誰由使用者自己決定。
update public.roster_slots
   set name = '', is_second = false
 where date_label = '1017幫戰'
   and session = '1'
   and grp = '團一進攻'
   and team = '二隊'
   and slot = '2'
   and name = '抹黑丶';

create unique index if not exists roster_slots_one_slot_per_person
  on public.roster_slots (date_label, session, name)
  where name is not null and name <> '';
