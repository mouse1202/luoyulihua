// 落雨梨花 幫會管理系統 API
//
// 前端（index.html）只認得這一個網址，所有資料存取都從這裡進出。
// 這支函式用 service_role 連資料庫，會繞過 RLS；資料表本身開了 RLS 但沒有任何 policy，
// 所以就算有人拿 anon key 直接打 REST API 也什麼都讀不到。
//
// 對應醉心亭的 zxtapi，差別只有 GUILD_NAME 與擁有者設定。

import { createClient } from "jsr:@supabase/supabase-js@2";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const GUILD_NAME = "落雨梨花";

// 登入識別是「角色名稱」，不是 Gmail。
//
// 擁有者完全寫死在這裡，access_requests 不會有他的資料列：
// 登入直接放行成「管理」，也不會出現在審核申請清單上。
// 這個名字是保留字 —— 別人拿去註冊不會建立紀錄，
// 否則會產生一筆管理員在清單上看不到、也刪不掉的冒名資料。
const OWNER_NAME = "鼠仔丶";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// 角色名稱只去頭尾空白，不轉小寫也不做其他正規化：
// 遊戲 ID 常有「丶」這類字元，動它反而會對不上。
function normName(n: unknown): string {
  return String(n ?? "").trim();
}

async function chk<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<T> {
  const { data, error } = await p;
  if (error) throw new Error(error.message);
  return data;
}

async function appendActivityLog(actorEmail: string, actorRole: string, description: string) {
  await db.from("activity_log").insert({ actor_email: actorEmail || "", actor_role: actorRole || "", description });
  const { data } = await db.from("activity_log").select("id").order("id", { ascending: false }).range(500, 500);
  if (data && data.length > 0) {
    await db.from("activity_log").delete().lte("id", data[0].id);
  }
}

async function appendVideoLog(actorEmail: string, actorRole: string, description: string) {
  await db.from("video_activity_log").insert({ actor_email: actorEmail || "", actor_role: actorRole || "", description });
  const { data } = await db.from("video_activity_log").select("id").order("id", { ascending: false }).range(500, 500);
  if (data && data.length > 0) {
    await db.from("video_activity_log").delete().lte("id", data[0].id);
  }
}

async function listByCategory(category: string) {
  const { data } = await db.from("roster_members").select("name,job").eq("category", category).order("sort_order");
  return (data ?? []).map((r) => ({ name: r.name, job: r.job }));
}
async function saveByCategory(category: string, rows: any[]) {
  await chk(db.from("roster_members").delete().eq("category", category).select("id"));
  const clean = (rows ?? []).filter((r) => r && r.name)
    .map((r, i) => ({ category, name: r.name, job: r.job ?? "", sort_order: i }));
  if (clean.length > 0) await chk(db.from("roster_members").insert(clean).select("id"));
  return { success: true, count: clean.length };
}

async function getAttendanceCandidates() {
  const { data } = await db.from("roster_members").select("name,job,category").order("category").order("sort_order");
  return (data ?? []).map((r) => ({ name: r.name, job: r.job, category: r.category }));
}

async function getAttendanceByDate(date: string) {
  const { data } = await db.from("attendance_records").select("name,job,status").eq("date_label", date);
  return (data ?? []).map((r) => ({ name: r.name, job: r.job, status: r.status }));
}

async function getRosterByDate(date: string, session: string) {
  const { data } = await db.from("roster_slots").select("grp,team,slot,name,job,note")
    .eq("date_label", date).eq("session", String(session)).order("id");
  return (data ?? []).map((r) => ({ group: r.grp, team: r.team, slot: r.slot, name: r.name, job: r.job, note: r.note }));
}
async function getCommandersByDate(date: string, session: string) {
  const { data } = await db.from("roster_commanders").select("grp,name")
    .eq("date_label", date).eq("session", String(session)).order("id");
  return (data ?? []).map((r) => ({ group: r.grp, name: r.name }));
}

async function getAllDateLabels(): Promise<string[]> {
  const labelTime: Record<string, number | null> = {};
  const att = await db.from("attendance_records").select("date_label");
  (att.data ?? []).forEach((r) => { const l = String(r.date_label); if (l && !(l in labelTime)) labelTime[l] = null; });
  const ros = await db.from("roster_slots").select("date_label,updated_at");
  (ros.data ?? []).forEach((r) => {
    const l = String(r.date_label); if (!l) return;
    const t = new Date(r.updated_at).getTime();
    if (!labelTime[l] || (t > (labelTime[l] as number))) labelTime[l] = t;
  });
  const dl = await db.from("date_labels").select("label");
  (dl.data ?? []).forEach((r) => { const l = String(r.label); if (l && !(l in labelTime)) labelTime[l] = null; });
  const labels = Object.keys(labelTime);
  labels.sort((a, b) => {
    const ta = labelTime[a], tb = labelTime[b];
    if (ta && tb) return tb - ta;
    if (ta && !tb) return -1;
    if (!ta && tb) return 1;
    return a < b ? -1 : (a > b ? 1 : 0);
  });
  return labels;
}

function parseMonthFromLabel(label: string): number | null {
  const m = String(label ?? "").match(/^(\d{2})(\d{2})/);
  if (!m) return null;
  const month = parseInt(m[1], 10), day = parseInt(m[2], 10);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return month;
}

const handlers: Record<string, (...a: any[]) => Promise<any> | any> = {
  getMemberList: () => listByCategory("member"),
  saveMemberList: (rows: any[]) => saveByCategory("member", rows),
  getGuestList: () => listByCategory("guest"),
  saveGuestList: (rows: any[]) => saveByCategory("guest", rows),
  getTrialList: () => listByCategory("trial"),
  saveTrialList: (rows: any[]) => saveByCategory("trial", rows),
  getAttendanceCandidates: () => getAttendanceCandidates(),

  checkAccessStatus: async (nameIn: string) => {
    const name = normName(nameIn);
    if (!name) return { name, status: "none", message: "請輸入角色名稱" };
    // 擁有者不查資料庫、也不寫資料庫，直接放行
    if (name === OWNER_NAME) return { name: OWNER_NAME, status: "已核准", category: "管理", isOwner: true };
    const { data } = await db.from("access_requests").select("*").eq("name", name).maybeSingle();
    if (!data) return { name, status: "none" };
    return { name: data.name, status: data.status, category: data.category || "幫眾", isOwner: false };
  },
  submitAccessRequest: async (nameIn: string) => {
    const name = normName(nameIn);
    if (!name) return { success: false, message: "請輸入角色名稱" };
    // 擁有者的名字是保留字，不建立申請紀錄
    if (name === OWNER_NAME) return { success: true, status: "已核准" };
    const now = new Date().toISOString();
    const { data } = await db.from("access_requests").select("status").eq("name", name).maybeSingle();
    if (!data) {
      await chk(db.from("access_requests").insert({ name, requested_at: now, status: "待審核", category: "幫眾" }).select("name"));
      return { success: true, status: "待審核" };
    }
    // 已經有人用這個名字登記過了。已核准就直接放行，
    // 其他狀態視為重新申請（被拒絕過的人可以再送一次）。
    if (data.status === "已核准") return { success: true, status: "已核准" };
    await chk(db.from("access_requests").update({ requested_at: now, status: "待審核" }).eq("name", name).select("name"));
    return { success: true, status: "待審核" };
  },
  addAccessMember: async (nameIn: string, categoryIn: string) => {
    const name = normName(nameIn);
    if (!name) return { success: false, message: "請輸入角色名稱" };
    // 擁有者本來就是最高權限，不需要、也不該被加進清冊
    if (name === OWNER_NAME) return { success: false, message: "這個名字是擁有者，本來就有最高權限" };
    const category = (categoryIn === "管理" || categoryIn === "文書") ? categoryIn : "幫眾";
    const now = new Date().toISOString();
    await chk(db.from("access_requests").upsert({ name, requested_at: now, status: "已核准", category }, { onConflict: "name" }).select("name"));
    return { success: true };
  },
  getAllAccessRequests: async () => {
    const { data } = await db.from("access_requests").select("*").order("requested_at", { ascending: true });
    // 擁有者不列在清冊上。理論上不會有這筆，過濾是為了舊資料。
    return (data ?? []).filter((r) => r.name !== OWNER_NAME).map((r) => ({
      name: r.name, time: r.requested_at ? String(r.requested_at).slice(0, 16).replace("T", " ") : "",
      status: r.status, category: r.category || "幫眾",
    }));
  },
  setAccessRequestStatus: async (nameIn: string, status: string) => {
    const name = normName(nameIn);
    if (name === OWNER_NAME) return { success: false, message: "擁有者不在審核清冊裡，不用也不能改" };
    const { data } = await db.from("access_requests").select("name").eq("name", name).maybeSingle();
    if (!data) return { success: false, message: "找不到這個申請紀錄" };
    await chk(db.from("access_requests").update({ status }).eq("name", name).select("name"));
    return { success: true };
  },
  setAccessRequestCategory: async (nameIn: string, categoryIn: string) => {
    const name = normName(nameIn);
    if (name === OWNER_NAME) return { success: false, message: "不能修改擁有者的類別" };
    const category = (categoryIn === "管理" || categoryIn === "文書") ? categoryIn : "幫眾";
    const { data } = await db.from("access_requests").select("name").eq("name", name).maybeSingle();
    if (!data) return { success: false, message: "找不到這個申請紀錄" };
    await chk(db.from("access_requests").update({ category }).eq("name", name).select("name"));
    return { success: true };
  },
  deleteAccessRequest: async (nameIn: string) => {
    const name = normName(nameIn);
    if (name === OWNER_NAME) return { success: false, message: "不能刪除擁有者" };
    await chk(db.from("access_requests").delete().eq("name", name).select("name"));
    return { success: true };
  },
  purgeRejected: async () => {
    const { data } = await db.from("access_requests").delete().eq("status", "已拒絕").select("name");
    return { success: true, count: data?.length ?? 0 };
  },

  getAttendanceDeadline: async (date: string) => {
    const { data } = await db.from("attendance_deadlines").select("deadline_time").eq("date_label", date).maybeSingle();
    return data?.deadline_time ?? "";
  },
  saveAttendanceDeadlineTime: async (date: string, time: string) => {
    await chk(db.from("attendance_deadlines").upsert({ date_label: date, deadline_time: time }, { onConflict: "date_label" }).select("date_label"));
    return { success: true };
  },
  clearAttendanceDeadlineTime: async (date: string) => {
    await chk(db.from("attendance_deadlines").update({ deadline_time: "" }).eq("date_label", date).select("date_label"));
    return { success: true };
  },
  setAttendanceTempUnlock: async (date: string, durationMinutes: number) => {
    const until = Date.now() + (durationMinutes || 30) * 60 * 1000;
    await chk(db.from("attendance_deadlines").upsert({ date_label: date, temp_unlock_until: until }, { onConflict: "date_label" }).select("date_label"));
    return { success: true, until };
  },
  getAttendanceTempUnlockUntil: async (date: string) => {
    const { data } = await db.from("attendance_deadlines").select("temp_unlock_until").eq("date_label", date).maybeSingle();
    return data?.temp_unlock_until ? Number(data.temp_unlock_until) : 0;
  },

  getAllDateLabels: () => getAllDateLabels(),
  addDateLabel: async (label: string) => {
    const l = String(label ?? "").trim();
    if (!l) return { success: false };
    await chk(db.from("date_labels").upsert({ label: l }, { onConflict: "label" }).select("label"));
    return { success: true };
  },
  getAttendanceByDate: (date: string) => getAttendanceByDate(date),
  getRosterAttendeesForDate: async (date: string) => {
    const records = await getAttendanceByDate(date);
    const statusByName: Record<string, string> = {};
    records.forEach((r) => { statusByName[r.name] = r.status; });
    const cands = await getAttendanceCandidates();
    return cands.filter((c) => (statusByName[c.name] || "出勤") === "出勤")
      .map((c) => ({ name: c.name, job: c.job, category: c.category }));
  },
  saveAttendanceRecord: async (record: any) => {
    const actorLabel = record.actorRoleName || record.actorEmail || "有人";
    const { data: existing } = await db.from("attendance_records").select("status")
      .eq("date_label", record.date).eq("name", record.name).maybeSingle();
    await chk(db.from("attendance_records").upsert(
      { date_label: record.date, name: record.name, job: record.job, status: record.status, updated_at: new Date().toISOString() },
      { onConflict: "date_label,name" },
    ).select("id"));
    if (record.isManual) {
      const oldStatus = existing?.status;
      if (!existing) {
        await appendActivityLog(record.actorEmail, record.actorRoleName,
          `${actorLabel} 把「${record.name}」（${record.date}）的出勤狀態設為「${record.status}」`);
      } else if (oldStatus !== record.status) {
        await appendActivityLog(record.actorEmail, record.actorRoleName,
          `${actorLabel} 把「${record.name}」（${record.date}）的出勤狀態從「${oldStatus || "出勤"}」改成「${record.status}」`);
      }
    }
    return { success: true };
  },
  deleteAllRecordsForDate: async (date: string, actorEmail?: string, actorRoleName?: string) => {
    const a = await db.from("attendance_records").delete().eq("date_label", date).select("id");
    const r = await db.from("roster_slots").delete().eq("date_label", date).select("id");
    const c = await db.from("roster_commanders").delete().eq("date_label", date).select("id");
    await db.from("date_labels").delete().eq("label", date);
    const na = a.data?.length ?? 0, nr = r.data?.length ?? 0, nc = c.data?.length ?? 0;
    const actorLabel = actorRoleName || actorEmail || "有人";
    await appendActivityLog(actorEmail || "", actorRoleName || "",
      `${actorLabel} 刪除了「${date}」的表單（出勤 ${na} 筆、排表 ${nr} 筆、指揮 ${nc} 筆）`);
    return { success: true, attendance: na, roster: nr, commanders: nc };
  },
  renameDateLabel: async (oldDate: string, newDate: string) => {
    if (!oldDate || !newDate) return { success: false, message: "日期不能是空白" };
    if (oldDate === newDate) return { success: true, attendance: 0, roster: 0, commanders: 0 };
    const labels = await getAllDateLabels();
    if (labels.indexOf(newDate) !== -1) return { success: false, message: `「${newDate}」已經是現有的日期/場次標籤，不能重複` };
    const a = await db.from("attendance_records").update({ date_label: newDate }).eq("date_label", oldDate).select("id");
    const r = await db.from("roster_slots").update({ date_label: newDate }).eq("date_label", oldDate).select("id");
    const c = await db.from("roster_commanders").update({ date_label: newDate }).eq("date_label", oldDate).select("id");
    await db.from("date_labels").upsert({ label: newDate }, { onConflict: "label" });
    await db.from("date_labels").delete().eq("label", oldDate);
    return { success: true, attendance: a.data?.length ?? 0, roster: r.data?.length ?? 0, commanders: c.data?.length ?? 0 };
  },

  getActivityLog: async () => {
    const { data } = await db.from("activity_log").select("*").order("id", { ascending: false });
    return (data ?? []).map((r) => ({
      time: r.created_at ? String(r.created_at).slice(0, 19).replace("T", " ") : "",
      actorEmail: r.actor_email, actorRoleName: r.actor_role, description: r.description,
    }));
  },

  saveRoster: async (payload: any) => {
    const date = payload.date;
    const session = String(payload.session || "1");
    const rows = payload.rows || [];
    const commanders = payload.commanders || [];
    const now = new Date().toISOString();
    if (rows.length > 0) {
      await chk(db.from("roster_slots").upsert(
        rows.map((r: any) => ({ date_label: date, session, grp: r.group, team: r.team, slot: r.slot, name: r.name, job: r.job, note: r.note, updated_at: now })),
        { onConflict: "date_label,session,grp,team,slot" },
      ).select("id"));
    }
    if (commanders.length > 0) {
      await chk(db.from("roster_commanders").upsert(
        commanders.map((c: any) => ({ date_label: date, session, grp: c.group, name: c.name })),
        { onConflict: "date_label,session,grp" },
      ).select("id"));
    }
    return { success: true, count: rows.length };
  },
  getRosterByDate: (date: string, session: string) => getRosterByDate(date, session || "1"),
  getCommandersByDate: (date: string, session: string) => getCommandersByDate(date, session || "1"),
  getRosterWithFallback: async (date: string, sessionIn: string) => {
    const session = sessionIn || "1";
    const rows = await getRosterByDate(date, session);
    const hasAny = rows.some((r) => r.name || r.job || r.note);
    if (hasAny) return { rows, commanders: await getCommandersByDate(date, session), copiedFrom: null };
    const { data } = await db.from("roster_slots").select("date_label,updated_at").eq("session", session);
    let best: { date: string; time: number } | null = null;
    (data ?? []).forEach((r) => {
      const d = String(r.date_label);
      if (d === date) return;
      const t = new Date(r.updated_at).getTime();
      if (!best || t > best.time) best = { date: d, time: t };
    });
    if (!best) return { rows, commanders: await getCommandersByDate(date, session), copiedFrom: null };
    return { rows: await getRosterByDate(best.date, session), commanders: await getCommandersByDate(best.date, session), copiedFrom: best.date };
  },

  getAttendanceMonthOptions: async () => {
    const { data } = await db.from("attendance_records").select("date_label");
    const countByMonth: Record<number, number> = {};
    (data ?? []).forEach((r) => {
      const m = parseMonthFromLabel(String(r.date_label));
      if (m === null) return;
      countByMonth[m] = (countByMonth[m] || 0) + 1;
    });
    return Object.keys(countByMonth).map((m) => ({ month: Number(m), count: countByMonth[Number(m)] }))
      .sort((a, b) => a.month - b.month);
  },
  exportAttendanceAll: async (month?: number) => {
    const members = await getAttendanceCandidates();
    const { data } = await db.from("attendance_records").select("date_label,name,status");
    const labelSet: Record<string, boolean> = {};
    const statusMap: Record<string, string> = {};
    (data ?? []).forEach((r) => {
      const label = String(r.date_label);
      if (!label) return;
      if (month && parseMonthFromLabel(label) !== month) return;
      labelSet[label] = true;
      statusMap[label + "|" + r.name] = r.status;
    });
    const labels = Object.keys(labelSet).sort();
    const header = ["姓名", "職業", ...labels, "出勤數", "請假數", "臨時請假數"];
    const lines = [header];
    members.forEach((m) => {
      const row: string[] = [m.name, m.job ?? ""];
      const counts: Record<string, number> = { "出勤": 0, "請假": 0, "臨時請假": 0 };
      labels.forEach((label) => {
        const status = statusMap[label + "|" + m.name] || "出勤";
        row.push(status);
        if (status in counts) counts[status]++;
      });
      row.push(String(counts["出勤"]), String(counts["請假"]), String(counts["臨時請假"]));
      lines.push(row);
    });
    const csv = "﻿" + lines.map((r) => r.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(",")).join("\r\n");
    const filename = `${GUILD_NAME}出勤總表${month ? "_" + month + "月" : ""}.csv`;
    return { success: true, csv, filename };
  },
  exportRoster: (_payload: any) => ({ success: false, message: "排表匯出改為前端產生" }),

  getAnnouncement: async () => {
    const { data } = await db.from("app_settings").select("value").eq("key", "challenge_announcement").maybeSingle();
    return { text: data?.value ?? "" };
  },
  saveAnnouncement: async (text: string) => {
    await chk(db.from("app_settings").upsert(
      { key: "challenge_announcement", value: String(text ?? ""), updated_at: new Date().toISOString() },
      { onConflict: "key" },
    ).select("key"));
    return { success: true };
  },
  getMonthTabs: async () => {
    const { data } = await db.from("app_settings").select("value").eq("key", "month_tabs").maybeSingle();
    if (!data || !data.value) return [];
    try {
      const arr = JSON.parse(data.value);
      return Array.isArray(arr) ? arr.filter((n: any) => typeof n === "number") : [];
    } catch {
      return [];
    }
  },
  saveMonthTabs: async (tabs: number[]) => {
    const clean = Array.isArray(tabs) ? tabs.filter((n) => typeof n === "number") : [];
    await chk(db.from("app_settings").upsert(
      { key: "month_tabs", value: JSON.stringify(clean), updated_at: new Date().toISOString() },
      { onConflict: "key" },
    ).select("key"));
    return { success: true };
  },

  saveVideoReport: async (record: any) => {
    const date = record.date, name = record.name, job = record.job;
    const u1 = String(record.url1 ?? "").trim();
    const u2 = String(record.url2 ?? "").trim();
    const { data: ex } = await db.from("video_uploads").select("url1,url2,uploaded_at1,uploaded_at2")
      .eq("date_label", date).eq("name", name).maybeSingle();
    const now = new Date().toISOString();
    const vis = record.visibility === "public" ? "public" : "private";
    const prev1 = ex?.url1 ?? "", prev2 = ex?.url2 ?? "";
    let t1 = ex?.uploaded_at1 ?? null, t2 = ex?.uploaded_at2 ?? null;
    if (u1) { if (prev1 !== u1 || !t1) t1 = now; } else { t1 = null; }
    if (u2) { if (prev2 !== u2 || !t2) t2 = now; } else { t2 = null; }
    await chk(db.from("video_uploads").upsert(
      { date_label: date, name, job, url1: u1, url2: u2, uploaded_at1: t1, uploaded_at2: t2, visibility: vis, updated_at: now },
      { onConflict: "date_label,name" },
    ).select("id"));
    const actorLabel = record.actorRoleName || record.actorEmail || "有人";
    const parts: string[] = [];
    if (prev1 !== u1) parts.push(u1 ? "第一場" : "清除第一場");
    if (prev2 !== u2) parts.push(u2 ? "第二場" : "清除第二場");
    if (parts.length) {
      await appendVideoLog(record.actorEmail, record.actorRoleName,
        `${actorLabel} 上傳了「${name}」（${date}）的${parts.join("、")}影片`);
    }
    return { success: true, time1: t1 ? String(t1).slice(0, 16).replace("T", " ") : "", time2: t2 ? String(t2).slice(0, 16).replace("T", " ") : "" };
  },
  getMyVideoStatus: async (date: string, name: string) => {
    const { data } = await db.from("video_uploads").select("url1,url2,visibility").eq("date_label", date).eq("name", name).maybeSingle();
    const pub = !!(data && data.visibility === "public");
    return {
      name,
      s1: !!(data && data.url1), s2: !!(data && data.url2),
      isPublic: pub,
      url1: pub && data ? (data.url1 || "") : "",
      url2: pub && data ? (data.url2 || "") : "",
    };
  },
  deleteVideoUrl: async (date: string, name: string, which: number, actorEmail?: string, actorRoleName?: string) => {
    const { data: ex } = await db.from("video_uploads").select("url1,url2").eq("date_label", date).eq("name", name).maybeSingle();
    if (!ex) return { success: false, message: "找不到紀錄" };
    const patch: Record<string, any> = { updated_at: new Date().toISOString() };
    if (Number(which) === 2) { patch.url2 = ""; patch.uploaded_at2 = null; } else { patch.url1 = ""; patch.uploaded_at1 = null; }
    await chk(db.from("video_uploads").update(patch).eq("date_label", date).eq("name", name).select("id"));
    const actorLabel = actorRoleName || actorEmail || "有人";
    const label = Number(which) === 2 ? "第二場" : "第一場";
    await appendVideoLog(actorEmail || "", actorRoleName || "", `${actorLabel} 刪除了「${name}」（${date}）的${label}影片`);
    return { success: true };
  },
  getVideoRoster: async (date: string) => {
    const { data } = await db.from("video_uploads").select("name,job,url1,url2,uploaded_at1,uploaded_at2,visibility").eq("date_label", date);
    return (data ?? []).map((r) => ({
      name: r.name, job: r.job, url1: r.url1 || "", url2: r.url2 || "",
      time1: r.uploaded_at1 ? String(r.uploaded_at1).slice(0, 16).replace("T", " ") : "",
      time2: r.uploaded_at2 ? String(r.uploaded_at2).slice(0, 16).replace("T", " ") : "",
      isPublic: r.visibility === "public",
    }));
  },
  getVideoActivityLog: async () => {
    const { data } = await db.from("video_activity_log").select("*").order("id", { ascending: false });
    return (data ?? []).map((r) => ({
      time: r.created_at ? String(r.created_at).slice(0, 19).replace("T", " ") : "",
      actorEmail: r.actor_email, actorRoleName: r.actor_role, description: r.description,
    }));
  },

  /* ── 戰績 ── */

  // 前端解析完 CSV 之後把整場送過來。同一場重傳會覆蓋，不會變成兩筆。
  saveBattle: async (payload: any) => {
    const date = String(payload.battleDate ?? "").trim();
    if (!date) return { success: false, message: "缺少戰鬥日期" };
    const players = Array.isArray(payload.players) ? payload.players : [];
    if (players.length === 0) return { success: false, message: "這場沒有任何玩家資料" };

    const sum = (side: string, key: string) =>
      players.filter((p: any) => p.side === side)
             .reduce((n: number, p: any) => n + (Number(p[key]) || 0), 0);
    const myKills = Math.round(sum("my", "kills"));
    const oppKills = Math.round(sum("opp", "kills"));

    const [battle] = await chk(db.from("battles").upsert({
      battle_date: date,
      battle_time: String(payload.battleTime ?? "").trim(),
      my_guild:    String(payload.myGuild ?? "").trim(),
      opp_guild:   String(payload.oppGuild ?? "").trim(),
      battle_type: ["幫戰", "約戰", "其他"].includes(payload.battleType) ? payload.battleType : "幫戰",
      my_kills:    myKills,
      opp_kills:   oppKills,
      result:      myKills > oppKills ? "勝" : (myKills < oppKills ? "敗" : "平"),
      date_label:  payload.dateLabel || null,
      file_name:   String(payload.fileName ?? "").trim(),
      note:        String(payload.note ?? "").trim(),
    }, { onConflict: "battle_date,battle_time,my_guild,opp_guild" }).select());

    // 重傳同一場時先清掉舊的名單，避免新舊混在一起
    await db.from("battle_players").delete().eq("battle_id", battle.id);
    await chk(db.from("battle_players").insert(players.map((p: any) => ({
      battle_id: battle.id,
      side: p.side === "opp" ? "opp" : "my",
      guild_name: String(p.guildName ?? "").trim(),
      name: String(p.name ?? "").trim(),
      job: String(p.job ?? "").trim(),
      kills: Math.round(Number(p.kills) || 0),
      assists: Math.round(Number(p.assists) || 0),
      res: Math.round(Number(p.res) || 0),
      pvp: Number(p.pvp) || 0,
      bld: Number(p.bld) || 0,
      heal: Number(p.heal) || 0,
      tank: Number(p.tank) || 0,
      heavy: Math.round(Number(p.heavy) || 0),
      feather: Math.round(Number(p.feather) || 0),
      bone: Math.round(Number(p.bone) || 0),
    }))).select("id"));

    return { success: true, id: battle.id, myKills, oppKills, result: battle.result, players: players.length };
  },

  listBattles: async () => {
    const { data } = await db.from("battles").select("*")
      .order("battle_date", { ascending: false }).order("battle_time", { ascending: false });
    return (data ?? []).map((b) => ({
      id: b.id, date: b.battle_date, time: b.battle_time,
      myGuild: b.my_guild, oppGuild: b.opp_guild, type: b.battle_type,
      myKills: b.my_kills, oppKills: b.opp_kills, result: b.result,
      dateLabel: b.date_label || "", note: b.note, fileName: b.file_name,
    }));
  },

  getBattle: async (id: string) => {
    const { data: b } = await db.from("battles").select("*").eq("id", id).maybeSingle();
    if (!b) return { found: false };
    const { data: ps } = await db.from("battle_players").select("*").eq("battle_id", id);
    // 帶上名單身分，好在戰報上看出誰是自己人、誰是外援或路人
    const { data: roster } = await db.from("roster_members").select("name,category");
    const cat: Record<string, string> = {};
    (roster ?? []).forEach((r) => { cat[r.name] = r.category; });
    return {
      found: true,
      battle: {
        id: b.id, date: b.battle_date, time: b.battle_time,
        myGuild: b.my_guild, oppGuild: b.opp_guild, type: b.battle_type,
        myKills: b.my_kills, oppKills: b.opp_kills, result: b.result,
        dateLabel: b.date_label || "", note: b.note,
      },
      players: (ps ?? []).map((p) => ({
        side: p.side, guildName: p.guild_name, name: p.name, job: p.job,
        kills: p.kills, assists: p.assists, res: p.res,
        pvp: Number(p.pvp), bld: Number(p.bld), heal: Number(p.heal), tank: Number(p.tank),
        heavy: p.heavy, feather: p.feather, bone: p.bone,
        rosterCategory: p.side === "my" ? (cat[p.name] || "") : "",
      })),
    };
  },

  deleteBattle: async (id: string, actorName?: string) => {
    const { data: b } = await db.from("battles").select("battle_date,opp_guild").eq("id", id).maybeSingle();
    await chk(db.from("battles").delete().eq("id", id).select("id"));
    if (b) {
      await appendActivityLog(actorName || "", actorName || "",
        `${actorName || "有人"} 刪除了戰績「${b.battle_date} vs ${b.opp_guild}」`);
    }
    return { success: true };
  },

  // 累積統計：把區間內每個人的場次與各項數據加總，只算我方。
  getBattleAggregate: async (opts: any) => {
    const from = String(opts?.from ?? "").trim();
    const to = String(opts?.to ?? "").trim();
    const type = String(opts?.type ?? "").trim();

    let q = db.from("battles").select("id,battle_date,battle_type");
    if (from) q = q.gte("battle_date", from);
    if (to) q = q.lte("battle_date", to);
    if (type) q = q.eq("battle_type", type);
    const { data: battles } = await q;
    const ids = (battles ?? []).map((b) => b.id);
    if (ids.length === 0) return { battleCount: 0, rows: [] };

    const { data: ps } = await db.from("battle_players").select("*").in("battle_id", ids).eq("side", "my");
    const { data: roster } = await db.from("roster_members").select("name,job,category");
    const cat: Record<string, string> = {};
    (roster ?? []).forEach((r) => { cat[r.name] = r.category; });

    const KEYS = ["kills", "assists", "res", "pvp", "bld", "heal", "tank", "heavy", "feather", "bone"];
    const acc: Record<string, any> = {};
    (ps ?? []).forEach((p) => {
      const a = acc[p.name] ?? (acc[p.name] = {
        name: p.name, job: p.job, games: 0,
        ...Object.fromEntries(KEYS.map((k) => [k, 0])),
      });
      a.games += 1;
      if (p.job) a.job = p.job;
      KEYS.forEach((k) => { a[k] += Number((p as any)[k]) || 0; });
    });

    const rows = Object.values(acc).map((a: any) => {
      const avg: Record<string, number> = {};
      KEYS.forEach((k) => { avg[k] = a.games ? a[k] / a.games : 0; });
      return { ...a, rosterCategory: cat[a.name] || "", avg };
    }).sort((x: any, y: any) => y.games - x.games || y.pvp - x.pvp);

    return { battleCount: ids.length, rows };
  },
};

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
  if (req.method !== "POST") return json({ ok: false, error: "只接受 POST" }, 405);

  let payload: { fn?: string; args?: any[] };
  try { payload = await req.json(); } catch { return json({ ok: false, error: "格式錯誤" }, 400); }
  const fn = payload.fn ?? "";
  const args = Array.isArray(payload.args) ? payload.args : [];
  const handler = handlers[fn];
  if (!handler) return json({ ok: false, error: `未知的函式：${fn}` }, 404);
  try {
    const result = await handler(...args);
    return json({ ok: true, result });
  } catch (e) {
    return json({ ok: false, error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
