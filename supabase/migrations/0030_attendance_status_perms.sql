/* 出勤類別：出勤／請假／臨時請假／X／藍牌／黃牌 六種各自一項權限。

   原本只有一項「設黃牌／藍牌」（att_card），其他四種是對所有人開放、
   完全沒有權限控管的。現在六種都進權限表，誰能設哪一種由總管理自己調。

   預設值刻意不等於「舊行為」，是 11/05 當天指定的：
     出勤、請假      管理／文書／指揮／幫眾   （俱樂部不給）
     臨時請假、X     管理／文書／指揮         （幫眾、俱樂部不給）
     藍牌、黃牌      管理／文書／指揮         （同上，等於原本的 att_card 再加指揮）
   也就是幫眾從此不能自己登記「臨時請假」「X」，俱樂部一種都不能設。

   sort_order 用 1~6 讓這一組排在最前面：出勤系統那一組已經佔滿 10~100，
   插在中間會把那一組切成兩半（畫面是照 sort_order 掃過去再按 grp 分組的）。

   「設出勤」的幫眾那一格在程式裡鎖著取消不了（PERM_FORCED）——
   勾掉的話全幫都不能自己點出勤，只有知道密碼的人登記得了。 */

delete from public.role_permissions where perm_key = 'att_card';

insert into public.role_permissions
  (perm_key, grp, label, admin, clerk, member, club, commander, sort_order) values
  ('att_st_present', '出勤類別', '設「出勤」',     true, true, true,  false, true, 1),
  ('att_st_leave',   '出勤類別', '設「請假」',     true, true, true,  false, true, 2),
  ('att_st_temp',    '出勤類別', '設「臨時請假」', true, true, false, false, true, 3),
  ('att_st_x',       '出勤類別', '設「X」',        true, true, false, false, true, 4),
  ('att_st_blue',    '出勤類別', '設「藍牌」',     true, true, false, false, true, 5),
  ('att_st_yellow',  '出勤類別', '設「黃牌」',     true, true, false, false, true, 6)
on conflict (perm_key) do nothing;
