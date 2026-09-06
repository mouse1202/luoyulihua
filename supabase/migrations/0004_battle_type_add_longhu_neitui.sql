-- 戰鬥類型：拿掉「其他」，新增「龍虎」與「內推」
-- 套用時現有資料只有幫戰與約戰，沒有任何一列會被新約束擋下

alter table public.battles drop constraint battles_battle_type_check;

alter table public.battles
  add constraint battles_battle_type_check
  check (battle_type = any (array['幫戰','約戰','龍虎','內推']));
