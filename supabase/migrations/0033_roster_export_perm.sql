-- 排表工具的「匯出為 Google 試算表」補一個權限格子。
--
-- 為什麼要補：這顆按鈕從來沒有進過權限表。程式裡沒帶權限代號的按鈕，
-- openPasswordGate 一律當成「只有管理能用，而且要總管理密碼」—— 寫死的，
-- 權限頁上找不到地方調。結果是：把排表工具開給指揮或文書之後，他進得去、
-- 看得到那顆按鈕，一按卻被擋下來，而你也沒辦法給他。
--
-- 預設照出勤匯出（att_export：管理＋文書），再加指揮 —— 補這一項的起因
-- 就是指揮要用卻給不了。要收回在權限頁上取消勾選就好。
--
-- 注意：這一項只擋得住畫面。排表匯出是在瀏覽器裡產生的（後端那支
-- exportRoster 早就只回一句「改為前端產生」），資料來自「看排表」那幾支
-- 本來就對所有人開放的 API。也就是說，進得去排表工具的人本來就看得到
-- 那些內容，匯出只是幫他排版。真的要連看都不給，要擋的是入口 nav_roster。
-- 這跟 att_club_bulk、vid_upload、bat_view 一樣，是只擋前端的那一類。
--
-- sort_order 放 165：夾在「存排表」160 與「看排表操作記錄」170 中間。

insert into public.role_permissions
  (perm_key, grp, label, admin, clerk, member, club, commander, sort_order) values
  ('roster_export', '排表工具', '匯出排表', true, true, false, false, true, 165)
on conflict (perm_key) do nothing;
