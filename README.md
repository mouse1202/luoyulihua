# 落雨梨花 幫會管理系統

與醉心亭的 [`zxt-signup`](https://github.com/mouse1202/zxt-signup) 同一套架構，換成落雨梨花自己的品牌與資料庫。
兩邊資料完全獨立，互不影響。

## 架構

```
index.html （單檔，含全部 CSS/JS）
     │
     │  POST { fn, args }
     ↓
Supabase Edge Function  lylhapi
     │  用 service_role 連線
     ↓
Postgres（11 張表，全部開 RLS 但不給 policy）
```

前端只認得一個網址，所有資料存取都走 Edge Function。
資料表開了 RLS 但**沒有建立任何 policy**，所以就算有人拿 anon key 直接打 REST API 也什麼都讀不到 ——
唯一的入口是 `lylhapi`，而它用 service_role 連線會繞過 RLS。

| 項目 | 值 |
|---|---|
| Supabase 專案 | `落雨梨花`（`ggjdradkqlsncilqkovd`，新加坡） |
| API 端點 | `https://ggjdradkqlsncilqkovd.supabase.co/functions/v1/lylhapi` |
| 擁有者 | 角色名稱 `鼠仔丶`（永遠是「管理」，不能被剔除或改類別） |

## 檔案

```
index.html                          整個網站（223 KB，無打包步驟）
supabase/functions/lylhapi/index.ts Edge Function 原始碼（44 個 API）
supabase/migrations/                資料表結構
tools/serve.js                      本機預覽用的小型伺服器
```

## 本機預覽

```bash
node tools/serve.js 5174
```

開 <http://localhost:5174>。

## 資料表

| 表 | 內容 |
|---|---|
| `roster_members` | 名單，分 `member`（主要成員）/ `guest`（外援）/ `trial`（試訓） |
| `access_requests` | 權限申請與審核，主鍵是**角色名稱**，分「管理／文書／幫眾」三級 |
| `attendance_records` | 出勤紀錄（出勤／請假／臨時請假） |
| `attendance_deadlines` | 各場次的調整截止時間、臨時解鎖 |
| `roster_slots` | 排表格位（場次／團／隊／位置） |
| `roster_commanders` | 各團指揮 |
| `date_labels` | 日期／場次標籤 |
| `app_settings` | 約戰公告、月份分頁設定 |
| `activity_log` | 操作紀錄（自動保留最新 500 筆） |
| `video_uploads` | 影片回報，每人每場最多兩個連結 |
| `video_activity_log` | 影片操作紀錄（自動保留最新 500 筆） |

## 登入方式

**打角色名稱就能登入，沒有密碼、也不用 Gmail。** 例如 `鼠仔丶`。

- 沒登記過的名字會被導到「註冊」分頁，送出後等管理員在「審核申請」核准
- 核准前一律停在登入彈窗，看不到任何功能
- 登入成功會把名字記在瀏覽器（localStorage 的 `lylh_access_name`），下次自動代入
- 名字只去頭尾空白，不轉大小寫也不做其他正規化 —— 遊戲 ID 常有「丶」這類字元，動它反而會對不上

名字就是身分，所以**同名會撞號**：誰先註冊誰佔用，後來的人得換一個名字或請管理員處理。
沒有密碼也意味著**知道別人角色名稱的人就能冒用身分登入**，這是用名字當帳號的必然代價；
要擋就得加密碼或改回信箱驗證。

### 擁有者

`鼠仔丶` 寫死在 Edge Function 的 `OWNER_NAME`，是內定的最高權限：

- 登入直接放行成「管理」，**完全不碰資料庫** —— `access_requests` 裡沒有他的資料列
- **不會出現在「審核申請」清單上**
- 這個名字是保留字：別人拿去註冊不會建立紀錄，管理員也不能手動把它加進清冊。
  否則會產生一筆你在清單上看不到、卻又刪不掉的冒名資料
- 剔除／改類別／改狀態一律被 API 擋下

要換人就改 `OWNER_NAME` 那一行，然後重新部署 Edge Function。

資料表還留著一個 `email` 欄位，是 Gmail 登入時代的遺物，現在不填也不顯示。

## 權限分級

| 級別 | 能做什麼 |
|---|---|
| 管理 | 輸入總管理密碼後，排表工具／名單管理／審核申請等全部功能 |
| 文書 | 比幫眾多一項：輸入匯出密碼後可匯出出勤紀錄 |
| 幫眾 | 登入後只能開出勤系統改自己的出勤狀態 |

密碼寫在 `index.html` 裡（沿用醉心亭那組）：

```js
var EXPORT_PASSWORD = '0103';   // 只解鎖「出勤匯出」
var ADMIN_PASSWORD  = '1102';   // 總管理密碼
```

**這兩組密碼跟醉心亭是同一組。** 兩邊要分開的話，改這兩行、順便更新第 2114 行說明文字裡寫的數字。

## 修改後怎麼上線

- **改 `index.html`** → `git push`，GitHub Pages 會自動重新部署
- **改 Edge Function** → 改 `supabase/functions/lylhapi/index.ts`，然後在 Supabase 後台或用 CLI 重新部署；
  光是 push 到 GitHub **不會**更新後端

## 跟醉心亭版本的差異

1. **登入改成角色名稱**（醉心亭那邊還是 Gmail），審核申請頁也不再顯示 Gmail 欄位
2. API 指向 `lylhapi`（新專案），不是 `zxtapi`
3. `GUILD_NAME`、標題、訪客驗證視窗的名稱都換成落雨梨花
4. 首頁標語改成「江湖不問來處，落雨只待歸人」；首頁兩顆按鈕靠畫面底部
5. localStorage 的 key 由 `zxt_` 改成 `lylh_` —— 這樣同一個瀏覽器同時開兩邊的網站，
   登入狀態不會互相蓋掉

## 待辦

- [x] 底圖換成落雨梨花主視覺，醉心亭的金字橫幅已移除
- [ ] 名單是空的，要在「管理名單」裡建立主要成員／外援／試訓
- [ ] 視情況把管理密碼改成跟醉心亭不同的
