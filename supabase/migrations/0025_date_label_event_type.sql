/* 場次類型。
   出勤率要能分開看「幫戰的出勤率」跟「俱樂部賽事的出勤率」，不然把
   13 場幫戰跟 8 場俱樂部賽事混在一起算，數字誰都不認。

   以前沒有這一欄，只能靠名稱去猜（名字裡有「幫戰」就算幫戰），但名稱
   是人手打的：0919 那場叫「0919龍虎」沒有「決戰」、1008 那場只寫
   「(俱樂部)」沒寫是約戰還是賽事。猜錯一場，整個類型的出勤率就偏掉。
   所以改成存一欄，建立場次時選一次就固定下來。

   '' ＝ 還沒分類。新建立的場次預設落在這裡，統計頁會把它們列出來提醒，
   不會偷偷算進某一類。
   '不計入' ＝ 不是真的比賽（例如只為了讓人上傳影片而開的場次），
   出勤率一律跳過，但影片、排表那邊照常用得到這個場次。 */
alter table public.date_labels
  add column if not exists event_type text not null default '';

alter table public.date_labels
  drop constraint if exists date_labels_event_type_check;

alter table public.date_labels
  add constraint date_labels_event_type_check
  check (event_type in ('', '幫戰', '龍虎決戰', '幫會約戰', '俱樂部約戰', '俱樂部賽事', '不計入'));

/* 既有 39 場的分類：照名稱判讀，使用者已逐類確認過。
   只在還沒分類（event_type = ''）的時候才寫，之後在網站上改過的不會被蓋回去。 */
update public.date_labels set event_type = '幫戰' where event_type = '' and label in (
  '0905幫戰','0912幫戰','0919幫戰','0926幫戰','1003幫戰','1010幫戰','1017幫戰',
  '1024幫戰','1031幫戰','1107幫戰','1114幫戰','1121幫戰','1128幫戰');

update public.date_labels set event_type = '龍虎決戰' where event_type = '' and label in (
  '0905龍虎決戰','0919龍虎','1003龍虎決戰(俱樂部)','1017龍虎決戰(俱樂部)',
  '1031龍虎決戰(俱樂部)','1114龍虎決戰(俱樂部)','1128龍虎決戰(俱樂部)');

update public.date_labels set event_type = '幫會約戰' where event_type = '' and label in (
  '0910情若初夢(幫會約戰)','0924頂樓風好大(幫會約戰)','1119劍映梨花(幫會約戰)');

/* 後面四場只寫「(俱樂部)」，名字看起來是對手幫會名，使用者確認是約戰。 */
update public.date_labels set event_type = '俱樂部約戰' where event_type = '' and label in (
  '0917驟雨初歇(俱約戰)','1001夏夜淺酌(俱約戰)','1126繁花似錦(俱樂部約戰)',
  '1008星河皓月(俱樂部)','1015醉心亭(俱樂部)','1022劍映梨花(俱樂部)','1029輪迴(俱樂部)');

update public.date_labels set event_type = '俱樂部賽事' where event_type = '' and label in (
  '1002俱樂部體驗賽','1009俱樂部海選賽一','1016俱樂部海選賽二','1018俱樂部海選賽三',
  '1023俱樂部小組賽一','1025俱樂部小組賽二','1030俱樂部小組賽三','1101俱樂部巔峰對決一');

/* 這場不是比賽，是為了讓人上傳影片才開的。 */
update public.date_labels set event_type = '不計入' where event_type = '' and label in (
  '1030小組賽三上傳影片用場次');
