-- 把密碼從前端搬到後端。
--
-- 原本 ADMIN_PASSWORD / EXPORT_PASSWORD 是寫在 index.html 裡的字串常數，
-- 也就是每個開過網頁的人都拿得到。看檢視原始碼、存檔、curl 都看得到，
-- 封 F12 完全沒有幫助 —— 頁面送到對方電腦，它就已經是對方的了。
--
-- 改成：密碼只留在這裡（RLS 開著、沒有任何 policy，只有 Edge Function 的
-- service_role 讀得到）。前端把使用者打的字送上去問「對不對」，
-- 後端驗過發一張有期限的通行證，之後的管理操作都要帶著它。

create table if not exists public.app_secrets (
  key        text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);
alter table public.app_secrets enable row level security;


-- 登入失敗次數。四位數密碼只有一萬種組合，沒有這道限制的話，
-- 直接對 API 硬試幾分鐘就會被試出來 —— 搬到後端也擋不住。
create table if not exists public.login_attempts (
  bucket       text primary key,      -- 來源識別（IP）
  fails        int  not null default 0,
  first_fail   timestamptz not null default now(),
  locked_until timestamptz
);
alter table public.login_attempts enable row level security;


-- 種入目前的密碼。salt 與簽章金鑰都用亂數產生，任何人（包括我）都看不到。
insert into public.app_secrets (key, value)
select 'pw_salt', encode(gen_random_bytes(16), 'hex')
where not exists (select 1 from public.app_secrets where key = 'pw_salt');

insert into public.app_secrets (key, value)
select 'token_secret', encode(gen_random_bytes(32), 'hex')
where not exists (select 1 from public.app_secrets where key = 'token_secret');

insert into public.app_secrets (key, value)
select 'pw_admin',
       encode(sha256((( select value from public.app_secrets where key = 'pw_salt') || '1221')::bytea), 'hex')
where not exists (select 1 from public.app_secrets where key = 'pw_admin');

insert into public.app_secrets (key, value)
select 'pw_export',
       encode(sha256((( select value from public.app_secrets where key = 'pw_salt') || '2024')::bytea), 'hex')
where not exists (select 1 from public.app_secrets where key = 'pw_export');


-- 換密碼用這支，不用再改程式碼也不用重新部署
create or replace function public.set_app_password(p_which text, p_new text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_salt text; v_key text;
begin
  if p_which not in ('admin', 'export') then
    return jsonb_build_object('success', false, 'message', '只能是 admin 或 export');
  end if;
  if length(coalesce(p_new, '')) < 4 then
    return jsonb_build_object('success', false, 'message', '密碼至少 4 個字');
  end if;
  select value into v_salt from public.app_secrets where key = 'pw_salt';
  v_key := 'pw_' || p_which;
  update public.app_secrets
     set value = encode(sha256((v_salt || p_new)::bytea), 'hex'), updated_at = now()
   where key = v_key;
  return jsonb_build_object('success', true);
end $$;


-- 登入頻率限制：15 分鐘內失敗 10 次就鎖 15 分鐘。
-- 這樣一萬種組合要試上百小時，硬試就不可行了。
create or replace function public.check_login_rate(p_bucket text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.login_attempts%rowtype;
begin
  select * into r from public.login_attempts where bucket = p_bucket;
  if not found then
    return jsonb_build_object('allowed', true);
  end if;
  if r.locked_until is not null and r.locked_until > now() then
    return jsonb_build_object(
      'allowed', false,
      'retryAfterSec', ceil(extract(epoch from (r.locked_until - now())))::int
    );
  end if;
  -- 鎖已經過期，或上次失敗是很久以前了，重新開始算
  if r.locked_until is not null or r.first_fail < now() - interval '15 minutes' then
    delete from public.login_attempts where bucket = p_bucket;
  end if;
  return jsonb_build_object('allowed', true);
end $$;

create or replace function public.note_login_fail(p_bucket text)
returns void language plpgsql security definer set search_path = public as $$
declare v_fails int;
begin
  insert into public.login_attempts (bucket, fails, first_fail)
  values (p_bucket, 1, now())
  on conflict (bucket) do update set fails = public.login_attempts.fails + 1
  returning fails into v_fails;

  if v_fails >= 10 then
    update public.login_attempts
       set locked_until = now() + interval '15 minutes'
     where bucket = p_bucket;
  end if;
end $$;

create or replace function public.clear_login_fails(p_bucket text)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.login_attempts where bucket = p_bucket;
end $$;

revoke all on function public.set_app_password(text, text) from public, anon, authenticated;
revoke all on function public.check_login_rate(text)       from public, anon, authenticated;
revoke all on function public.note_login_fail(text)        from public, anon, authenticated;
revoke all on function public.clear_login_fails(text)      from public, anon, authenticated;
