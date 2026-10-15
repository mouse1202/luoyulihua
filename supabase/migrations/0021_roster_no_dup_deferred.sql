-- 0020 用唯一索引擋「同一天同一場同一個人佔兩格」，但那個做法會誤殺正常操作。
--
-- 存檔是一次 upsert 送多列（只送改過的格子）。把某個人從 A 格搬到 B 格時，
-- 送上來的是「B 格＝這個人」跟「A 格＝空白」兩列，而 Postgres 的唯一索引是
-- **逐列檢查**的：如果 B 那一列先被處理，A 格這時候還留著他的名字，當場就撞。
--
-- 實測（已回捲）：
--   insert ... values (二隊2,'抹黑丶'), (一隊3,'') on conflict ...
--   → ERROR 23505 duplicate key ... Key (date_label, session, name)=(1017幫戰, 1, 抹黑丶)
-- 等於往回搬一個人就存不了檔。
--
-- 改成「延遲到 commit 才檢查」的 constraint trigger：那個時間點所有列都已經是
-- 最終狀態，搬動過程中的中間狀態不會被看到，真正的重複還是擋得住，
-- 而且錯誤訊息可以寫清楚是誰、卡在哪兩格（前端會原樣顯示給使用者）。

drop index if exists public.roster_slots_one_slot_per_person;

-- 檢查要查 (date_label, session, name)，給它一個一般索引，不然每改一格都要全表掃
create index if not exists roster_slots_date_session_name
  on public.roster_slots (date_label, session, name);

create or replace function public.roster_slot_no_dup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v record;
begin
  if new.name is null or new.name = '' then return null; end if;

  select grp, team, slot into v
    from public.roster_slots
   where date_label = new.date_label
     and session = new.session
     and name = new.name
     and id <> new.id
   limit 1;

  if found then
    raise exception '「%」在同一場被排了兩個位置（%／% 第 % 位、%／% 第 % 位），同一場不能排同一個人兩次',
      new.name, v.grp, v.team, v.slot, new.grp, new.team, new.slot;
  end if;

  return null;
end $$;

drop trigger if exists roster_slots_no_dup_name on public.roster_slots;

create constraint trigger roster_slots_no_dup_name
  after insert or update on public.roster_slots
  deferrable initially deferred
  for each row execute function public.roster_slot_no_dup();
