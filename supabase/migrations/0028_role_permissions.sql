/* 功能權限分配表。
   一個功能一列，四個身分四個布林欄：管理 / 文書 / 幫眾 / 俱樂部。

   為什麼要有這張表：以前「誰能用什麼」散在兩個地方 —— 後端寫死的
   NEED_LEVEL（admin / export 兩級）跟前端一堆 currentAccessCategory === '管理'。
   要把某一項開放給文書，得改程式再重新部署。現在改成查這張表。

   grp / label 也存在這裡，讓畫面上那張表格直接照資料畫，
   不用前後端各維護一份中文字。但「這個 key 控制畫面上哪顆按鈕」
   還是寫在程式裡 —— 那本來就是程式的事。

   預設值是 2026-11-05 當下的實際行為，一個勾都沒改：
   部署完當天不會有任何人發現差別，要變由總管理自己勾。 */

create table public.role_permissions (
  perm_key   text primary key,
  grp        text not null,
  label      text not null,
  admin      boolean not null default true,   -- 管理
  clerk      boolean not null default false,  -- 文書
  member     boolean not null default false,  -- 幫眾
  club       boolean not null default false,  -- 俱樂部
  sort_order integer not null default 0,
  updated_at timestamptz not null default now()
);

create index role_permissions_sort_idx on public.role_permissions (sort_order);

alter table public.role_permissions enable row level security;

insert into public.role_permissions (perm_key, grp, label, admin, clerk, member, club, sort_order) values
  ('att_card',           '出勤系統', '設黃牌／藍牌',           true,  true,  false, false, 10),
  ('att_after_deadline', '出勤系統', '過了截止時間還能改',     true,  true,  false, false, 20),
  ('att_deadline',       '出勤系統', '設定／清除調整截止時間', true,  false, false, false, 30),
  ('att_temp_unlock',    '出勤系統', '臨時解鎖某一場',         true,  false, false, false, 40),
  ('att_rename_label',   '出勤系統', '重新命名場次',           true,  false, false, false, 50),
  ('att_delete_label',   '出勤系統', '刪除整場紀錄',           true,  false, false, false, 60),
  ('att_event_type',     '出勤系統', '設定場次類型',           true,  false, false, false, 70),
  ('att_club_bulk',      '出勤系統', '俱樂部全員批次調整',     true,  true,  false, false, 80),
  ('att_export',         '出勤系統', '匯出出勤紀錄',           true,  true,  false, false, 90),
  ('att_announce',       '出勤系統', '編輯約戰公告',           true,  true,  false, false, 100),

  ('mem_member',    '名單管理', '存幫眾名單',   true, false, false, false, 110),
  ('mem_guest',     '名單管理', '存外援名單',   true, false, false, false, 120),
  ('mem_trial',     '名單管理', '存試訓名單',   true, false, false, false, 130),
  ('mem_club',      '名單管理', '存俱樂部名單', true, false, false, false, 140),
  ('mem_commander', '名單管理', '存指揮名單',   true, false, false, false, 150),

  ('roster_save', '排表工具', '存排表',         true, false, false, false, 160),
  ('roster_log',  '排表工具', '看排表操作記錄', true, false, false, false, 170),

  ('acc_list',       '審核申請', '看人員清冊',           true, false, false, false, 180),
  ('acc_status',     '審核申請', '核准／拒絕／剔除',     true, false, false, false, 190),
  ('acc_category',   '審核申請', '改某人的類別',         true, false, false, false, 200),
  ('acc_add',        '審核申請', '手動新增成員',         true, false, false, false, 210),
  ('acc_delete',     '審核申請', '刪除申請／清除已拒絕', true, false, false, false, 220),
  ('acc_rename_req', '審核申請', '同意／退回改名申請',   true, false, false, false, 230),

  ('vid_upload', '影片', '上傳自己的影片',   true, true, true,  false, 240),
  ('vid_roster', '影片', '開影片清冊',       true, true, false, false, 250),
  ('vid_log',    '影片', '看影片操作記錄',   true, true, false, false, 260),

  ('bat_view',   '戰績', '看戰績',         true, true,  true,  false, 270),
  ('bat_upload', '戰績', '上傳戰績 CSV',   true, false, false, false, 280),
  ('bat_edit',   '戰績', '修改／刪除戰績', true, false, false, false, 290),

  ('name_view',      '名字對照', '看未對應的名字、曾用名', true, false, false, false, 300),
  ('name_rename',    '名字對照', '幫人改名',               true, false, false, false, 310),
  ('name_left',      '名字對照', '標記已退出',             true, false, false, false, 320),
  ('name_alias_del', '名字對照', '刪除曾用名對照',         true, false, false, false, 330),

  ('log_view', '操作記錄', '看出勤操作記錄', true, false, false, false, 340),

  ('nav_roster', '導覽入口', '排表工具', true, false, false, false, 350),
  ('nav_member', '導覽入口', '管理名單', true, false, false, false, 360),
  ('nav_access', '導覽入口', '審核申請', true, false, false, false, 370),
  ('nav_log',    '導覽入口', '操作記錄', true, false, false, false, 380),
  ('nav_name',   '導覽入口', '名字對照', true, false, false, false, 390),
  ('nav_stats',  '導覽入口', '出勤率',   true, true,  false, false, 400);
