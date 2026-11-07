const __name = (target) => target; // shim (کدِ باندل‌شده)
// src/transcribe.js
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type"
};
function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...CORS }
  });
}
__name(json, "json");
function toBase64(bytes) {
  let bin = "";
  const CH = 32768;
  for (let i = 0; i < bytes.length; i += CH) {
    bin += String.fromCharCode.apply(null, bytes.subarray(i, i + CH));
  }
  return btoa(bin);
}
__name(toBase64, "toBase64");
function pcmToWav(pcmBytes, sampleRate = 16e3, numChannels = 1, bitsPerSample = 16) {
  const byteRate = sampleRate * numChannels * bitsPerSample / 8;
  const blockAlign = numChannels * bitsPerSample / 8;
  const dataSize = pcmBytes.length;
  const buffer = new ArrayBuffer(44 + dataSize);
  const view = new DataView(buffer);
  const writeString = __name((offset, str) => {
    for (let i = 0; i < str.length; i++)
      view.setUint8(offset + i, str.charCodeAt(i));
  }, "writeString");
  writeString(0, "RIFF");
  view.setUint32(4, 36 + dataSize, true);
  writeString(8, "WAVE");
  writeString(12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, numChannels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, bitsPerSample, true);
  writeString(36, "data");
  view.setUint32(40, dataSize, true);
  const wavBytes = new Uint8Array(buffer);
  wavBytes.set(pcmBytes, 44);
  return wavBytes;
}
__name(pcmToWav, "pcmToWav");
async function handleTranscribe(request, env) {
  if (request.method === "OPTIONS")
    return new Response(null, { status: 204, headers: CORS });
  if (request.method !== "POST")
    return json({ error: "POST only" }, 405);
  try {
    const buf = await request.arrayBuffer();
    if (buf.byteLength < 9600)
      return json({ text: "" });
    if (buf.byteLength > 4 * 1024 * 1024)
      return json({ error: "audio too large" }, 413);
    const pcmBytes = new Uint8Array(buf);
    const wavBytes = pcmToWav(pcmBytes, 16e3, 1, 16);
    const lang = new URL(request.url).searchParams.get("lang");
    const input = {
      audio: toBase64(wavBytes),
      task: "transcribe",
      vad_filter: true
    };
    if (lang && lang !== "auto")
      input.language = lang;
    const out = await env.AI.run("@cf/openai/whisper-large-v3-turbo", input);
    return json({
      text: (out && out.text ? out.text : "").trim(),
      language: out && out.transcription_info ? out.transcription_info.language : void 0
    });
  } catch (e) {
    return json({ error: String(e && e.message ? e.message : e) }, 500);
  }
}
__name(handleTranscribe, "handleTranscribe");

export { handleTranscribe };
