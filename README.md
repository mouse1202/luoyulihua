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
| 擁有者 | `aeddiex111@gmail.com`（角色名 `鼠仔丶`，永遠是「管理」，不能被剔除） |

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
| `access_requests` | 權限申請與審核，分「管理／文書／幫眾」三級 |
| `attendance_records` | 出勤紀錄（出勤／請假／臨時請假） |
| `attendance_deadlines` | 各場次的調整截止時間、臨時解鎖 |
| `roster_slots` | 排表格位（場次／團／隊／位置） |
| `roster_commanders` | 各團指揮 |
| `date_labels` | 日期／場次標籤 |
| `app_settings` | 約戰公告、月份分頁設定 |
| `activity_log` | 操作紀錄（自動保留最新 500 筆） |
| `video_uploads` | 影片回報，每人每場最多兩個連結 |
| `video_activity_log` | 影片操作紀錄（自動保留最新 500 筆） |

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

1. API 指向 `lylhapi`（新專案），不是 `zxtapi`
2. `GUILD_NAME`、標題、訪客驗證視窗的名稱都換成落雨梨花
3. 首頁標語改成「江湖不問來處，落雨只待歸人」
4. localStorage 的 key 由 `zxt_` 改成 `lylh_` —— 這樣同一個瀏覽器同時開兩邊的網站，
   登入狀態不會互相蓋掉

## 待辦

- [ ] 首頁橫幅圖還是醉心亭那張（`index.html` 第 1761 行的 Google Drive 連結），換成落雨梨花自己的
- [ ] 名單是空的，要在「管理名單」裡建立主要成員／外援／試訓
- [ ] 視情況把管理密碼改成跟醉心亭不同的
