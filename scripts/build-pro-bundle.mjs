// 💎 نسخه‌ی «آفلاینِ Pro» مکالمه‌ها: همه‌ی موضوع‌ها در یک فایل → assets/data/pro_conv_bundle.bin
// فقط وقتی استفاده می‌شود که کاربر Pro باشد و سرور/شبکه جواب ندهد (ConversationRepository).
// اجرا (بعد از هر تغییرِ paid-content/*_conversations.json):  node scripts/build-pro-bundle.mjs
// ⚠️ XOR فقط مخفی‌سازیِ ساده است، نه رمزنگاریِ واقعی.
import fs from "node:fs";

const KEY = "lingova-pro-conv-v1";
const KINDS = { daily: "daily_conversations", thematic: "thematic_conversations" };

function topicId(kind, topic) {
  // «(IELTS style)» فقط برچسب است و جزو شناسه نیست (وگرنه همه‌ی موضوع‌های IELTS یک شناسه می‌گیرند)
  const name = topic.replace(/\s*\(IELTS style\)\s*$/i, "");
  const m = name.match(/\(([^)]+)\)/);
  const base = (m ? m[1] : name).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return (kind === "daily" ? "d-" : "t-") + base;
}

const out = {};
for (const [kind, f] of Object.entries(KINDS)) {
  for (const t of JSON.parse(fs.readFileSync(`paid-content/${f}.json`, "utf8"))) {
    const id = topicId(kind, t.topic);
    if (out[id]) throw new Error("duplicate id " + id);
    out[id] = {
      topic: t.topic,
      scenarios: (t.scenarios || []).map((s) => ({
        scenario: s.scenario,
        context: s.context,
        speakerA: (s.speakerA || []).map((l) => ({ en: l.en, level: l.level, ...(l.fa ? { fa: l.fa } : {}) })),
        speakerB: (s.speakerB || []).map((l) => ({ en: l.en, level: l.level, ...(l.fa ? { fa: l.fa } : {}) })),
      })),
    };
  }
}
const buf = Buffer.from(JSON.stringify(out), "utf8");
const k = Buffer.from(KEY);
for (let i = 0; i < buf.length; i++) buf[i] ^= k[i % k.length];
fs.writeFileSync("assets/data/pro_conv_bundle.bin", buf);
console.log("topics:", Object.keys(out).length, "bytes:", buf.length);
