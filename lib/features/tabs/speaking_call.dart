import 'dart:async';
import 'dart:convert' show base64Decode, base64Encode;
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:typed_data' show Int32List, Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/native/native_bridge.dart';
import '../../core/providers/speech_provider.dart';
import '../../core/storage/local_storage.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/tts/speech_controller.dart';
import '../../core/tts/speech_state.dart';
import 'photo_talking_face.dart';

// ═══════════════════════════════════════════════════════════════════
// تمرین مکالمه — «شخصیتِ هوش مصنوعی» + «ویدیو کال»
//
//  • AiPersona: هر شخصیت اسم، نقش، حال‌وهوا و سناریوی خودش را دارد
//    (باریستا، مصاحبه‌گر، پزشک، دوست، یا شخصیتی که خودت می‌سازی).
//  • SpeakingCallPanel: تماسِ صوتی/تصویریِ زنده در همان صفحه‌ی چت.
//    صدایت ضبط می‌شود ← با Whisperِ روی گوشی به متن ← شخصیت جواب می‌دهد،
//    اشتباهاتت را اصلاح می‌کند و با صدا حرف می‌زند.
// این فایل مستقل است؛ اتصالش به چت در speaking_tab.dart انجام می‌شود.
// ═══════════════════════════════════════════════════════════════════

String _tr(BuildContext c, String fa, String en) =>
    Localizations.localeOf(c).languageCode == 'fa' ? fa : en;

/// قانون‌های اضافه برای پرامپت وقتی مکالمه «تماس صوتی» است.
const String kCallRules =
    '\nThis is a LIVE VOICE VIDEO CALL. The learner\'s sentence comes from automatic '
    'speech recognition, so IGNORE capitalization, punctuation and tiny spelling '
    'differences — never list those as mistakes; only real grammar, word-choice or '
    'unnatural-phrasing mistakes. Your reply will be read aloud: keep it to 1-3 short '
    'spoken sentences, no emojis, no lists, no stage directions. If there was at least '
    'one FIX line, begin your reply with ONE short, natural spoken sentence in the '
    'target language that gently says the corrected version (the way a friend would), '
    'then continue the conversation in character.\n';

// ───────────────────────────── مدل ─────────────────────────────

class AiPersona {
  final String id;
  final String name;
  final String emoji;

  /// عکسِ دلخواه (برش‌خورده، base64 PNG)؛ خالی = از ایموجی استفاده می‌شود
  final String image;

  /// عکسِ آماده‌ی داخلِ اپ (مثلاً assets/personas/ryan.jpg) که در ویدیو کال تمام‌قاب
  /// نشان داده می‌شود و لب‌هایش حرکت می‌کنند؛ باید در kPhotoFaces ثبت شده باشد.
  final String asset;
  final int color;
  final String role;
  final String roleFa;
  final String personality;
  final String scenario;

  /// 'auto' یا A1..C2
  final String level;
  final bool builtIn;

  const AiPersona({
    required this.id,
    required this.name,
    required this.emoji,
    this.image = '',
    this.asset = '',
    required this.color,
    this.role = '',
    this.roleFa = '',
    this.personality = '',
    this.scenario = '',
    this.level = 'auto',
    this.builtIn = false,
  });

  static const String jimmyId = 'jimmy';

  bool get isDefault => id == jimmyId;

  /// مشخصاتِ عکسِ سخنگو (اگر این شخصیت عکسِ آماده دارد)
  PhotoFaceSpec? get photoFace => asset.isEmpty ? null : kPhotoFaces[asset];
  Color get colorValue => Color(color);

  static String _s(String v) =>
      v.trim().replaceAll(RegExp(r'[\s.]+$'), '').replaceAll('\n', ' ');

  String _character() {
    final b = StringBuffer('You are $name');
    if (_s(role).isNotEmpty) b.write(', ${_s(role)}');
    b.write('.');
    if (_s(personality).isNotEmpty) {
      b.write(' Personality: ${_s(personality)}.');
    }
    if (_s(scenario).isNotEmpty) b.write(' Situation: ${_s(scenario)}.');
    return b.toString();
  }

  String get _levelRule => level == 'auto' || level.isEmpty
      ? ''
      : ' Keep your own vocabulary and grammar at CEFR level $level.';

  /// جمله‌ی اولِ پرامپتِ «معلم + اصلاح». برای Jimmy دقیقاً همان متنِ قبلی.
  String coachIntro(String langLabel) => isDefault
      ? 'You are Jimmy, a friendly patient $langLabel coach.'
      : '${_character()} You are also a friendly, patient $langLabel coach for the '
          'learner: stay in character in the chat part of your reply.$_levelRule';

  /// جمله‌ی اولِ پرامپتِ «ادامه‌ی گفتگو». برای Jimmy دقیقاً همان متنِ قبلی.
  String partnerIntro(String langLabel) => isDefault
      ? 'You are Jimmy, a friendly $langLabel conversation partner.'
      : '${_character()} You are chatting with a $langLabel learner and you stay '
          'in character.$_levelRule';

  String welcomeText(String langName) {
    final r = _s(role);
    return "Hi! I'm $name${r.isEmpty ? '' : ', $r'}. Let's practice $langName "
        'together. Say or write anything to start!';
  }

  AiPersona copyWith({
    String? id,
    String? name,
    String? emoji,
    String? image,
    int? color,
    String? role,
    String? personality,
    String? scenario,
    String? level,
    bool? builtIn,
  }) =>
      AiPersona(
        id: id ?? this.id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        image: image ?? this.image,
        asset: asset,
        color: color ?? this.color,
        role: role ?? this.role,
        roleFa: '',
        personality: personality ?? this.personality,
        scenario: scenario ?? this.scenario,
        level: level ?? this.level,
        builtIn: builtIn ?? this.builtIn,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        if (image.isNotEmpty) 'image': image,
        'color': color,
        'role': role,
        'personality': personality,
        'scenario': scenario,
        'level': level,
      };

  static AiPersona? fromJson(Map<String, dynamic> j) {
    final id = (j['id'] ?? '').toString();
    final name = (j['name'] ?? '').toString().trim();
    if (id.isEmpty || name.isEmpty) return null;
    return AiPersona(
      id: id,
      name: name,
      emoji: (j['emoji'] ?? '🙂').toString(),
      image: (j['image'] ?? '').toString(),
      color: (j['color'] as num?)?.toInt() ?? 0xFF0F766E,
      role: (j['role'] ?? '').toString(),
      personality: (j['personality'] ?? '').toString(),
      scenario: (j['scenario'] ?? '').toString(),
      level: (j['level'] ?? 'auto').toString(),
    );
  }
}

class PersonaStore {
  static const String _key = 'zflut-speaking-personas-v1';

  static const List<AiPersona> builtIns = [
    AiPersona(
      id: AiPersona.jimmyId,
      name: 'Jimmy',
      emoji: '🧑‍🏫',
      color: 0xFF0F766E,
      role: 'your conversation coach',
      roleFa: 'مربی مکالمه‌ی تو',
      builtIn: true,
    ),
    AiPersona(
      id: 'ryan',
      name: 'Ryan',
      emoji: '🧔',
      asset: 'assets/personas/ryan.jpg',
      color: 0xFF1E3A5F,
      role: 'a friendly, easygoing friend on a video call',
      roleFa: 'دوستِ صمیمی در ویدیو کال',
      personality: 'warm, upbeat, curious, speaks naturally like a real friend',
      scenario: 'a relaxed video call catching up about everyday life, work and hobbies',
      builtIn: true,
    ),
    AiPersona(
      id: 'emma',
      name: 'Emma',
      emoji: '👩‍🍳',
      color: 0xFF9A3412,
      role: 'a cheerful barista in a busy coffee shop',
      roleFa: 'باریستای شاد کافه',
      personality: 'warm, chatty, patient with customers',
      scenario: 'the learner is a customer ordering drinks and snacks',
      builtIn: true,
    ),
    AiPersona(
      id: 'daniel',
      name: 'Daniel',
      emoji: '👨‍💼',
      color: 0xFF1E3A8A,
      role: 'a professional but friendly job interviewer',
      roleFa: 'مصاحبه‌گر شغلی',
      personality: 'polite, curious, asks one clear question at a time',
      scenario: 'a job interview where the learner is the candidate',
      builtIn: true,
    ),
    AiPersona(
      id: 'sofia',
      name: 'Sofia',
      emoji: '👩‍💼',
      color: 0xFF7C3AED,
      role: 'a hotel receptionist',
      roleFa: 'مسئول پذیرش هتل',
      personality: 'helpful, calm, very polite',
      scenario: 'the learner is a guest checking in, asking about the room and the city',
      builtIn: true,
    ),
    AiPersona(
      id: 'alex',
      name: 'Alex',
      emoji: '😎',
      color: 0xFF0E7490,
      role: 'a friendly local who just became the learner\'s friend',
      roleFa: 'یک دوستِ صمیمی و خودمونی',
      personality: 'relaxed, funny, uses everyday casual language',
      scenario: 'an easy everyday chat about life, hobbies and plans',
      builtIn: true,
    ),
    AiPersona(
      id: 'drlee',
      name: 'Dr. Lee',
      emoji: '👨‍⚕️',
      color: 0xFFBE123C,
      role: 'a kind family doctor',
      roleFa: 'پزشکِ مهربان',
      personality: 'gentle, reassuring, explains things simply',
      scenario: 'the learner is a patient describing how they feel at a check-up',
      builtIn: true,
    ),
  ];

  static Map<String, dynamic> _read(LocalStorage ls) =>
      Map<String, dynamic>.from(ls.readJson(_key));

  static List<AiPersona> custom(LocalStorage ls) {
    final raw = _read(ls)['items'];
    final out = <AiPersona>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          try {
            final p = AiPersona.fromJson(Map<String, dynamic>.from(e));
            if (p != null) out.add(p);
          } catch (_) {}
        }
      }
    }
    return out;
  }

  static List<AiPersona> all(LocalStorage ls) => [...builtIns, ...custom(ls)];

  static AiPersona byId(LocalStorage ls, String? id) {
    for (final p in all(ls)) {
      if (p.id == id) return p;
    }
    return builtIns.first;
  }

  static String activeId(LocalStorage ls) =>
      (_read(ls)['activeId'] ?? AiPersona.jimmyId).toString();

  static AiPersona active(LocalStorage ls) => byId(ls, activeId(ls));

  static void _write(LocalStorage ls, Map<String, dynamic> m) =>
      unawaited(ls.writeJson(_key, m));

  static void setActive(LocalStorage ls, String id) {
    final m = _read(ls);
    if (m['activeId'] == id) return;
    m['activeId'] = id;
    _write(ls, m);
  }

  static void upsert(LocalStorage ls, AiPersona p) {
    final m = _read(ls);
    final list = custom(ls).where((x) => x.id != p.id).toList()..add(p);
    m['items'] = list.map((x) => x.toJson()).toList();
    _write(ls, m);
  }

  static void remove(LocalStorage ls, String id) {
    final m = _read(ls);
    m['items'] = custom(ls)
        .where((x) => x.id != id)
        .map((x) => x.toJson())
        .toList();
    if (m['activeId'] == id) m['activeId'] = AiPersona.jimmyId;
    _write(ls, m);
  }

  /// شخصیتِ هر مکالمه‌ی ذخیره‌شده در تاریخچه (تا با باز کردنِ تاریخچه همان بماند).
  static String? forSession(LocalStorage ls, String sessionId) {
    final s = _read(ls)['sessions'];
    if (s is Map && s[sessionId] != null) return s[sessionId].toString();
    return null;
  }

  static void setForSession(LocalStorage ls, String sessionId, String pid) {
    if (sessionId.isEmpty || forSession(ls, sessionId) == pid) return;
    final m = _read(ls);
    final s = m['sessions'] is Map
        ? Map<String, dynamic>.from(m['sessions'] as Map)
        : <String, dynamic>{};
    s[sessionId] = pid;
    m['sessions'] = s;
    _write(ls, m);
  }
}

class CallFix {
  final String original;
  final String corrected;
  const CallFix(this.original, this.corrected);
}

class CallTurn {
  /// متنی که شخصیت با صدا می‌گوید
  final String spoken;
  final List<CallFix> fixes;
  const CallTurn(this.spoken, this.fixes);
}

/// متنِ پاسخ بدون خط‌های «N. Instead of …» (برای خواندن با صدا).
String callSpokenBody(String text) => text
    .split('\n')
    .where((l) => !RegExp(r'^\s*\d+\.\s*Instead of\s').hasMatch(l))
    .join('\n')
    .replaceAll(RegExp(r'\s*\n\s*'), ' ')
    .trim();

// ───────────────────────────── نوار شخصیت + حالت ─────────────────────────────

class SpeakingPersonaBar extends StatelessWidget {
  final AiPersona persona;
  final bool callMode;
  final bool busy;
  final VoidCallback onPickPersona;
  final ValueChanged<bool> onModeChanged;

  const SpeakingPersonaBar({
    super.key,
    required this.persona,
    required this.callMode,
    required this.busy,
    required this.onPickPersona,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final role = fa && persona.roleFa.isNotEmpty ? persona.roleFa : persona.role;

    Widget seg(bool call, IconData icon, String label) {
      final active = callMode == call;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: busy ? null : () => onModeChanged(call),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 17, color: active ? c.headerTo : c.inkSoft),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? c.headerTo : c.inkSoft,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── مربی: آواتار + اسم + نقش + تغییر ──
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: busy ? null : onPickPersona,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [c.gold, c.gold.withOpacity(0.35)],
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                              shape: BoxShape.circle, color: c.surface),
                          child: _EmojiAvatar(persona: persona, size: 44),
                        ),
                      ),
                      PositionedDirectional(
                        bottom: 1,
                        end: 1,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: busy
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF22C55E),
                            shape: BoxShape.circle,
                            border: Border.all(color: c.surface, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(persona.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.ink,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800)),
                        if (role.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(role,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: c.inkSoft, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: c.goldSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_horiz_rounded,
                            size: 17, color: c.gold),
                        const SizedBox(width: 3),
                        Icon(Icons.keyboard_arrow_down_rounded,
                            size: 17, color: c.gold),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ── سوئیچِ چت / ویدیو کال با نشانگرِ لغزنده ──
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.paperDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.cardBorder),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: callMode
                        ? AlignmentDirectional.centerEnd
                        : AlignmentDirectional.centerStart,
                    child: FractionallySizedBox(
                      widthFactor: 0.5,
                      heightFactor: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [c.gold, c.gold.withOpacity(0.78)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: c.gold.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    seg(false, Icons.chat_bubble_rounded,
                        _tr(context, 'چت', 'Chat')),
                    seg(true, Icons.videocam_rounded,
                        _tr(context, 'ویدیو کال', 'Call')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final Map<String, Uint8List> _avatarBytesCache = {};

Uint8List? _avatarBytes(String b64) {
  if (b64.isEmpty) return null;
  final hit = _avatarBytesCache[b64];
  if (hit != null) return hit;
  try {
    final b = base64Decode(b64);
    if (_avatarBytesCache.length > 24) _avatarBytesCache.clear();
    _avatarBytesCache[b64] = b;
    return b;
  } catch (_) {
    return null;
  }
}

class _EmojiAvatar extends StatelessWidget {
  final AiPersona persona;
  final double size;
  const _EmojiAvatar({required this.persona, required this.size});

  @override
  Widget build(BuildContext context) {
    final base = persona.colorValue;
    final img = _avatarBytes(persona.image);
    final face = persona.photoFace;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, Colors.black, 0.45)!],
        ),
      ),
      child: face != null
          ? Image.asset(face.avatar,
              width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true)
          : img != null
              ? Image.memory(img,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  gaplessPlayback: true)
              : Text(persona.emoji, style: TextStyle(fontSize: size * 0.52)),
    );
  }
}

/// آیا ایموجی صورت/آدمِ زردرنگ (بدونِ رنگِ پوستِ دیگر) است؟ فقط برای این‌ها دهانِ ثابت پوشانده می‌شود.
bool _yellowFaceEmoji(String e) {
  final r = e.runes.toList();
  if (r.isEmpty) return false;
  for (final c in r) {
    if (c >= 0x1F3FB && c <= 0x1F3FF) return false; // رنگِ پوستِ دیگر
  }
  final c = r.first;
  return (c >= 0x1F600 && c <= 0x1F64F) ||
      (c >= 0x1F910 && c <= 0x1F92F) ||
      (c >= 0x1F466 && c <= 0x1F469) ||
      (c >= 0x1F470 && c <= 0x1F478) ||
      (c >= 0x1F9D1 && c <= 0x1F9DD) ||
      c == 0x1F575 ||
      c == 0x1F9B8 ||
      c == 0x1F9B9;
}

/// شکلِ دهان در یک لحظه: عرض و بازشدگی نسبت به اندازه‌ی آواتار، و میزانِ لبخند (بالا رفتنِ گوشه‌ها).
class _Viseme {
  final double w; // عرض (نسبت از size)
  final double open; // بازشدگی عمودی (نسبت از size)
  final double smile; // لبخند ۰..۱
  const _Viseme(this.w, this.open, this.smile);

  static _Viseme lerp(_Viseme a, _Viseme b, double t) => _Viseme(
        a.w + (b.w - a.w) * t,
        a.open + (b.open - a.open) * t,
        a.smile + (b.smile - a.smile) * t,
      );
}

/// دهانِ متحرک: صورت «ثابت» می‌ماند و فقط یک شکلِ تو‌پُر (دهان) روی محلِ لب‌ها
/// بین حالت‌های لبخند، «او» گرد، باز و «ای» عوض می‌شود تا حالتِ حرف‌زدن بگیرد.
/// برای هر ایموجیِ صورت‌دار و هر عکسی کار می‌کند.
class _TalkingJaw extends StatelessWidget {
  final Widget child;
  final double size;
  final _Viseme? viseme; // null = ساکت (دهانی کشیده نمی‌شود)
  final double split; // محلِ دهان (نسبت از بالا)
  final double scale; // اندازه‌ی دهان نسبت به پیش‌فرض
  // رنگِ پوستِ ایموجی: وقتی داده شود، دهانِ خودِ ایموجی با این رنگ پوشانده می‌شود
  // و فقط دهانِ متحرک دیده می‌شود (لبِ ثابتِ ایموجی زیرش پیدا نباشد)
  final Color? skin;
  const _TalkingJaw({
    required this.child,
    required this.size,
    required this.viseme,
    this.split = 0.64,
    this.scale = 1.0,
    this.skin,
  });

  @override
  Widget build(BuildContext context) {
    final v = viseme;
    if (v == null) return SizedBox(width: size, height: size, child: child);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(child: child),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _MouthPainter(v, split, scale, skin),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MouthPainter extends CustomPainter {
  final _Viseme v;
  final double split;
  final double scale;
  final Color? skin;
  const _MouthPainter(this.v, this.split, this.scale, this.skin);

  @override
  void paint(Canvas canvas, Size size) {
    final box = size.width;
    final cx = box / 2;
    final cy = box * split;
    // پوشاندنِ دهانِ ثابتِ ایموجی با رنگ پوست (لبه‌ی نرم تا لکه دیده نشود)
    if (skin != null) {
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx, cy), width: box * 0.31, height: box * 0.125),
          Paint()
            ..color = skin!
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, box * 0.008));
    }
    final s = box * scale;
    final hw = s * v.w / 2;
    final oh = s * v.open;
    // گوشه‌ها در لبخند بالاتر می‌روند
    final cornerY = cy - s * 0.030 * v.smile;
    final sd = s * 0.020 + s * 0.030 * v.smile; // عمقِ خمِ لب‌ها
    final topCtrl = cornerY + 2 * sd;
    final botCtrl = topCtrl + 2 * oh + s * 0.012;
    final path = Path()
      ..moveTo(cx - hw, cornerY)
      ..quadraticBezierTo(cx, topCtrl, cx + hw, cornerY)
      ..quadraticBezierTo(cx, botCtrl, cx - hw, cornerY)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF4A1414));
    // دندانِ بالا فقط وقتی دهان کمی بازتر است
    if (oh > s * 0.035) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawRect(
          Rect.fromLTWH(cx - hw, cornerY, hw * 2, (topCtrl - cornerY) / 2 + oh * 0.28),
          Paint()..color = Colors.white.withOpacity(0.92));
      canvas.restore();
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF9C3F38)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.012
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_MouthPainter o) =>
      o.v.w != v.w ||
      o.v.open != v.open ||
      o.v.smile != v.smile ||
      o.split != split ||
      o.scale != scale ||
      o.skin != skin;
}

// ═══════════════ دهانِ دقیقِ ایموجی (تحلیلِ پیکسلی) ═══════════════
// ایموجی یک‌بار در یک تصویر رسم می‌شود؛ جای واقعیِ دهانش از روی پیکسل‌ها پیدا و پاک
// می‌شود و دهانِ متحرک دقیقاً همان‌جا، هم‌اندازه و هم‌رنگِ دهانِ اصلی کشیده می‌شود.
// اگر تحلیل ممکن نبود (ایموجیِ غیرانسانی و …) همان روشِ قبلی استفاده می‌شود.

bool _humanFaceEmoji(String e) {
  final r = e.runes.toList();
  if (r.isEmpty) return false;
  final c = r.first;
  return (c >= 0x1F600 && c <= 0x1F64F) ||
      (c >= 0x1F910 && c <= 0x1F92F) ||
      (c >= 0x1F466 && c <= 0x1F469) ||
      (c >= 0x1F470 && c <= 0x1F478) ||
      (c >= 0x1F481 && c <= 0x1F487) ||
      (c >= 0x1F9D1 && c <= 0x1F9DD) ||
      c == 0x1F46E ||
      c == 0x1F575 ||
      c == 0x1F9B8 ||
      c == 0x1F9B9;
}

/// حالتِ دهان در یک لحظه: بازشدگیِ فک، گردیِ لب («او») و لبخند؛ همه ۰..۱
class _Talk {
  final double open;
  final double round;
  final double smile;
  const _Talk(this.open, this.round, this.smile);
  static const _Talk rest = _Talk(0, 0, 0.5);
}

class _EmojiFace {
  final ui.Image image; // ایموجی بدونِ دهان
  final double cx, cy; // مرکزِ دهانِ اصلی (نسبت از ۰ تا ۱)
  final double w; // عرضِ دهانِ اصلی
  final double stroke; // ضخامتِ خطِ لب
  final double depth; // عمقِ خمِ لبخند
  final Color lip;
  const _EmojiFace({
    required this.image,
    required this.cx,
    required this.cy,
    required this.w,
    required this.stroke,
    required this.depth,
    required this.lip,
  });
}

final Map<String, Future<_EmojiFace?>> _emojiFaceCache = {};

Future<_EmojiFace?> _emojiFaceFor(String emoji) =>
    _emojiFaceCache.putIfAbsent(emoji, () => _buildEmojiFace(emoji));

/// برچسب‌گذاریِ اجزای هم‌بندِ یک ماسکِ n×n؛ اندازه‌ی هر جزء (به ترتیبِ برچسب از ۱) در sizes می‌آید.
int _labelCells(Uint8List mask, int n, Int32List lab, List<int> sizes) {
  final stack = Int32List(n * n);
  var id = 0;
  for (var s0 = 0; s0 < n * n; s0++) {
    if (mask[s0] == 0 || lab[s0] != 0) continue;
    id++;
    var sp = 0;
    var size = 0;
    stack[sp++] = s0;
    lab[s0] = id;
    while (sp > 0) {
      final c = stack[--sp];
      size++;
      final x = c % n;
      if (x > 0 && mask[c - 1] != 0 && lab[c - 1] == 0) {
        lab[c - 1] = id;
        stack[sp++] = c - 1;
      }
      if (x < n - 1 && mask[c + 1] != 0 && lab[c + 1] == 0) {
        lab[c + 1] = id;
        stack[sp++] = c + 1;
      }
      if (c >= n && mask[c - n] != 0 && lab[c - n] == 0) {
        lab[c - n] = id;
        stack[sp++] = c - n;
      }
      if (c < n * (n - 1) && mask[c + n] != 0 && lab[c + n] == 0) {
        lab[c + n] = id;
        stack[sp++] = c + n;
      }
    }
    sizes.add(size);
  }
  return id;
}

Future<_EmojiFace?> _buildEmojiFace(String emoji) async {
  try {
    const px = 256; // اندازه‌ی تصویر
    const n = 128; // شبکه‌ی تحلیل (هر خانه ۲×۲ پیکسل)
    const st = 2;

    // ۱) رسمِ ایموجی با همان فونتِ سیستم
    final rec = ui.PictureRecorder();
    final cv = Canvas(rec, Rect.fromLTWH(0, 0, px.toDouble(), px.toDouble()));
    final tp = TextPainter(
      text: TextSpan(
          text: emoji,
          style: const TextStyle(fontSize: px * 0.83, height: 1.0)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(cv, Offset((px - tp.width) / 2, (px - tp.height) / 2));
    final img = await rec.endRecording().toImage(px, px);
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) return null;
    final src = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    int off(int c) => (((c ~/ n) * st) * px + (c % n) * st) * 4;

    // ۲) رنگِ پوست = پرتکرارترین رنگِ گرم و سیر
    final acc = <int, List<int>>{};
    for (var c = 0; c < n * n; c++) {
      final o = off(c);
      if (src[o + 3] < 250) continue;
      final r = src[o], g = src[o + 1], b = src[o + 2];
      final mx = math.max(r, math.max(g, b));
      final mn = math.min(r, math.min(g, b));
      if (mx < 140 || r != mx || g < b) continue;
      final d = mx - mn;
      final sat = d / mx;
      if (sat < 0.25 || sat > 0.85) continue;
      if ((g - b) / d >= 0.84) continue;
      final key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
      final e = acc.putIfAbsent(key, () => [0, 0, 0, 0]);
      e[0]++;
      e[1] += r;
      e[2] += g;
      e[3] += b;
    }
    List<int>? top;
    for (final e in acc.values) {
      if (top == null || e[0] > top[0]) top = e;
    }
    if (top == null || top[0] < 300) return null;
    final sr = top[1] ~/ top[0], sg = top[2] ~/ top[0], sb = top[3] ~/ top[0];

    // ۳) بزرگ‌ترین ناحیه‌ی هم‌رنگِ پوست = صورت
    final skin = Uint8List(n * n);
    for (var c = 0; c < n * n; c++) {
      final o = off(c);
      if (src[o + 3] < 250) continue;
      final dr = src[o] - sr, dg = src[o + 1] - sg, db = src[o + 2] - sb;
      if (dr * dr + dg * dg + db * db < 3600) skin[c] = 1;
    }
    final lab = Int32List(n * n);
    final sizes = <int>[];
    final cn = _labelCells(skin, n, lab, sizes);
    if (cn == 0) return null;
    var bestId = 1;
    for (var k = 1; k <= cn; k++) {
      if (sizes[k - 1] > sizes[bestId - 1]) bestId = k;
    }
    var fx0 = n, fx1 = -1, fy0 = n, fy1 = -1;
    final nonBig = Uint8List(n * n);
    for (var c = 0; c < n * n; c++) {
      if (lab[c] == bestId) {
        final x = c % n, y = c ~/ n;
        if (x < fx0) fx0 = x;
        if (x > fx1) fx1 = x;
        if (y < fy0) fy0 = y;
        if (y > fy1) fy1 = y;
      } else {
        nonBig[c] = 1;
      }
    }
    if (fx1 < 0) return null;
    final fw = fx1 - fx0 + 1, fh = fy1 - fy0 + 1;
    final fcx = (fx0 + fx1) / 2;

    // ۴) حفره‌های داخلِ صورت (چشم، بینی، دهان) = اجزای غیرپوست که به لبه‌ی تصویر نمی‌رسند
    final hl = Int32List(n * n);
    final hs = <int>[];
    final hn = _labelCells(nonBig, n, hl, hs);
    final border = <int>{};
    for (var i = 0; i < n; i++) {
      border.add(hl[i]);
      border.add(hl[(n - 1) * n + i]);
      border.add(hl[i * n]);
      border.add(hl[i * n + n - 1]);
    }
    final area = List<int>.filled(hn + 1, 0);
    final x0s = List<int>.filled(hn + 1, n);
    final x1s = List<int>.filled(hn + 1, -1);
    final y0s = List<int>.filled(hn + 1, n);
    final y1s = List<int>.filled(hn + 1, -1);
    for (var c = 0; c < n * n; c++) {
      final k = hl[c];
      if (k == 0) continue;
      final x = c % n, y = c ~/ n;
      area[k]++;
      if (x < x0s[k]) x0s[k] = x;
      if (x > x1s[k]) x1s[k] = x;
      if (y < y0s[k]) y0s[k] = y;
      if (y > y1s[k]) y1s[k] = y;
    }

    // ۵) دهان = پایین‌ترین حفره‌ی پهن که وسطِ صورت و در نیمه‌ی پایینِ آن است
    var mid = 0;
    var bestY = -1.0;
    for (var k = 1; k <= hn; k++) {
      if (border.contains(k)) continue;
      final cw = x1s[k] - x0s[k] + 1;
      final ccx = (x0s[k] + x1s[k]) / 2;
      final ccy = (y0s[k] + y1s[k]) / 2;
      if (area[k] < 40 || cw < 12) continue;
      if ((ccx - fcx).abs() > fw * 0.18) continue;
      if (ccy < fy0 + fh * 0.45) continue;
      if (ccy > bestY) {
        bestY = ccy;
        mid = k;
      }
    }
    if (mid == 0) return null;
    final mx0 = x0s[mid], mx1 = x1s[mid], my0 = y0s[mid], my1 = y1s[mid];
    final mcw = mx1 - mx0 + 1, mch = my1 - my0 + 1;

    // رنگِ لب: میانگینِ پیکسل‌های تیره‌ی دهان
    var lr = 0, lg = 0, lb = 0, lc = 0;
    for (var c = 0; c < n * n; c++) {
      if (hl[c] != mid) continue;
      final o = off(c);
      if (src[o] + src[o + 1] + src[o + 2] < 450) {
        lr += src[o];
        lg += src[o + 1];
        lb += src[o + 2];
        lc++;
      }
    }
    final lip = lc >= 5
        ? Color.fromARGB(255, lr ~/ lc, lg ~/ lc, lb ~/ lc)
        : const Color(0xFF7A5048);

    // ۶) پاک‌کردنِ دهانِ اصلی (با کمی حاشیه برای لبه‌های نرم)
    final er = Uint8List(n * n);
    for (var y = math.max(0, my0 - 2); y <= math.min(n - 1, my1 + 2); y++) {
      for (var x = math.max(0, mx0 - 2); x <= math.min(n - 1, mx1 + 2); x++) {
        var hit = false;
        for (var dy = -2; dy <= 2 && !hit; dy++) {
          for (var dx = -2; dx <= 2; dx++) {
            final yy = y + dy, xx = x + dx;
            if (yy < 0 || yy >= n || xx < 0 || xx >= n) continue;
            if (hl[yy * n + xx] == mid) {
              hit = true;
              break;
            }
          }
        }
        if (hit) er[y * n + x] = 1;
      }
    }
    final outPx = Uint8List.fromList(src);
    for (var y = 0; y < px; y++) {
      for (var x = 0; x < px; x++) {
        if (er[(y >> 1) * n + (x >> 1)] == 0) continue;
        final o = (y * px + x) * 4;
        outPx[o] = sr;
        outPx[o + 1] = sg;
        outPx[o + 2] = sb;
        outPx[o + 3] = 255;
      }
    }
    final comp = Completer<ui.Image>();
    ui.decodeImageFromPixels(outPx, px, px, ui.PixelFormat.rgba8888, comp.complete);
    final clean = await comp.future;

    final wRatio = mcw / n;
    final stroke = ((area[mid] / (mcw * 1.15)) / n).clamp(0.025, 0.045).toDouble();
    final depth = math.max(0.0, math.min(mch / n - stroke, wRatio * 0.3));
    return _EmojiFace(
      image: clean,
      cx: (mx0 + mx1 + 1) / 2 / n,
      cy: (my0 + my1 + 1) / 2 / n,
      w: wRatio,
      stroke: stroke,
      depth: depth,
      lip: lip,
    );
  } catch (_) {
    return null;
  }
}

/// ایموجی (بدونِ دهان) + دهانِ متحرکِ لبخند/«او»/باز/«ای» دقیقاً روی جای دهانِ اصلی.
class _EmojiFacePainter extends CustomPainter {
  final _EmojiFace f;
  final _Talk t;
  const _EmojiFacePainter(this.f, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width, H = size.height;
    canvas.save();
    // تکانِ خیلی ظریفِ سر هم‌زمان با بازشدنِ دهان
    canvas.translate(0, t.open * W * 0.008);
    canvas.drawImageRect(
      f.image,
      Rect.fromLTWH(0, 0, f.image.width.toDouble(), f.image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.high,
    );

    final cx = f.cx * W, cy = f.cy * H;
    final mw = f.w * W;
    final sw = f.stroke * W;
    final wf = 1 + 0.18 * (t.smile - 0.5) - 0.40 * t.round + 0.08 * t.open;
    final hw = mw * wf / 2;
    final depth = f.depth * W * (0.45 + 1.1 * t.smile) * (1 - 0.7 * t.round);
    final cornerY = cy - depth / 2;
    final upperMid = cy + depth / 2 - t.open * mw * 0.04;
    final openH = mw * 0.62 * t.open;
    final lowerMid = upperMid + openH;

    final lipPaint = Paint()
      ..color = f.lip
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final upper = Path()
      ..moveTo(cx - hw, cornerY)
      ..quadraticBezierTo(cx, 2 * upperMid - cornerY, cx + hw, cornerY);

    if (openH < 0.6) {
      // بسته: فقط یک خطِ لبخند، مثلِ خودِ ایموجی
      canvas.drawPath(upper, lipPaint);
      canvas.restore();
      return;
    }

    final mouth = Path()
      ..moveTo(cx - hw, cornerY)
      ..quadraticBezierTo(cx, 2 * upperMid - cornerY, cx + hw, cornerY)
      ..quadraticBezierTo(cx, 2 * lowerMid - cornerY, cx - hw, cornerY)
      ..close();

    canvas.save();
    canvas.clipPath(mouth);
    canvas.drawPath(
        mouth, Paint()..color = Color.lerp(f.lip, const Color(0xFF1E0A0A), 0.55)!);
    // دندانِ بالا
    if (t.round < 0.7 && openH > mw * 0.10) {
      canvas.drawRect(
          Rect.fromLTRB(cx - hw, cornerY - 2, cx + hw, upperMid + openH * 0.30),
          Paint()..color = Colors.white.withOpacity(0.95));
    }
    // زبان
    if (openH > mw * 0.22) {
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx, lowerMid - openH * 0.18),
              width: hw * 1.2,
              height: openH * 0.55),
          Paint()..color = const Color(0xFFE0675D));
    }
    canvas.restore();
    canvas.drawPath(mouth, lipPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EmojiFacePainter o) =>
      o.f != f ||
      o.t.open != t.open ||
      o.t.round != t.round ||
      o.t.smile != t.smile;
}

class _EmojiTalkingFace extends StatefulWidget {
  final String emoji;
  final double size;
  final _Talk? talk; // null = ساکت
  final Widget fallback; // روشِ قبلی؛ وقتی تحلیلِ ایموجی ممکن نبود
  const _EmojiTalkingFace({
    required this.emoji,
    required this.size,
    required this.talk,
    required this.fallback,
  });

  @override
  State<_EmojiTalkingFace> createState() => _EmojiTalkingFaceState();
}

class _EmojiTalkingFaceState extends State<_EmojiTalkingFace> {
  _EmojiFace? _face;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_EmojiTalkingFace old) {
    super.didUpdateWidget(old);
    if (old.emoji != widget.emoji) {
      _face = null;
      _load();
    }
  }

  Future<void> _load() async {
    final e = widget.emoji;
    final f = _humanFaceEmoji(e) ? await _emojiFaceFor(e) : null;
    if (!mounted || e != widget.emoji) return;
    setState(() => _face = f);
  }

  @override
  Widget build(BuildContext context) {
    final f = _face;
    if (f == null) return widget.fallback;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _EmojiFacePainter(f, widget.talk ?? _Talk.rest),
      ),
    );
  }
}

/// انتخابِ عکس از گالری + برشِ دایره‌ای (جابه‌جا و زوم کن). خروجی: PNG با فرمتِ base64 یا null.
Future<String?> _pickPersonaPhoto(BuildContext context) async {
  Uint8List? bytes;
  try {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    bytes = res?.files.isEmpty ?? true ? null : res!.files.first.bytes;
  } catch (_) {
    bytes = null;
  }
  if (bytes == null || !context.mounted) return null;
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AvatarCropDialog(bytes: bytes!),
  );
}

class _AvatarCropDialog extends StatefulWidget {
  final Uint8List bytes;
  const _AvatarCropDialog({required this.bytes});

  @override
  State<_AvatarCropDialog> createState() => _AvatarCropDialogState();
}

class _AvatarCropDialogState extends State<_AvatarCropDialog> {
  static const double _vp = 280;
  static const int _out = 192;
  final GlobalKey _key = GlobalKey();
  final TransformationController _tc = TransformationController();
  double? _w, _h;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final im = await decodeImageFromList(widget.bytes);
      final w = im.width.toDouble(), h = im.height.toDouble();
      im.dispose();
      final k = _vp / math.min(w, h);
      _tc.value = Matrix4.translationValues(
          -(w * k - _vp) / 2, -(h * k - _vp) / 2, 0);
      if (mounted) setState(() {
            _w = w;
            _h = h;
          });
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final b = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final im = await b.toImage(pixelRatio: _out / _vp);
      final bd = await im.toByteData(format: ui.ImageByteFormat.png);
      im.dispose();
      if (!mounted) return;
      Navigator.of(context)
          .pop(bd == null ? null : base64Encode(bd.buffer.asUint8List()));
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final w = _w, h = _h;
    Widget body;
    if (w == null || h == null) {
      body = const SizedBox(
          width: _vp,
          height: _vp,
          child: Center(child: CircularProgressIndicator()));
    } else {
      final k = _vp / math.min(w, h);
      final cw = w * k, ch = h * k;
      body = SizedBox(
        width: _vp,
        height: _vp,
        child: Stack(
          children: [
            RepaintBoundary(
              key: _key,
              child: ClipRect(
                child: SizedBox(
                  width: _vp,
                  height: _vp,
                  child: InteractiveViewer(
                    transformationController: _tc,
                    constrained: false,
                    minScale: 1,
                    maxScale: 6,
                    boundaryMargin: EdgeInsets.zero,
                    child: SizedBox(
                      width: cw,
                      height: ch,
                      child: Image.memory(
                        widget.bytes,
                        fit: BoxFit.fill,
                        cacheWidth: w <= h
                            ? math.min(w, 1200).round()
                            : null,
                        cacheHeight: h < w
                            ? math.min(h, 1200).round()
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const IgnorePointer(
              child: CustomPaint(
                size: Size(_vp, _vp),
                painter: _CropMaskPainter(),
              ),
            ),
          ],
        ),
      );
    }
    return Dialog(
      backgroundColor: c.paper,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_tr(context, 'عکس را جابه‌جا و زوم کن', 'Move and zoom the photo'),
                style: TextStyle(
                    color: c.ink, fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            body,
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(_tr(context, 'لغو', 'Cancel')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: (w == null || _busy) ? null : _done,
                    child: Text(_tr(context, 'تأیید', 'OK')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CropMaskPainter extends CustomPainter {
  const _CropMaskPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = Path()..addOval(rect.deflate(2));
    final mask = Path.combine(
        PathOperation.difference, Path()..addRect(rect), circle);
    canvas.drawPath(mask, Paint()..color = const Color(0x99000000));
    canvas.drawPath(
        circle,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_CropMaskPainter o) => false;
}

// ───────────────────────────── انتخاب / ساخت شخصیت ─────────────────────────────

/// شناسه‌ی شخصیتِ انتخاب‌شده را برمی‌گرداند (یا null اگر فقط بسته شد).
Future<String?> showPersonaSheet(
    BuildContext context, LocalStorage ls, String activeId) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PersonaSheet(ls: ls, activeId: activeId),
  );
}

class _PersonaSheet extends StatefulWidget {
  final LocalStorage ls;
  final String activeId;
  const _PersonaSheet({required this.ls, required this.activeId});

  @override
  State<_PersonaSheet> createState() => _PersonaSheetState();
}

class _PersonaSheetState extends State<_PersonaSheet> {
  Future<void> _edit(AiPersona? initial) async {
    final res = await showModalBottomSheet<AiPersona>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PersonaEditor(initial: initial),
    );
    if (res == null || !mounted) return;
    PersonaStore.upsert(widget.ls, res);
    setState(() {});
  }

  void _delete(AiPersona p) {
    PersonaStore.remove(widget.ls, p.id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final list = PersonaStore.all(widget.ls);
    final h = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: h * 0.86),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: c.cardBorder,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _tr(context, 'با چه کسی صحبت کنم؟', 'Who do you want to talk to?'),
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: c.inkSoft),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: [
                  for (final p in list)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: p.id == widget.activeId
                              ? c.gold
                              : c.cardBorder,
                          width: p.id == widget.activeId ? 2 : 1,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(context).pop(p.id),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              _EmojiAvatar(persona: p, size: 44),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name,
                                        style: TextStyle(
                                            color: c.ink,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800)),
                                    Text(
                                      fa && p.roleFa.isNotEmpty
                                          ? p.roleFa
                                          : p.role,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: c.inkSoft, fontSize: 11.5),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: p.builtIn
                                    ? _tr(context, 'کپی و ویرایش', 'Copy & edit')
                                    : _tr(context, 'ویرایش', 'Edit'),
                                onPressed: () => _edit(p.builtIn
                                    ? p.copyWith(
                                        id: 'p${DateTime.now().microsecondsSinceEpoch}',
                                        builtIn: false,
                                        role: p.role,
                                      )
                                    : p),
                                icon: Icon(
                                    p.builtIn
                                        ? Icons.copy_outlined
                                        : Icons.edit_outlined,
                                    size: 18,
                                    color: c.teal),
                              ),
                              if (!p.builtIn)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: _tr(context, 'حذف', 'Delete'),
                                  onPressed: () => _delete(p),
                                  icon: Icon(Icons.delete_outline,
                                      size: 18, color: c.rose),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _edit(null),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(_tr(context, 'ساختِ شخصیتِ جدید', 'Create a new persona')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonaEditor extends StatefulWidget {
  final AiPersona? initial;
  const _PersonaEditor({this.initial});

  @override
  State<_PersonaEditor> createState() => _PersonaEditorState();
}

class _PersonaEditorState extends State<_PersonaEditor> {
  static const _emojis = [
    '🧑‍🏫', '👩‍🍳', '👨‍💼', '👩‍💼', '😎', '👨‍⚕️', '👩‍⚕️', '🧑‍✈️', '👩‍🎤', '🎓', '🧙', '🤖', '🐱', '🎤',
    '🙂', '😀', '😄', '🥰', '🤓', '🧐', '🤠', '🥳', '😇', '🤩', '👩‍💼', '👨‍💼', '👩‍🏫', '👨‍🍳',
    '👮', '👷', '🧑‍🚀', '🧑‍🎨', '🧑‍🔧', '🧑‍⚕️', '🦸', '🧛', '🧚', '🧞', '👽', '👻', '🐶', '🦊',
    '🐼', '🦁', '🐯', '🐸', '🐵', '🦄', '🐧', '🦉', '🐰', '🐻', '👨‍🎓', '👩‍🎓',
  ];
  static const _colors = [
    0xFF0F766E, 0xFF9A3412, 0xFF1E3A8A, 0xFF7C3AED, 0xFF0E7490, 0xFFBE123C,
    0xFF166534, 0xFF92400E,
  ];
  static const _levels = ['auto', 'A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  late final TextEditingController _name;
  late final TextEditingController _role;
  late final TextEditingController _personality;
  late final TextEditingController _scenario;
  late String _emoji;
  String _image = '';
  late final TextEditingController _emojiCtl;
  late int _color;
  late String _level;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _name = TextEditingController(text: p?.name ?? '');
    _role = TextEditingController(text: p?.role ?? '');
    _personality = TextEditingController(text: p?.personality ?? '');
    _scenario = TextEditingController(text: p?.scenario ?? '');
    _emoji = p?.emoji ?? '🙂';
    _image = p?.image ?? '';
    _emojiCtl = TextEditingController(text: _emoji);
    _color = p?.color ?? _colors.first;
    _level = p?.level ?? 'auto';
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _personality.dispose();
    _scenario.dispose();
    _emojiCtl.dispose();
    super.dispose();
  }

  void _setEmoji(String e) {
    _emoji = e;
    _emojiCtl.value = TextEditingValue(
      text: e,
      selection: TextSelection.collapsed(offset: e.length),
    );
  }

  /// هر ایموجیِ دلخواه از کیبورد: همیشه آخرین ایموجیِ تایپ‌شده می‌ماند
  void _onEmojiTyped(String v) {
    if (v.isEmpty) return;
    final last = v.characters.last.toString();
    if (RegExp(r'^[A-Za-z0-9\s]').hasMatch(last)) {
      setState(() => _setEmoji(_emoji));
      return;
    }
    setState(() => _setEmoji(last));
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final base = widget.initial;
    Navigator.of(context).pop(AiPersona(
      id: (base != null && !base.builtIn)
          ? base.id
          : 'p${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      emoji: _emoji,
      image: _image,
      color: _color,
      role: _role.text.trim(),
      personality: _personality.text.trim(),
      scenario: _scenario.text.trim(),
      level: _level,
    ));
  }

  Widget _field(AppThemeColorsExt c, TextEditingController ctl, String label,
      String hint,
      {int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctl,
        minLines: lines,
        maxLines: lines + 1,
        onChanged: (_) => setState(() {}),
        style: TextStyle(color: c.ink, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: c.inkSoft.withOpacity(0.55), fontSize: 12),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.cardBorder),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final preview = AiPersona(
        id: 'x', name: _name.text, emoji: _emoji, image: _image, color: _color);
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: BoxDecoration(
          color: c.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              Row(
                children: [
                  _EmojiAvatar(persona: preview, size: 46),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.initial == null
                          ? _tr(context, 'شخصیتِ جدید', 'New persona')
                          : _tr(context, 'ویرایشِ شخصیت', 'Edit persona'),
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _field(c, _name, _tr(context, 'اسم', 'Name'), 'Emma'),
              _field(
                c,
                _role,
                _tr(context, 'نقش (به انگلیسی بهتره)', 'Role'),
                'a friendly waiter in an Italian restaurant',
              ),
              _field(
                c,
                _personality,
                _tr(context, 'شخصیت و لحن', 'Personality & tone'),
                'funny, patient, speaks slowly',
              ),
              _field(
                c,
                _scenario,
                _tr(context, 'موقعیتِ مکالمه', 'Situation'),
                'I am a tourist ordering dinner',
                lines: 2,
              ),
              Text(_tr(context, 'عکس (اختیاری)', 'Photo (optional)'),
                  style: TextStyle(color: c.inkSoft, fontSize: 12)),
              const SizedBox(height: 6),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final r = await _pickPersonaPhoto(context);
                      if (r != null && mounted) setState(() => _image = r);
                    },
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: Text(_tr(context, 'انتخاب از گالری', 'Pick from gallery')),
                  ),
                  if (_image.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => setState(() => _image = ''),
                      child: Text(_tr(context, 'حذف عکس', 'Remove')),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(_tr(context, 'ایموجی', 'Avatar'),
                  style: TextStyle(color: c.inkSoft, fontSize: 12)),
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SizedBox(
                  width: 84,
                  child: TextField(
                    controller: _emojiCtl,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 30),
                    onChanged: _onEmojiTyped,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: c.gold, width: 2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: c.gold, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in _emojis)
                    GestureDetector(
                      onTap: () => setState(() => _setEmoji(e)),
                      child: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _emoji == e ? c.gold : c.cardBorder,
                            width: _emoji == e ? 2 : 1,
                          ),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(_tr(context, 'رنگ', 'Color'),
                  style: TextStyle(color: c.inkSoft, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final col in _colors)
                    GestureDetector(
                      onTap: () => setState(() => _color = col),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(col),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == col ? c.ink : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(_tr(context, 'سطحِ زبانِ شخصیت', 'Language level'),
                  style: TextStyle(color: c.inkSoft, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final l in _levels)
                    ChoiceChip(
                      label: Text(
                        l == 'auto' ? _tr(context, 'خودکار', 'Auto') : l,
                        style: TextStyle(
                            fontSize: 12,
                            color: _level == l ? c.headerTo : c.ink),
                      ),
                      selected: _level == l,
                      selectedColor: c.gold,
                      backgroundColor: Colors.white,
                      onSelected: (_) => setState(() => _level = l),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(_tr(context, 'انصراف', 'Cancel')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.teal,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _name.text.trim().isEmpty ? null : _save,
                      child: Text(_tr(context, 'ذخیره', 'Save')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── پنلِ ویدیو کال ─────────────────────────────

enum _Phase { ringing, ready, recording, transcribing, thinking, speaking, error }

class SpeakingCallPanel extends ConsumerStatefulWidget {
  final AiPersona persona;

  /// زبانِ تمرین (کدِ دو حرفی) و نامِ انگلیسی‌اش
  final String langCode;
  final String langName;

  /// بعد از «وصل شدن»؛ متنِ سلامِ شخصیت (یا null)
  final Future<String?> Function() onConnected;

  /// جملهٔ کاربر → پاسخ + اصلاحات. [retry] = تلاشِ دوباره برای همان پیامِ ناموفق.
  final Future<CallTurn?> Function(String text, bool retry) onUserSaid;
  final VoidCallback onEnd;

  const SpeakingCallPanel({
    super.key,
    required this.persona,
    required this.langCode,
    required this.langName,
    required this.onConnected,
    required this.onUserSaid,
    required this.onEnd,
  });

  @override
  ConsumerState<SpeakingCallPanel> createState() => _SpeakingCallPanelState();
}

class _SpeakingCallPanelState extends ConsumerState<SpeakingCallPanel>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final AudioRecorder _rec = AudioRecorder();
  final ValueNotifier<double> _level = ValueNotifier<double>(0);
  final TextEditingController _typeCtl = TextEditingController();
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();
  late final SpeechController _ctl =
      ref.read(speechControllerProvider.notifier);

  _Phase _phase = _Phase.ringing;
  // سطحِ صدا را خودمان با تایمر می‌خوانیم (onAmplitudeChanged در بعضی نسخه‌ها
  // استریمِ تک‌مشترک می‌دهد و بار دوم «Stream has already been listened to» می‌داد)
  Timer? _ampSub;
  StreamSubscription<NativeEvent>? _dlSub;
  Timer? _clock;
  int _secs = 0;
  int _turn = 0; // هر بار که «نوبت» عوض می‌شود زیاد می‌شود (قطعِ حرفِ AI)
  bool _closed = false;
  bool _stopping = false;

  bool _handsFree = true;
  bool _muted = false;
  bool _showTyping = false;

  String _aiLine = '';
  String _heard = '';
  String _lastText = '';
  List<CallFix> _fixes = const [];
  String _info = '';
  String _error = '';
  String? _recPath;
  int _speechFrames = 0;
  int _silentFrames = 0;
  int _recFrames = 0;

  bool _needModel = false;
  bool _dlRunning = false;
  double _dlFrac = 0;
  int _approxMb = 0;
  int _prevRepeatCycles = 0;
  int? _prevRepeatCustom; // تعدادِ تکرارِ دلخواهِ کاربر (خارج از چرخه‌ی ۲/۳/∞)

  bool get _sttSupported => !kIsWeb && NativeBridge.instance.isSupported;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _neutralizeRepeat();
    _showTyping = !_sttSupported;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _phase != _Phase.ringing) setState(() => _secs++);
    });
    unawaited(_connect());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // برنامه به پس‌زمینه رفت → تماس قطع (میکروفون روشن نمی‌ماند)
    if (state == AppLifecycleState.paused && !_closed) widget.onEnd();
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _ampSub?.cancel();
    _dlSub?.cancel();
    _pulse.dispose();
    _level.dispose();
    _typeCtl.dispose();
    unawaited(_rec.dispose());
    _deleteFile(_recPath);
    try {
      _ctl.stop();
    } catch (_) {}
    _restoreRepeat();
    if (_phase == _Phase.transcribing) {
      unawaited(NativeBridge.instance.syncTranscribeCancel().catchError(
          (Object _) => <String, dynamic>{}));
    }
    super.dispose();
  }

  // ───────────── پخشِ صدا (تکرارِ پلیر خاموش می‌شود تا جواب‌ها تکرار نشوند) ─────────────
  static const List<int> _repeatOrder = [0, 2, 3, -1];

  void _neutralizeRepeat() {
    try {
      final cur = ref.read(speechControllerProvider).globalRepeat;
      final idx = _repeatOrder.indexOf(cur);
      if (idx > 0) {
        _prevRepeatCycles = idx;
        for (var i = 0; i < _repeatOrder.length - idx; i++) {
          _ctl.cycleRepeat();
        }
      } else if (idx < 0 && cur > 1) {
        _prevRepeatCustom = cur;
        _prevRepeatCycles = 0;
        _ctl.setRepeat(0);
      }
    } catch (_) {}
  }

  void _restoreRepeat() {
    try {
      final custom = _prevRepeatCustom;
      if (custom != null) {
        _prevRepeatCustom = null;
        _ctl.setRepeat(custom);
      }
      for (var i = 0; i < _prevRepeatCycles; i++) {
        _ctl.cycleRepeat();
      }
    } catch (_) {}
  }

  Future<void> _speak(String text) async {
    final t = text.trim();
    if (t.isEmpty || _muted || _closed) return;
    final done = Completer<void>();
    var started = false;
    final remove = _ctl.addListener((SpeechState s) {
      if (s.status == SpeechStatus.playing) started = true;
      if (started && s.status == SpeechStatus.idle && !done.isCompleted) {
        done.complete();
      }
    }, fireImmediately: false);
    final guard = Timer(const Duration(seconds: 8), () {
      if (!started && !done.isCompleted) done.complete();
    });
    try {
      await _ctl.stop();
      await _ctl.toggle(t, widget.langCode);
      await done.future.timeout(const Duration(seconds: 150), onTimeout: () {});
    } catch (_) {
    } finally {
      guard.cancel();
      try {
        remove();
      } catch (_) {}
    }
  }

  void _stopSpeaking() {
    try {
      _ctl.stop();
    } catch (_) {}
  }

  // ───────────── جریانِ تماس ─────────────
  Future<void> _connect() async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted || _closed) return;
    final token = ++_turn;
    setState(() => _phase = _Phase.thinking);
    String? greet;
    try {
      greet = await widget.onConnected();
    } catch (_) {}
    if (!mounted || _closed || token != _turn) return;
    final g = greet;
    if (g != null && g.trim().isNotEmpty) {
      setState(() {
        _aiLine = g;
        _phase = _Phase.speaking;
      });
      await _speak(g);
      if (!mounted || _closed || token != _turn) return;
    }
    setState(() => _phase = _Phase.ready);
    if (_handsFree && _sttSupported) unawaited(_startRec());
  }

  Future<void> _onMicTap() async {
    switch (_phase) {
      case _Phase.ready:
      case _Phase.error:
        await _startRec();
        break;
      case _Phase.recording:
        await _stopRec(send: true);
        break;
      case _Phase.speaking:
        _turn++; // قطعِ حرفِ AI
        _stopSpeaking();
        setState(() => _phase = _Phase.ready);
        await _startRec();
        break;
      default:
        break;
    }
  }

  Future<void> _startRec() async {
    if (_closed || !mounted) return;
    if (_phase == _Phase.recording ||
        _phase == _Phase.transcribing ||
        _phase == _Phase.thinking) {
      return;
    }
    if (!_sttSupported) {
      setState(() {
        _showTyping = true;
        _info = _tr(context, 'تشخیصِ صدا فقط روی اندروید کار می‌کند؛ بنویس.',
            'Voice recognition works on Android only — type instead.');
      });
      return;
    }
    try {
      if (!await _rec.hasPermission()) {
        if (mounted) {
          setState(() => _error = _tr(context, 'اجازه‌ی میکروفون داده نشد.',
              'Microphone permission was not granted.'));
        }
        return;
      }
      _stopSpeaking();
      // بعد از حرفِ AI کمی صبر کن تا فوکوسِ صدا/میکروفون آزاد شود
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted || _closed) return;
      try {
        if (await _rec.isRecording()) await _rec.stop();
      } catch (_) {}
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/call_${DateTime.now().millisecondsSinceEpoch}.m4a';
      // اگر تنظیماتِ پیشرفته (حذفِ اکو/نویز) روی این گوشی جواب نداد، ساده‌تر امتحان کن
      const configs = <RecordConfig>[
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: false,
        ),
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
        ),
      ];
      Object? lastErr;
      var started = false;
      for (final cfg in configs) {
        try {
          await _rec.start(cfg, path: path);
          started = true;
          break;
        } catch (e) {
          lastErr = e;
          try {
            await _rec.stop();
          } catch (_) {}
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (!mounted || _closed) return;
        }
      }
      if (!started) throw lastErr ?? StateError('record start failed');
      _recPath = path;
      _speechFrames = 0;
      _silentFrames = 0;
      _recFrames = 0;
      _stopping = false;
      _ampSub?.cancel();
      var ampBusy = false;
      _ampSub = Timer.periodic(const Duration(milliseconds: 100), (_) async {
        if (ampBusy || _closed || !mounted || _phase != _Phase.recording) {
          return;
        }
        ampBusy = true;
        try {
          _onAmp(await _rec.getAmplitude());
        } catch (_) {
          // یک نمونه‌ی ناموفق مهم نیست؛ نمونه‌ی بعدی دوباره خوانده می‌شود
        } finally {
          ampBusy = false;
        }
      });
      if (mounted) {
        setState(() {
          _phase = _Phase.recording;
          _error = '';
          _info = '';
        });
      }
    } catch (e) {
      if (mounted) {
        var d = e.toString().replaceAll('\n', ' ');
        if (d.length > 90) d = '${d.substring(0, 90)}…';
        setState(() => _error = _tr(
            context,
            'شروعِ ضبط ممکن نشد. (میکروفون شاید دستِ برنامه‌ی دیگری باشد)\n$d',
            'Could not start recording.\n$d'));
      }
    }
  }

  void _onAmp(Amplitude a) {
    if (_phase != _Phase.recording || _stopping) return;
    final db = a.current;
    _level.value = ((db + 55) / 55).clamp(0.0, 1.0);
    _recFrames++;
    if (db > -38) {
      _speechFrames++;
      _silentFrames = 0;
    } else {
      _silentFrames++;
    }
    if (_handsFree) {
      if (_speechFrames >= 3 && _silentFrames >= 15) {
        unawaited(_stopRec(send: true)); // حرفت تمام شد (۱٫۵ ثانیه سکوت)
        return;
      }
      if (_speechFrames < 3 && _recFrames >= 100) {
        unawaited(_stopRec(send: false, noSpeech: true)); // ۱۰ ثانیه چیزی نگفتی
        return;
      }
    }
    if (_recFrames >= 600) unawaited(_stopRec(send: true)); // سقفِ ۶۰ ثانیه
  }

  Future<void> _stopRec({required bool send, bool noSpeech = false}) async {
    if (_phase != _Phase.recording || _stopping) return;
    _stopping = true;
    _ampSub?.cancel();
    _ampSub = null;
    _level.value = 0;
    String? out;
    try {
      out = await _rec.stop();
    } catch (_) {}
    final path = out ?? _recPath;
    final heard = _speechFrames >= 3;
    if (!mounted || _closed) {
      _deleteFile(path);
      return;
    }
    if (!send || !heard || path == null) {
      _deleteFile(path);
      setState(() {
        _phase = _Phase.ready;
        _info = _tr(
          context,
          noSpeech
              ? 'چیزی نشنیدم. هر وقت آماده بودی میکروفون رو بزن.'
              : 'صدایی نشنیدم؛ دوباره امتحان کن.',
          noSpeech
              ? "I didn't hear anything. Tap the mic when you're ready."
              : "I couldn't hear you — try again.",
        );
      });
      return;
    }
    setState(() {
      _phase = _Phase.transcribing;
      _info = '';
    });
    String? text;
    try {
      text = await _transcribe(path);
    } on _NoModel {
      _deleteFile(path);
      await _loadModelInfo();
      if (mounted) {
        setState(() {
          _needModel = true;
          _phase = _Phase.ready;
        });
        // ⬇️ بی‌صدا شروع می‌شود؛ کاربر فقط پیامِ «در حال آماده‌سازی» را می‌بیند
        unawaited(_downloadModel());
      }
      return;
    } catch (_) {
      text = null;
    }
    _deleteFile(path);
    if (!mounted || _closed) return;
    final clean = _cleanTranscript(text ?? '');
    if (clean.isEmpty) {
      setState(() {
        _phase = _Phase.ready;
        _info = _tr(context, 'متوجه نشدم چی گفتی؛ یه بار دیگه بگو.',
            "I didn't catch that — say it once more.");
      });
      return;
    }
    await _submit(clean);
  }

  String _cleanTranscript(String t) => t
      .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|♪[^♪]*♪'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<void> _submit(String text, {bool retry = false}) async {
    final t = text.trim();
    if (t.isEmpty || _closed) return;
    final token = ++_turn;
    setState(() {
      _heard = t;
      _lastText = t;
      _phase = _Phase.thinking;
      _error = '';
      _info = '';
      _fixes = const [];
    });
    CallTurn? turn;
    try {
      turn = await widget.onUserSaid(t, retry);
    } catch (_) {
      turn = null;
    }
    if (!mounted || _closed || token != _turn) return;
    if (turn == null) {
      setState(() {
        _phase = _Phase.error;
        _error = _tr(context, 'هوش مصنوعی جواب نداد. اینترنت رو چک کن.',
            'The AI did not answer. Check your connection.');
      });
      return;
    }
    final res = turn;
    setState(() {
      _fixes = res.fixes;
      _aiLine = res.spoken;
      _phase = _Phase.speaking;
    });
    await _speak(res.spoken);
    if (!mounted || _closed || token != _turn) return;
    setState(() => _phase = _Phase.ready);
    if (_handsFree && _sttSupported) unawaited(_startRec());
  }

  // ───────────── تشخیصِ گفتار (Whisperِ روی گوشی) ─────────────
  Future<String?> _pickModel() async {
    try {
      final s = await NativeBridge.instance.getWhisperStatus();
      final ms = s['models'];
      if (ms is List) {
        final ok = <String>{
          for (final m in ms)
            if (m is Map && m['downloaded'] == true) m['id'].toString(),
        };
        for (final id in const ['base', 'small', 'tiny']) {
          if (ok.contains(id)) return id;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _loadModelInfo() async {
    try {
      final s = await NativeBridge.instance.getWhisperStatus();
      final ms = s['models'];
      if (ms is List) {
        for (final m in ms) {
          if (m is Map && m['id'] == 'base') {
            _approxMb = (m['approxMb'] as num?)?.toInt() ?? 0;
          }
        }
      }
    } catch (_) {}
  }

  Future<String?> _transcribe(String path) async {
    final model = await _pickModel();
    if (model == null) throw _NoModel();
    final n = NativeBridge.instance;
    final job = 'call-${DateTime.now().microsecondsSinceEpoch}';
    final buf = StringBuffer();
    final done = Completer<String?>();
    final sub = n.events.listen((e) {
      if (e.data['job'] != job) return;
      switch (e.name) {
        case 'syncChunk':
          buf.write(' ${e.data['text'] ?? ''}');
          break;
        case 'syncDone':
          if (!done.isCompleted) done.complete(buf.toString().trim());
          break;
        case 'syncError':
          if (!done.isCompleted) done.complete(null);
          break;
      }
    });
    try {
      await n.syncTranscribe(
          job: job, path: path, lang: widget.langCode, model: model);
      return await done.future
          .timeout(const Duration(seconds: 60), onTimeout: () => null);
    } on PlatformException catch (e) {
      if ('${e.message}'.contains('NO_MODEL')) throw _NoModel();
      return null;
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _downloadModel() async {
    if (_dlRunning) return;
    final n = NativeBridge.instance;
    setState(() {
      _dlRunning = true;
      _dlFrac = 0;
      _error = '';
    });
    _dlSub?.cancel();
    _dlSub = n.events.listen((e) {
      if (e.name == 'whisperDownloadProgress') {
        final b = (e.data['bytes'] as num?)?.toDouble() ?? 0;
        final t = (e.data['total'] as num?)?.toDouble() ?? 0;
        if (mounted && t > 0) setState(() => _dlFrac = (b / t).clamp(0.0, 1.0));
      } else if (e.name == 'whisperDownloadDone') {
        _dlSub?.cancel();
        if (mounted) {
          setState(() {
            _dlRunning = false;
            _needModel = false;
            _info = _tr(context, 'دستیار صوتی آماده شد! حالا میکروفون رو بزن.',
                'Your voice assistant is ready! Tap the mic now.');
          });
        }
      } else if (e.name == 'whisperDownloadError') {
        _dlSub?.cancel();
        if (mounted) {
          setState(() {
            _dlRunning = false;
            _error = _tr(context, 'آماده‌سازی دستیار کامل نشد؛ چند دقیقه‌ی دیگه خودکار دوباره تلاش می‌شه.',
                'The assistant is not ready yet; it will retry automatically in a few minutes.');
          });
        }
      }
    });
    try {
      final r = await n.downloadWhisperModel(model: 'base');
      if (r['alreadyDownloaded'] == true && mounted) {
        _dlSub?.cancel();
        setState(() {
          _dlRunning = false;
          _needModel = false;
        });
      }
    } catch (_) {
      _dlSub?.cancel();
      if (mounted) {
        setState(() {
          _dlRunning = false;
          _error = _tr(context, 'دستیار هنوز آماده نیست؛ کمی بعد دوباره امتحان کن.', 'The assistant is not ready yet; please try again shortly.');
        });
      }
    }
  }

  void _deleteFile(String? p) {
    if (p == null || kIsWeb) return;
    try {
      File(p).deleteSync();
    } catch (_) {}
  }

  // ───────────── UI ─────────────
  String _status(BuildContext context) {
    final name = widget.persona.name;
    switch (_phase) {
      case _Phase.ringing:
        return _tr(context, 'در حال برقراری تماس…', 'Calling…');
      case _Phase.ready:
        return _tr(context, 'آماده‌ام؛ میکروفون رو بزن', 'Tap the mic to talk');
      case _Phase.recording:
        return _tr(context, 'گوش می‌دم…', 'Listening…');
      case _Phase.transcribing:
        return _tr(context, 'دارم صدات رو می‌فهمم…', 'Understanding your voice…');
      case _Phase.thinking:
        return _tr(context, 'در حال فکر کردن…', 'Thinking…');
      case _Phase.speaking:
        return _tr(context, '$name داره حرف می‌زنه', '$name is speaking');
      case _Phase.error:
        return _tr(context, 'مشکلی پیش اومد', 'Something went wrong');
    }
  }

  String _clock2() {
    final m = (_secs ~/ 60).toString().padLeft(2, '0');
    final s = (_secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _avatar() {
    final p = widget.persona;
    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _level]),
      builder: (_, __) {
        final listening = _phase == _Phase.recording;
        final speaking = _phase == _Phase.speaking;
        final ringing = _phase == _Phase.ringing;
        final wave = (math.sin(_pulse.value * math.pi * 2)).abs();
        final mouth = _mouthViseme(speaking);
        final photo = _avatarBytes(p.image);
        final lv = listening
            ? _level.value
            : speaking
                ? 0.3 + 0.5 * wave
                : ringing
                    ? wave
                    : 0.0;
        Widget ring(double size, double op) => Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(op.clamp(0.0, 1.0)),
              ),
            );
        return Stack(
          alignment: Alignment.center,
          children: [
            ring(150 + 46 * lv, 0.06 + 0.06 * lv),
            ring(128 + 24 * lv, 0.10 + 0.08 * lv),
            Container(
              width: 104,
              height: 104,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.85), width: 3),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(p.colorValue, Colors.white, 0.18)!,
                    Color.lerp(p.colorValue, Colors.black, 0.35)!,
                  ],
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Transform.scale(
                scale: 1.0, // صورت ثابت می‌ماند؛ فقط دهان حرکت می‌کند
                child: photo != null
                    ? _TalkingJaw(
                        size: 104,
                        viseme: mouth,
                        split: 0.68,
                        scale: 0.8,
                        child: Image.memory(photo,
                            width: 104,
                            height: 104,
                            fit: BoxFit.cover,
                            gaplessPlayback: true),
                      )
                    : _EmojiTalkingFace(
                        emoji: p.emoji,
                        size: 70,
                        talk: _talkShape(speaking),
                        // اگر تحلیلِ پیکسلیِ ایموجی ممکن نبود، همان روشِ قبلی
                        fallback: _TalkingJaw(
                          size: 70,
                          viseme: mouth,
                          split: 0.655,
                          scale: 0.6,
                          skin: _yellowFaceEmoji(p.emoji) ? const Color(0xFFFFCA28) : null,
                          child: Center(
                            child: Text(
                              p.emoji,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 58, height: 1.0),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// شخصیتِ عکس‌دار: عکسِ تمام‌قاب + حرکتِ لب/فک هنگامِ حرف‌زدن (هر فریم دوباره ساخته می‌شود)
  Widget _photoFace(PhotoFaceSpec spec) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _level]),
      builder: (_, __) {
        final speaking = _phase == _Phase.speaking;
        final talk = _talkShape(speaking);
        return PhotoTalkingFace(
          spec: spec,
          mouth: _photoMouth(speaking),
          speaking: speaking,
          time: DateTime.now().millisecondsSinceEpoch / 1000.0,
        );
      },
    );
  }

  // ── دهانِ شخصیتِ عکس‌دار (Ryan و …): حرکتِ کوچک، نرم و نامنظم مثلِ گفتارِ واقعی ──
  double _pmOpen = 0, _pmRound = 0;
  int _pmLastMs = 0;

  /// فکِ پایین موقعِ حرفِ پیوسته کاملاً بسته نمی‌شود، دامنه‌ی هر هجا فرق دارد،
  /// بینِ عبارت‌ها مکثِ کوتاه می‌آید و مقدارها با نرم‌کننده (attack سریع/release کندتر) می‌آیند.
  MouthShape? _photoMouth(bool speaking) {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final dt = _pmLastMs == 0 ? 16 : (ms - _pmLastMs).clamp(1, 80);
    _pmLastMs = ms;
    var tOpen = 0.0, tRound = 0.0;
    if (speaking) {
      // هر عبارت ~۲٫۴–۳٫۸ ثانیه؛ ته‌ش یک مکثِ ~۳۵۰ms
      final phrase = _visemeHash(ms ~/ 3100 + 7) % 1400; // ۰..۱۴۰۰ → طولِ ۲٫۴–۳٫۸s
      final phraseLen = 2400 + phrase;
      final pos = ms % phraseLen;
      if (pos < phraseLen - 350) {
        // هجاها: طولِ ~۱۵۰–۲۴۰ms (تقریباً ۴–۶ هجا در ثانیه)
        final k = ms ~/ 230;
        final h = _visemeHash(k);
        final span = 1 + (h % 3 == 0 ? 1 : 0); // بعضی هجاها کشیده‌ترند
        final seg = ((ms ~/ 230) ~/ span);
        final hs = _visemeHash(seg + 31);
        final dur = 230.0 * span;
        final ph = (ms % (230 * span)) / dur;
        const amps = [0.24, 0.34, 0.20, 0.38, 0.28, 0.16, 0.32];
        final amp = amps[hs % amps.length];
        final e = math.pow(math.sin(ph * math.pi), 1.0).toDouble();
        const lo = 0.05; // بینِ هجاها کاملاً بسته نمی‌شود
        tOpen = lo + (amp - lo) * e;
        // «او/وو» فقط گاهی و ملایم
        const rounds = [0.0, 0.0, 0.18, 0.0, 0.08, 0.0, 0.0];
        tRound = rounds[(hs >> 4) % rounds.length] * e;
      }
    }
    final tau = tOpen > _pmOpen ? 85.0 : 130.0;
    final a = 1 - math.exp(-dt / tau);
    _pmOpen += (tOpen - _pmOpen) * a;
    _pmRound += (tRound - _pmRound) * (1 - math.exp(-dt / 140.0));
    if (!speaking && _pmOpen < 0.01 && _pmRound < 0.01) {
      _pmOpen = 0;
      _pmRound = 0;
      return null;
    }
    return MouthShape(_pmOpen, _pmRound);
  }

  static const List<_Viseme> _visemes = [
    _Viseme(0.30, 0.012, 1.0), // لبخندِ بسته
    _Viseme(0.13, 0.115, 0.0), // «او» گرد (دایره‌ی تو‌پُر)
    _Viseme(0.26, 0.105, 0.5), // باز
    _Viseme(0.34, 0.050, 1.0), // «ای» / لبخندِ پهن
    _Viseme(0.18, 0.090, 0.2), // «آ» کوچک
    _Viseme(0.22, 0.020, 0.7), // نیمه‌بسته
  ];

  int _visemeHash(int n) {
    var x = (n * 2654435761) & 0x7fffffff;
    x ^= x >> 13;
    return (x * 1274126177) & 0x7fffffff;
  }

  /// شکلِ دهان: هر ~۱۴۰ms به یکی از حالت‌ها (لبخند، گرد، باز، …) نرم عوض می‌شود.
  /// گاهی هم مکث می‌کند و روی لبخندِ بسته می‌ماند. null = ساکت.
  _Viseme? _mouthViseme(bool speaking) {
    if (!speaking) return null;
    final ms = DateTime.now().millisecondsSinceEpoch;
    final t = ms / 1000.0;
    if (math.sin(t * 2 * math.pi * 0.45) > 0.85) return _visemes[0]; // مکث
    const seg = 140;
    final i = ms ~/ seg;
    var f = (ms % seg) / seg;
    f = f * f * (3 - 2 * f);
    final a = _visemes[_visemeHash(i) % _visemes.length];
    var bi = _visemeHash(i + 1) % _visemes.length;
    if (_visemes[bi] == a) bi = (bi + 1) % _visemes.length;
    return _Viseme.lerp(a, _visemes[bi], f);
  }

  /// حالتِ دهانِ ایموجی: هجا‌به‌هجا (~۵.۵ هجا در ثانیه) باز و بسته می‌شود؛ هر هجا یک واکه‌ی
  /// متفاوت (آ، ای، ایی، او، اوو) و شدتِ متفاوت دارد و هر چند هجا یک مکثِ کوتاه می‌آید. null = ساکت.
  _Talk? _talkShape(bool speaking) {
    if (!speaking) return null;
    final ms = DateTime.now().millisecondsSinceEpoch;
    const syl = 180;
    final i = ms ~/ syl;
    final ph = (ms % syl) / syl;
    if (i % 7 == 6 && _visemeHash(i ~/ 7 + 91) % 3 != 0) return _Talk.rest;
    final h = _visemeHash(i);
    const opens = [0.95, 0.55, 0.30, 0.70, 0.40];
    const rounds = [0.0, 0.10, 0.0, 0.85, 1.0];
    const smiles = [0.30, 0.65, 1.0, 0.10, 0.0];
    final v = h % 5;
    final stress = 0.7 + 0.3 * ((h >> 5) % 4) / 3;
    final e = math.pow(math.sin(ph * math.pi), 0.8).toDouble();
    return _Talk(opens[v] * e * stress, rounds[v] * e, smiles[v] * e + 0.5 * (1 - e));
  }

  /// پلک‌زدن: هر ~۳٫۵ ثانیه برای ~۱۲۰ میلی‌ثانیه
  double _blinkAmount() {
    final ms = DateTime.now().millisecondsSinceEpoch % 3600;
    if (ms > 120) return 0;
    return math.sin(ms / 120 * math.pi);
  }

  Widget _bars() {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _level]),
      builder: (_, __) {
        final active =
            _phase == _Phase.recording || _phase == _Phase.speaking;
        final lv = _phase == _Phase.recording
            ? _level.value
            : (_phase == _Phase.speaking ? 0.7 : 0.0);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 11; i++)
              Container(
                width: 4,
                height: 4 +
                    (active
                        ? 22 *
                            lv *
                            (0.35 +
                                0.65 *
                                    ((math.sin(_pulse.value * math.pi * 2 +
                                                    i * 0.9) +
                                                1) /
                                            2))
                        : 0),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(active ? 0.9 : 0.35),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required VoidCallback onTap,
    Color bg = const Color(0xFFEFE9D6),
    Color fg = const Color(0xFF3A3A3A),
    double size = 46,
    String? tip,
  }) {
    return Tooltip(
      message: tip ?? '',
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.46, color: fg),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final p = widget.persona;
    final base = p.colorValue;
    final rec = _phase == _Phase.recording;
    final canMic = _phase == _Phase.ready ||
        _phase == _Phase.error ||
        _phase == _Phase.recording ||
        _phase == _Phase.speaking;
    final photoFace = p.photoFace;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── «ویدیو» ──
        Container(
          height: 380,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(base, Colors.black, 0.2)!,
                Color.lerp(base, Colors.black, 0.72)!,
              ],
            ),
          ),
          child: Stack(
            children: [
              if (photoFace != null) ...[
                // شخصیتِ عکس‌دار: عکس تمام‌قابِ ویدیو است و لب‌هایش حرکت می‌کند
                Positioned.fill(
                  child: RepaintBoundary(child: _photoFace(photoFace)),
                ),
                // سایه‌ی بالا و پایین تا متن‌ها روی عکس خوانا بمانند
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 90,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.55),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 120,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.5),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // پس‌زمینه‌ی مخصوصِ هر شخصیت
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _CallBackdropPainter(p.id, base,
                          hint: '${p.role} ${p.scenario} ${p.personality} ${p.name} ${p.emoji}'),
                    ),
                  ),
                ),
                Align(alignment: const Alignment(0, -0.28), child: _avatar()),
              ],
              // بالا: اسم + وضعیت + زمان
              Positioned(
                left: 14,
                right: 14,
                top: 12,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800)),
                          Text(_status(context),
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 11.5)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 5),
                          Text(_clock2(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (photoFace == null)
                Align(alignment: const Alignment(0, 0.3), child: _bars()),
              // پایین: زیرنویس
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_heard.isNotEmpty)
                        Text('${_tr(context, 'تو', 'You')}: $_heard',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 11)),
                      if (_fixes.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: _fixes.first.original,
                                style: const TextStyle(
                                  color: Color(0xFFFCA5A5),
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              const TextSpan(
                                  text: '  →  ',
                                  style: TextStyle(color: Colors.white70)),
                              TextSpan(
                                text: _fixes.first.corrected,
                                style: const TextStyle(
                                  color: Color(0xFF86EFAC),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ]),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      if (_aiLine.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(_aiLine,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  height: 1.35)),
                        ),
                      if (_heard.isEmpty && _aiLine.isEmpty)
                        Text(
                          _tr(context, 'زیرنویسِ تماس این‌جا می‌آید…',
                              'Call captions will appear here…'),
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 11.5),
                        ),
                    ],
                  ),
                ),
              ),
              // تصویرِ «خودت»
              PositionedDirectional(
                end: 10,
                top: 58,
                child: Container(
                  width: 62,
                  height: 82,
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: rec
                            ? const Color(0xFFEF4444)
                            : Colors.white24,
                        width: rec ? 2 : 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(rec ? Icons.mic : Icons.person_outline,
                          color: rec
                              ? const Color(0xFFEF4444)
                              : Colors.white54,
                          size: 26),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: ValueListenableBuilder<double>(
                          valueListenable: _level,
                          builder: (_, v, __) => ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: rec ? v : 0,
                              minHeight: 4,
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation(
                                  Color(0xFF86EFAC)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(_tr(context, 'تو', 'You'),
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── کنترل‌ها ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _circleBtn(
              icon: _muted ? Icons.volume_off : Icons.volume_up,
              tip: _tr(context, 'صدای شخصیت', 'Persona voice'),
              onTap: () {
                setState(() => _muted = !_muted);
                if (_muted) _stopSpeaking();
              },
            ),
            // میکروفون
            GestureDetector(
              onTap: canMic ? _onMicTap : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: !canMic
                      ? c.cardBorder
                      : rec
                          ? const Color(0xFFDC2626)
                          : c.teal,
                  boxShadow: rec
                      ? [
                          BoxShadow(
                            color: const Color(0xFFDC2626).withOpacity(0.45),
                            blurRadius: 18,
                            spreadRadius: 3,
                          )
                        ]
                      : const [],
                ),
                child: Icon(
                  rec ? Icons.stop_rounded : Icons.mic,
                  size: 32,
                  color: Colors.white,
                ),
              ),
            ),
            _circleBtn(
              icon: Icons.call_end,
              bg: const Color(0xFFDC2626),
              fg: Colors.white,
              size: 50,
              tip: _tr(context, 'پایان تماس', 'End call'),
              onTap: widget.onEnd,
            ),
            _circleBtn(
              icon: Icons.keyboard_alt_outlined,
              tip: _tr(context, 'نوشتن', 'Type'),
              bg: _showTyping ? c.gold : const Color(0xFFEFE9D6),
              onTap: () => setState(() => _showTyping = !_showTyping),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _tr(context, 'دست‌آزاد (شروع و پایانِ خودکار)',
                  'Hands-free (auto start / stop)'),
              style: TextStyle(color: c.inkSoft, fontSize: 11.5),
            ),
            Switch(
              value: _handsFree,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: c.teal,
              onChanged: (v) => setState(() => _handsFree = v),
            ),
          ],
        ),

        if (_info.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(_info,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.inkSoft, fontSize: 12)),
          ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              children: [
                Text(_error,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.rose, fontSize: 12)),
                if (_phase == _Phase.error && _lastText.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _submit(_lastText, retry: true),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(_tr(context, 'تلاش دوباره', 'Try again')),
                  ),
              ],
            ),
          ),

        // ── دستیار صوتی هنوز آماده نیست: بدونِ هیچ اشاره‌ای به «دانلود» ──
        if (_needModel)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.goldSoft,
              border: Border.all(color: c.gold),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Text('✨', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _tr(
                      context,
                      'دستیار صوتی در حال آماده‌سازیِ نهایی است و تا چند دقیقه‌ی دیگه فعال می‌شه. تا اون موقع می‌تونی با دکمه‌ی کیبورد تایپ کنی و گفتگو رو ادامه بدی.',
                      'Your voice assistant is getting its final touches and will be ready in a few minutes. Meanwhile you can keep chatting by typing with the keyboard button.',
                    ),
                    style: TextStyle(color: c.ink, fontSize: 12.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ),

        // ── نوشتنِ دستی (برای جایی که نمی‌شود حرف زد) ──
        if (_showTyping)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: c.teal, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                Expanded(
                  child: TextField(
                    controller: _typeCtl,
                    minLines: 1,
                    maxLines: 3,
                    style: TextStyle(color: c.ink, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: _tr(context, 'به‌جای حرف زدن بنویس…',
                          'Type instead of speaking…'),
                      hintStyle: TextStyle(
                          color: c.inkSoft.withOpacity(0.6), fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 4),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: (_phase == _Phase.thinking ||
                          _phase == _Phase.transcribing)
                      ? null
                      : () {
                          final t = _typeCtl.text.trim();
                          if (t.isEmpty) return;
                          _typeCtl.clear();
                          _stopSpeaking();
                          if (_phase == _Phase.recording) {
                            _ampSub?.cancel();
                            _ampSub = null;
                            _stopping = true;
                            unawaited(_rec.stop().then((p) => _deleteFile(p)));
                            _level.value = 0;
                          }
                          _submit(t);
                        },
                  icon: Icon(Icons.send_rounded, color: c.teal, size: 20),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// صورتِ کارتونیِ آواتار: چشم، ابرو و دهانی که موقعِ حرف‌زدن تکان می‌خورد.
class _TalkingFacePainter extends CustomPainter {
  final Color hair;
  final double mouth; // 0 = بسته .. 1 = کاملاً باز
  final double blink; // 0 = باز .. 1 = بسته
  final bool smile;
  const _TalkingFacePainter({
    required this.hair,
    required this.mouth,
    required this.blink,
    required this.smile,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // پوست
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF6D3AE), Color(0xFFE8B98C)],
        ).createShader(Offset.zero & size),
    );
    // مو
    final hairPath = Path()
      ..moveTo(0, h * 0.40)
      ..quadraticBezierTo(w * 0.05, h * 0.02, w * 0.5, h * 0.0)
      ..quadraticBezierTo(w * 0.95, h * 0.02, w, h * 0.40)
      ..quadraticBezierTo(w * 0.80, h * 0.20, w * 0.5, h * 0.22)
      ..quadraticBezierTo(w * 0.20, h * 0.20, 0, h * 0.40)
      ..close();
    canvas.drawPath(hairPath, Paint()..color = hair);
    // گونه‌ها
    final cheek = Paint()..color = const Color(0x33E57373);
    canvas.drawCircle(Offset(w * 0.22, h * 0.62), w * 0.07, cheek);
    canvas.drawCircle(Offset(w * 0.78, h * 0.62), w * 0.07, cheek);
    // ابرو
    final brow = Paint()
      ..color = hair
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.03
      ..strokeCap = StrokeCap.round;
    final browUp = h * 0.012 * mouth;
    canvas.drawLine(Offset(w * 0.24, h * 0.32 - browUp),
        Offset(w * 0.40, h * 0.31 - browUp), brow);
    canvas.drawLine(Offset(w * 0.60, h * 0.31 - browUp),
        Offset(w * 0.76, h * 0.32 - browUp), brow);
    // چشم‌ها
    final eyeH = h * 0.085 * (1 - blink * 0.92);
    final eye = Paint()..color = const Color(0xFF2B2118);
    for (final cx in [w * 0.32, w * 0.68]) {
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx, h * 0.45),
              width: w * 0.085,
              height: eyeH.clamp(1.0, h)),
          eye);
      if (blink < 0.5) {
        canvas.drawCircle(Offset(cx + w * 0.012, h * 0.435), w * 0.013,
            Paint()..color = Colors.white);
      }
    }
    // بینی
    canvas.drawLine(
        Offset(w * 0.5, h * 0.50),
        Offset(w * 0.5, h * 0.58),
        Paint()
          ..color = const Color(0x33000000)
          ..strokeWidth = w * 0.015
          ..strokeCap = StrokeCap.round);
    // دهان
    final cx = w * 0.5;
    final cy = h * 0.74;
    if (mouth < 0.08) {
      final lip = Paint()
        ..color = const Color(0xFF8E3B2F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.028
        ..strokeCap = StrokeCap.round;
      final curve = smile ? h * 0.05 : h * 0.012;
      final path = Path()
        ..moveTo(cx - w * 0.12, cy)
        ..quadraticBezierTo(cx, cy + curve * 2, cx + w * 0.12, cy);
      canvas.drawPath(path, lip);
    } else {
      final mw = w * (0.20 + 0.06 * mouth);
      final mh = h * (0.03 + 0.17 * mouth);
      final rect =
          Rect.fromCenter(center: Offset(cx, cy + mh * 0.2), width: mw, height: mh);
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(mh * 0.8));
      canvas.drawRRect(rr, Paint()..color = const Color(0xFF5A1A17));
      // دندان‌های بالا
      canvas.save();
      canvas.clipRRect(rr);
      canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top, rect.width, mh * 0.28),
          Paint()..color = Colors.white);
      // زبان
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx, rect.bottom - mh * 0.12),
              width: mw * 0.6,
              height: mh * 0.45),
          Paint()..color = const Color(0xFFE0707A));
      canvas.restore();
      canvas.drawRRect(
          rr,
          Paint()
            ..color = const Color(0xFF8E3B2F)
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.02);
    }
  }

  @override
  bool shouldRepaint(_TalkingFacePainter o) =>
      o.mouth != mouth ||
      o.blink != blink ||
      o.smile != smile ||
      o.hair != hair;
}

class _NoModel implements Exception {}


/// پس‌زمینه‌ی ویدیو کال؛ برای هر شخصیت یک صحنه‌ی جدا (کلاس، آشپزخانه، دفتر، لابیِ هتل، نئون، کلینیک).
class _CallBackdropPainter extends CustomPainter {
  final String id;
  final Color base;
  final String hint; // نقش/سناریو/ایموجیِ شخصیت؛ برای انتخابِ صحنه‌ی شخصیت‌های ساخته‌شده
  const _CallBackdropPainter(this.id, this.base, {this.hint = ''});

  Color _l(double t) => Color.lerp(base, Colors.white, t)!;
  Color _d(double t) => Color.lerp(base, Colors.black, t)!;

  Paint _fill(Color c) => Paint()..color = c;
  Paint _line(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;

  /// موضوعِ صحنه: برای شخصیت‌های آماده همان id؛ برای شخصیت‌های ساخته‌شده از روی نقش/سناریو/ایموجی حدس زده می‌شود.
  String get _scene {
    switch (id) {
      case 'jimmy':
      case 'emma':
      case 'daniel':
      case 'sofia':
      case 'alex':
      case 'drlee':
        return id;
    }
    final t = hint.toLowerCase();
    bool has(List<String> k) => k.any((e) => t.contains(e));
    if (has(['doctor', 'nurse', 'clinic', 'hospital', 'pharmac', 'medical', 'دکتر', 'پزشک', 'پرستار', 'بیمارستان', 'کلینیک', 'داروخانه', '⚕', '🩺', '💊'])) return 'drlee';
    if (has(['barista', 'coffee', 'cafe', 'café', 'chef', 'restaurant', 'waiter', 'waitress', 'baker', 'kitchen', 'کافه', 'قهوه', 'آشپز', 'رستوران', 'گارسون', '🍳', '☕', '🍕', '🍰'])) return 'emma';
    if (has(['airport', 'flight', 'tour guide', 'traveler', 'traveller', 'passport', 'airline', 'سفر', 'فرودگاه', 'پرواز', 'مسافر', 'گردشگر', '✈', '🧳', '🛫', '🗺'])) return 'travel';
    if (has(['beach', 'ocean', 'seaside', 'surf', 'island', 'sailor', 'دریا', 'ساحل', 'جزیره', '🏖', '🌊', '🏄', '⛵'])) return 'beach';
    if (has(['hiking', 'hiker', 'mountain', 'nature', 'forest', 'camping', 'garden', 'farm', 'کوه', 'طبیعت', 'باغ', 'جنگل', 'کمپ', '🌲', '🏔', '🌳', '🏕', '🌿'])) return 'nature';
    if (has(['developer', 'programmer', 'software', 'engineer', 'computer', 'hacker', 'startup', 'scientist', 'laborator', 'technolog', 'برنامه', 'مهندس', 'کامپیوتر', 'فناوری', 'دانشمند', 'آزمایشگاه', '💻', '🔬', '🧪'])) return 'tech';
    if (has(['library', 'librarian', 'writer', 'author', 'poet', 'novel', 'کتابخانه', 'کتاب', 'نویسنده', 'شاعر', '📚', '📖', '✍'])) return 'library';
    if (has(['music', 'singer', 'concert', 'party', 'gamer', 'موسیقی', 'خواننده', 'پارتی', 'گیم', '🎵', '🎸', '🎤', '🎧', '🎮'])) return 'alex';
    if (has(['hotel', 'reception', 'concierge', 'resort', 'هتل', 'پذیرش', '🏨', '🛎'])) return 'sofia';
    if (has(['interview', 'manager', 'boss', 'office', 'business', 'company', 'recruit', 'مصاحبه', 'مدیر', 'شرکت', 'دفتر', '💼', '👔'])) return 'daniel';
    if (has(['teacher', 'tutor', 'professor', 'school', 'lecturer', 'classroom', 'معلم', 'استاد', 'مدرس', 'کلاس', 'مدرسه', 'دانشگاه', '🏫', '🎓'])) return 'jimmy';
    return 'room';
  }

  void _cloud(Canvas c, Offset o, double sc, double op) {
    final p = _fill(Colors.white.withOpacity(op));
    c.drawCircle(o + Offset(-18 * sc, 4 * sc), 12 * sc, p);
    c.drawCircle(o + Offset(0, -4 * sc), 17 * sc, p);
    c.drawCircle(o + Offset(20 * sc, 3 * sc), 13 * sc, p);
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(o.dx - 30 * sc, o.dy + 2 * sc, 62 * sc, 14 * sc),
            Radius.circular(7 * sc)),
        p);
  }

  void _plant(Canvas c, Offset b, double sc) {
    final leaf = _fill(const Color(0xFF3E8E5A).withOpacity(0.78));
    final leaf2 = _fill(const Color(0xFF2F7048).withOpacity(0.78));
    for (var i = 0; i < 7; i++) {
      c.save();
      c.translate(b.dx, b.dy - 26 * sc);
      c.rotate(-1.25 + i * 0.42);
      c.drawOval(Rect.fromLTWH(-7 * sc, -62 * sc, 14 * sc, 62 * sc),
          i.isEven ? leaf : leaf2);
      c.restore();
    }
    c.drawPath(
        Path()
          ..moveTo(b.dx - 22 * sc, b.dy - 28 * sc)
          ..lineTo(b.dx + 22 * sc, b.dy - 28 * sc)
          ..lineTo(b.dx + 16 * sc, b.dy)
          ..lineTo(b.dx - 16 * sc, b.dy)
          ..close(),
        _fill(const Color(0xFFC9784A).withOpacity(0.88)));
    c.drawRect(Rect.fromLTWH(b.dx - 24 * sc, b.dy - 32 * sc, 48 * sc, 6 * sc),
        _fill(const Color(0xFFD98A5B).withOpacity(0.92)));
  }

  void _pine(Canvas c, Offset b, double sc) {
    c.drawRect(Rect.fromLTWH(b.dx - 3 * sc, b.dy - 10 * sc, 6 * sc, 14 * sc),
        _fill(const Color(0xFF5A3A24).withOpacity(0.85)));
    for (var i = 0; i < 3; i++) {
      final y = b.dy - 10 * sc - i * 18 * sc;
      final wd = (26 - i * 6) * sc;
      c.drawPath(
          Path()
            ..moveTo(b.dx - wd, y)
            ..lineTo(b.dx, y - 28 * sc)
            ..lineTo(b.dx + wd, y)
            ..close(),
          _fill(const Color(0xFF1F5D3C).withOpacity(0.88)));
    }
  }

  Path _ridge(Size s, double base, double amp, double phase, double freq) {
    final p = Path()..moveTo(0, s.height);
    for (var x = 0.0; x <= s.width + 6; x += 6) {
      final y = base +
          amp * math.sin(x / s.width * freq * math.pi + phase) +
          amp * 0.45 * math.sin(x / s.width * freq * 2.3 * math.pi + phase * 1.7);
      p.lineTo(x, y);
    }
    p.lineTo(s.width, s.height);
    p.close();
    return p;
  }

  void _glow(Canvas c, Offset o, double r, Color col, double op) {
    c.drawCircle(
      o,
      r,
      Paint()
        ..shader = ui.Gradient.radial(o, r, [
          col.withOpacity(op),
          col.withOpacity(0),
        ]),
    );
  }

  void _bokeh(Canvas c, Size s, int n, int seed, double opMax) {
    final r = math.Random(seed);
    for (var i = 0; i < n; i++) {
      final o = Offset(r.nextDouble() * s.width, r.nextDouble() * s.height);
      final rad = 6 + r.nextDouble() * 22;
      c.drawCircle(o, rad,
          _fill(Colors.white.withOpacity(0.03 + r.nextDouble() * opMax)));
    }
  }

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    switch (_scene) {
      case 'jimmy': // کلاسِ درس
        _glow(canvas, Offset(w * 0.85, h * 0.2), h * 0.55, Colors.white, 0.22);
        // تخته
        final board = RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.12, h * 0.17, w * 0.62, h * 0.34),
            const Radius.circular(8));
        canvas.drawRRect(board, _fill(_d(0.55).withOpacity(0.55)));
        canvas.drawRRect(board, _line(const Color(0xFFD6B98C).withOpacity(0.55), 4));
        final ch = _line(Colors.white.withOpacity(0.28), 2);
        canvas.drawLine(Offset(w * 0.17, h * 0.24), Offset(w * 0.42, h * 0.24), ch);
        canvas.drawLine(Offset(w * 0.17, h * 0.30), Offset(w * 0.56, h * 0.30), ch);
        canvas.drawLine(Offset(w * 0.17, h * 0.36), Offset(w * 0.34, h * 0.36), ch);
        final sq = Path()
          ..moveTo(w * 0.52, h * 0.38)
          ..quadraticBezierTo(w * 0.58, h * 0.30, w * 0.64, h * 0.38)
          ..quadraticBezierTo(w * 0.68, h * 0.45, w * 0.60, h * 0.45);
        canvas.drawPath(sq, ch);
        // پنجره + پرتوِ نور
        final win = Rect.fromLTWH(w * 0.80, h * 0.10, w * 0.15, h * 0.28);
        canvas.drawRRect(RRect.fromRectAndRadius(win, const Radius.circular(6)),
            _fill(Colors.white.withOpacity(0.18)));
        canvas.drawLine(win.topCenter, win.bottomCenter, _line(Colors.white38, 2));
        canvas.drawLine(win.centerLeft, win.centerRight, _line(Colors.white38, 2));
        final beam = Path()
          ..moveTo(win.left, win.bottom)
          ..lineTo(win.right, win.bottom)
          ..lineTo(w * 0.55, h * 0.95)
          ..lineTo(w * 0.25, h * 0.95)
          ..close();
        canvas.drawPath(beam, _fill(Colors.white.withOpacity(0.05)));
        // قفسه‌ی کتاب
        final r = math.Random(3);
        var x = 0.0;
        while (x < w * 0.22) {
          final bw = 7 + r.nextDouble() * 7, bh = 26 + r.nextDouble() * 22;
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(w * 0.04 + x, h * 0.62 - bh, bw, bh),
                  const Radius.circular(2)),
              _fill(_l(0.2 + r.nextDouble() * 0.3).withOpacity(0.35)));
          x += bw + 2;
        }
        canvas.drawLine(Offset(w * 0.03, h * 0.62), Offset(w * 0.28, h * 0.62),
            _line(Colors.white24, 3));
        break;

      case 'emma': // آشپزخانه
        final tile = _line(Colors.white.withOpacity(0.07), 1);
        for (var x = 0.0; x < w; x += 34) {
          canvas.drawLine(Offset(x, h * 0.34), Offset(x, h), tile);
        }
        for (var y = h * 0.34; y < h; y += 34) {
          canvas.drawLine(Offset(0, y), Offset(w, y), tile);
        }
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.34),
            _fill(_d(0.35).withOpacity(0.35)));
        // قفسه و شیشه‌های ادویه
        canvas.drawRect(Rect.fromLTWH(w * 0.05, h * 0.20, w * 0.38, 5),
            _fill(const Color(0xFFD6A86B).withOpacity(0.6)));
        final jars = [0.07, 0.15, 0.23, 0.31, 0.37];
        for (var i = 0; i < jars.length; i++) {
          final jh = 20 + (i % 3) * 7.0;
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(w * jars[i], h * 0.20 - jh, 16, jh),
                  const Radius.circular(4)),
              _fill(Colors.white.withOpacity(0.16 + 0.04 * (i % 2))));
        }
        // لامپ‌های آویز
        for (final lx in [0.70, 0.88]) {
          canvas.drawLine(Offset(w * lx, 0), Offset(w * lx, h * 0.12),
              _line(Colors.white38, 1.5));
          final lamp = Path()
            ..moveTo(w * lx - 16, h * 0.17)
            ..quadraticBezierTo(w * lx, h * 0.07, w * lx + 16, h * 0.17)
            ..close();
          canvas.drawPath(lamp, _fill(const Color(0xFFFFD27A).withOpacity(0.85)));
          _glow(canvas, Offset(w * lx, h * 0.19), 70, const Color(0xFFFFD27A), 0.35);
        }
        // پیشخوان
        canvas.drawRect(Rect.fromLTWH(0, h * 0.86, w, h * 0.14),
            _fill(_d(0.45).withOpacity(0.55)));
        canvas.drawLine(Offset(0, h * 0.86), Offset(w, h * 0.86),
            _line(Colors.white.withOpacity(0.25), 2));
        break;

      case 'daniel': // دفتر کار با منظره‌ی شهر
        _glow(canvas, Offset(w * 0.2, h * 0.18), h * 0.5,
            const Color(0xFFFFB86B), 0.28);
        final r = math.Random(11);
        var x = -10.0;
        while (x < w) {
          final bw = 28 + r.nextDouble() * 34;
          final bh = h * (0.22 + r.nextDouble() * 0.30);
          final top = h * 0.74 - bh;
          canvas.drawRect(Rect.fromLTWH(x, top, bw, h), _fill(_d(0.5).withOpacity(0.7)));
          for (var wy = top + 8; wy < h * 0.72; wy += 12) {
            for (var wx = x + 5; wx < x + bw - 6; wx += 9) {
              if (r.nextDouble() > 0.55) {
                canvas.drawRect(Rect.fromLTWH(wx, wy, 4, 6),
                    _fill(const Color(0xFFFFE29A).withOpacity(0.55)));
              }
            }
          }
          x += bw + 3;
        }
        // قابِ پنجره‌ی شیشه‌ای
        final f = _line(Colors.white.withOpacity(0.22), 3);
        canvas.drawRect(Rect.fromLTWH(6, 6, w - 12, h * 0.74), f);
        canvas.drawLine(Offset(w * 0.33, 6), Offset(w * 0.33, h * 0.74 + 6), f);
        canvas.drawLine(Offset(w * 0.66, 6), Offset(w * 0.66, h * 0.74 + 6), f);
        // میز
        canvas.drawRect(Rect.fromLTWH(0, h * 0.88, w, h * 0.12),
            _fill(Colors.black.withOpacity(0.35)));
        break;

      case 'sofia': // لابیِ هتل
        _glow(canvas, Offset(w * 0.5, h * 0.05), h * 0.6,
            const Color(0xFFFFD98A), 0.30);
        final arch = _line(const Color(0xFFE9C46A).withOpacity(0.45), 3);
        for (var i = 0; i < 3; i++) {
          final cx = w * (0.17 + i * 0.33);
          final aw = w * 0.26;
          final p = Path()
            ..moveTo(cx - aw / 2, h * 0.80)
            ..lineTo(cx - aw / 2, h * 0.38)
            ..arcToPoint(Offset(cx + aw / 2, h * 0.38),
                radius: Radius.circular(aw / 2))
            ..lineTo(cx + aw / 2, h * 0.80);
          canvas.drawPath(p, _fill(Colors.white.withOpacity(0.05)));
          canvas.drawPath(p, arch);
        }
        // لوستر
        canvas.drawLine(Offset(w * 0.5, 0), Offset(w * 0.5, h * 0.08),
            _line(const Color(0xFFE9C46A), 1.5));
        for (var i = -3; i <= 3; i++) {
          canvas.drawCircle(Offset(w * 0.5 + i * 11, h * 0.10 + (i.abs()) * 5),
              3.2, _fill(const Color(0xFFFFE9A8)));
        }
        // کف مرمر
        final floor = Rect.fromLTWH(0, h * 0.80, w, h * 0.20);
        canvas.drawRect(
            floor,
            Paint()
              ..shader = ui.Gradient.linear(floor.topCenter, floor.bottomCenter, [
                Colors.white.withOpacity(0.16),
                Colors.black.withOpacity(0.25),
              ]));
        for (var i = 1; i < 6; i++) {
          canvas.drawLine(Offset(w * i / 6, h * 0.80), Offset(w * (i - 3) / 3 + w * 0.5, h),
              _line(Colors.white.withOpacity(0.06), 1));
        }
        _bokeh(canvas, s, 14, 5, 0.07);
        break;

      case 'alex': // نئون و موسیقی
        final r = math.Random(21);
        for (var i = 0; i < 4; i++) {
          final y = h * (0.12 + i * 0.16);
          canvas.drawLine(Offset(-10, y + 40), Offset(w + 10, y - 40),
              _line(Colors.white.withOpacity(0.05), 14));
        }
        final neon = [const Color(0xFFFF4FD8), const Color(0xFF38E8FF), const Color(0xFFB6FF3B)];
        for (var i = 0; i < 3; i++) {
          final o = Offset(w * (0.18 + i * 0.32), h * (0.26 + (i % 2) * 0.18));
          _glow(canvas, o, 70, neon[i], 0.25);
          canvas.drawCircle(o, 38 + i * 8.0, _line(neon[i].withOpacity(0.7), 3));
        }
        // اکولایزر
        final bw = w / 28;
        for (var i = 0; i < 26; i++) {
          final bh = 14 + r.nextDouble() * 60;
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(6 + i * bw, h - bh, bw - 3, bh),
                  const Radius.circular(3)),
              _fill(neon[i % 3].withOpacity(0.38)));
        }
        break;

      case 'drlee': // کلینیک
        _glow(canvas, Offset(w * 0.5, h * 0.35), h * 0.7, Colors.white, 0.14);
        // پنجره‌ی کرکره‌ای
        final win = Rect.fromLTWH(w * 0.06, h * 0.12, w * 0.30, h * 0.34);
        canvas.drawRRect(RRect.fromRectAndRadius(win, const Radius.circular(6)),
            _fill(Colors.white.withOpacity(0.14)));
        for (var y = win.top + 6; y < win.bottom; y += 9) {
          canvas.drawLine(Offset(win.left + 4, y), Offset(win.right - 4, y),
              _line(Colors.white.withOpacity(0.22), 3));
        }
        // صلیبِ پزشکی
        final cc = Offset(w * 0.84, h * 0.22);
        final cp = _fill(Colors.white.withOpacity(0.18));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: cc, width: 16, height: 54),
                const Radius.circular(4)),
            cp);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: cc, width: 54, height: 16),
                const Radius.circular(4)),
            cp);
        // ضربان قلب
        final y0 = h * 0.62;
        final ecg = Path()..moveTo(0, y0);
        for (var x = 0.0; x < w; x += 120) {
          ecg
            ..lineTo(x + 30, y0)
            ..lineTo(x + 40, y0 - 10)
            ..lineTo(x + 50, y0 + 6)
            ..lineTo(x + 60, y0 - 34)
            ..lineTo(x + 70, y0 + 20)
            ..lineTo(x + 80, y0)
            ..lineTo(x + 120, y0);
        }
        canvas.drawPath(ecg, _line(Colors.white.withOpacity(0.16), 2.5));
        _bokeh(canvas, s, 8, 9, 0.05);
        break;

      case 'nature': // کوه و دشت
        final sky = Rect.fromLTWH(0, 0, w, h);
        canvas.drawRect(
            sky,
            Paint()
              ..shader = ui.Gradient.linear(sky.topCenter, sky.bottomCenter, [
                const Color(0xFF9FD8FF).withOpacity(0.45),
                const Color(0xFFFFE9C2).withOpacity(0.18),
              ]));
        _glow(canvas, Offset(w * 0.82, h * 0.16), h * 0.45,
            const Color(0xFFFFF1B8), 0.55);
        canvas.drawCircle(Offset(w * 0.82, h * 0.16), 22,
            _fill(const Color(0xFFFFF4C2).withOpacity(0.9)));
        _cloud(canvas, Offset(w * 0.22, h * 0.13), 1.0, 0.45);
        _cloud(canvas, Offset(w * 0.55, h * 0.24), 0.7, 0.32);
        canvas.drawPath(_ridge(s, h * 0.58, 26, 0.4, 2.0),
            _fill(const Color(0xFF6C8FB0).withOpacity(0.45)));
        canvas.drawPath(_ridge(s, h * 0.68, 20, 2.1, 2.6),
            _fill(const Color(0xFF3E8E5A).withOpacity(0.50)));
        canvas.drawPath(_ridge(s, h * 0.80, 14, 4.0, 3.2),
            _fill(const Color(0xFF2F7048).withOpacity(0.70)));
        for (final t in [
          [0.07, 0.80, 1.2],
          [0.16, 0.84, 0.9],
          [0.90, 0.78, 1.3],
          [0.80, 0.84, 0.85],
        ]) {
          _pine(canvas, Offset(w * t[0], h * t[1]), t[2]);
        }
        break;

      case 'beach': // ساحل
        final bsky = Rect.fromLTWH(0, 0, w, h * 0.52);
        canvas.drawRect(
            bsky,
            Paint()
              ..shader = ui.Gradient.linear(bsky.topCenter, bsky.bottomCenter, [
                const Color(0xFF7CC8FF).withOpacity(0.45),
                const Color(0xFFFFE1B0).withOpacity(0.30),
              ]));
        _glow(canvas, Offset(w * 0.2, h * 0.2), h * 0.5,
            const Color(0xFFFFF1B8), 0.55);
        canvas.drawCircle(Offset(w * 0.2, h * 0.2), 20,
            _fill(const Color(0xFFFFF4C2).withOpacity(0.92)));
        _cloud(canvas, Offset(w * 0.62, h * 0.14), 0.9, 0.40);
        final sea = Rect.fromLTWH(0, h * 0.50, w, h * 0.30);
        canvas.drawRect(
            sea,
            Paint()
              ..shader = ui.Gradient.linear(sea.topCenter, sea.bottomCenter, [
                const Color(0xFF2FA4D8).withOpacity(0.55),
                const Color(0xFF14708F).withOpacity(0.70),
              ]));
        for (var k = 0; k < 6; k++) {
          final wy = h * (0.54 + k * 0.042);
          final wp = Path()..moveTo(0, wy);
          for (var x = 0.0; x <= w; x += 8) {
            wp.lineTo(x, wy + 3 * math.sin(x / 22 + k * 1.3));
          }
          canvas.drawPath(wp, _line(Colors.white.withOpacity(0.16), 1.6));
        }
        // قایق بادبانی
        canvas.drawPath(
            Path()
              ..moveTo(w * 0.72, h * 0.50)
              ..lineTo(w * 0.72, h * 0.40)
              ..lineTo(w * 0.78, h * 0.50)
              ..close(),
            _fill(Colors.white.withOpacity(0.85)));
        canvas.drawLine(Offset(w * 0.69, h * 0.505), Offset(w * 0.79, h * 0.505),
            _line(Colors.white.withOpacity(0.8), 3));
        final sand = Rect.fromLTWH(0, h * 0.78, w, h * 0.22);
        canvas.drawRect(
            sand,
            Paint()
              ..shader = ui.Gradient.linear(sand.topCenter, sand.bottomCenter, [
                const Color(0xFFF1D7A0).withOpacity(0.55),
                const Color(0xFFC9A66B).withOpacity(0.65),
              ]));
        // نخل
        final trunk = Path()
          ..moveTo(w * 0.90, h * 0.92)
          ..quadraticBezierTo(w * 0.95, h * 0.70, w * 0.88, h * 0.50);
        canvas.drawPath(trunk, _line(const Color(0xFF8A5A3B).withOpacity(0.85), 7));
        for (var i = -3; i <= 3; i++) {
          final leaf = Path()
            ..moveTo(w * 0.88, h * 0.50)
            ..quadraticBezierTo(w * 0.88 + i * 12, h * 0.50 - 26,
                w * 0.88 + i * 24, h * 0.52 + i.abs() * 7);
          canvas.drawPath(leaf, _line(const Color(0xFF2F8A55).withOpacity(0.85), 5));
        }
        break;

      case 'travel': // سالنِ فرودگاه
        final tw = Rect.fromLTWH(6, 6, w - 12, h * 0.62);
        canvas.drawRect(
            tw,
            Paint()
              ..shader = ui.Gradient.linear(tw.topCenter, tw.bottomCenter, [
                const Color(0xFF6DB8F2).withOpacity(0.50),
                const Color(0xFFFFE6B8).withOpacity(0.30),
              ]));
        canvas.save();
        canvas.clipRect(tw);
        _cloud(canvas, Offset(w * 0.20, h * 0.30), 1.3, 0.35);
        _cloud(canvas, Offset(w * 0.55, h * 0.50), 1.0, 0.28);
        canvas.drawLine(Offset(w * 0.30, h * 0.40), Offset(w * 0.70, h * 0.22),
            _line(Colors.white.withOpacity(0.22), 3));
        canvas.save();
        canvas.translate(w * 0.74, h * 0.20);
        canvas.rotate(-0.34);
        final pf = _fill(Colors.white.withOpacity(0.88));
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 76, height: 13), pf);
        canvas.drawPath(
            Path()
              ..moveTo(-6, 0)
              ..lineTo(8, -24)
              ..lineTo(17, -24)
              ..lineTo(10, 0)
              ..close(),
            pf);
        canvas.drawPath(
            Path()
              ..moveTo(-6, 0)
              ..lineTo(8, 24)
              ..lineTo(17, 24)
              ..lineTo(10, 0)
              ..close(),
            pf);
        canvas.drawPath(
            Path()
              ..moveTo(-32, 0)
              ..lineTo(-40, -15)
              ..lineTo(-31, -15)
              ..lineTo(-22, 0)
              ..close(),
            pf);
        canvas.restore();
        canvas.restore();
        final tf = _line(Colors.white.withOpacity(0.30), 3);
        canvas.drawRect(tw, tf);
        canvas.drawLine(Offset(w * 0.33, 6), Offset(w * 0.33, tw.bottom), tf);
        canvas.drawLine(Offset(w * 0.66, 6), Offset(w * 0.66, tw.bottom), tf);
        final tfl = Rect.fromLTWH(0, h * 0.68, w, h * 0.32);
        canvas.drawRect(
            tfl,
            Paint()
              ..shader = ui.Gradient.linear(tfl.topCenter, tfl.bottomCenter, [
                Colors.white.withOpacity(0.16),
                Colors.black.withOpacity(0.30),
              ]));
        // چمدان‌ها
        void suitcase(double x, double y, double sw, double sh, Color c) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(x, y - sh, sw, sh), const Radius.circular(6)),
              _fill(c.withOpacity(0.80)));
          canvas.drawLine(Offset(x + sw * 0.5, y - sh), Offset(x + sw * 0.5, y - sh - 12),
              _line(Colors.white.withOpacity(0.6), 3));
          canvas.drawLine(Offset(x + sw * 0.3, y - sh * 0.9), Offset(x + sw * 0.3, y - sh * 0.1),
              _line(Colors.black.withOpacity(0.18), 2));
          canvas.drawLine(Offset(x + sw * 0.7, y - sh * 0.9), Offset(x + sw * 0.7, y - sh * 0.1),
              _line(Colors.black.withOpacity(0.18), 2));
        }
        suitcase(w * 0.05, h * 0.94, 46, 62, const Color(0xFFE76F51));
        suitcase(w * 0.17, h * 0.94, 36, 46, const Color(0xFF2A9D8F));
        suitcase(w * 0.82, h * 0.94, 44, 56, const Color(0xFFE9C46A));
        break;

      case 'tech': // محیطِ فناوری و کد
        final gl = _line(Colors.white.withOpacity(0.05), 1);
        for (var x = 0.0; x < w; x += 28) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), gl);
        }
        for (var y = 0.0; y < h; y += 28) {
          canvas.drawLine(Offset(0, y), Offset(w, y), gl);
        }
        _glow(canvas, Offset(w * 0.15, h * 0.3), h * 0.5, const Color(0xFF38E8FF), 0.22);
        _glow(canvas, Offset(w * 0.88, h * 0.25), h * 0.5, const Color(0xFFB57BFF), 0.22);
        final tr = math.Random(17);
        final neonT = [const Color(0xFF38E8FF), const Color(0xFF7CFFB2), const Color(0xFFFF7AD9)];
        for (final m in [
          Rect.fromLTWH(w * 0.04, h * 0.13, w * 0.24, h * 0.22),
          Rect.fromLTWH(w * 0.72, h * 0.11, w * 0.24, h * 0.24),
        ]) {
          canvas.drawRRect(RRect.fromRectAndRadius(m, const Radius.circular(8)),
              _fill(Colors.black.withOpacity(0.45)));
          canvas.drawRRect(RRect.fromRectAndRadius(m, const Radius.circular(8)),
              _line(const Color(0xFF38E8FF).withOpacity(0.50), 2));
          var ly = m.top + 12;
          while (ly < m.bottom - 8) {
            final ind = (tr.nextInt(3)) * 10.0;
            final lw = 14 + tr.nextDouble() * math.max(4.0, m.width - 40 - ind);
            canvas.drawLine(Offset(m.left + 12 + ind, ly),
                Offset(m.left + 12 + ind + lw, ly),
                _line(neonT[tr.nextInt(3)].withOpacity(0.65), 3));
            ly += 12;
          }
        }
        // ردِ مدار
        final cp = _line(const Color(0xFF38E8FF).withOpacity(0.20), 2);
        canvas.drawPath(
            Path()
              ..moveTo(0, h * 0.58)
              ..lineTo(w * 0.22, h * 0.58)
              ..lineTo(w * 0.28, h * 0.66)
              ..lineTo(w * 0.40, h * 0.66),
            cp);
        canvas.drawPath(
            Path()
              ..moveTo(w, h * 0.62)
              ..lineTo(w * 0.80, h * 0.62)
              ..lineTo(w * 0.74, h * 0.70)
              ..lineTo(w * 0.62, h * 0.70),
            cp);
        canvas.drawCircle(Offset(w * 0.40, h * 0.66), 4, _fill(const Color(0xFF38E8FF).withOpacity(0.8)));
        canvas.drawCircle(Offset(w * 0.62, h * 0.70), 4, _fill(const Color(0xFFB57BFF).withOpacity(0.8)));
        canvas.drawRect(Rect.fromLTWH(0, h * 0.88, w, h * 0.12),
            _fill(Colors.black.withOpacity(0.35)));
        break;

      case 'library': // کتابخانه
        _glow(canvas, Offset(w * 0.5, h * 0.04), h * 0.65, const Color(0xFFFFD98A), 0.30);
        final lr = math.Random(29);
        for (final x0 in [8.0, w * 0.74]) {
          final sw0 = w * 0.26 - 8;
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(x0 - 4, h * 0.06, sw0 + 8, h * 0.80),
                  const Radius.circular(6)),
              _fill(const Color(0xFF5A3A24).withOpacity(0.45)));
          for (var row = 0; row < 4; row++) {
            final by = h * (0.22 + row * 0.19);
            var bx = x0;
            while (bx < x0 + sw0 - 8) {
              final bw = 7 + lr.nextDouble() * 7;
              final bh = 24 + lr.nextDouble() * 22;
              canvas.drawRRect(
                  RRect.fromRectAndRadius(
                      Rect.fromLTWH(bx, by - bh, bw, bh), const Radius.circular(2)),
                  _fill(_l(0.15 + lr.nextDouble() * 0.55).withOpacity(0.55)));
              bx += bw + 1.5;
            }
            canvas.drawRect(Rect.fromLTWH(x0 - 2, by, sw0 + 4, 5),
                _fill(const Color(0xFFD6A86B).withOpacity(0.75)));
          }
        }
        // لامپِ مطالعه
        canvas.drawLine(Offset(w * 0.5, 0), Offset(w * 0.5, h * 0.07),
            _line(const Color(0xFFE9C46A), 1.5));
        canvas.drawPath(
            Path()
              ..moveTo(w * 0.5 - 22, h * 0.12)
              ..quadraticBezierTo(w * 0.5, h * 0.04, w * 0.5 + 22, h * 0.12)
              ..close(),
            _fill(const Color(0xFF2A9D8F).withOpacity(0.85)));
        canvas.drawRect(Rect.fromLTWH(0, h * 0.88, w, h * 0.12),
            _fill(const Color(0xFF3B2616).withOpacity(0.45)));
        break;

      default: // اتاقِ دنج؛ شخصیت‌های ساخته‌شده توسط کاربر (وقتی موضوعِ دیگری تشخیص داده نشود)
        final wall = Rect.fromLTWH(0, 0, w, h * 0.74);
        canvas.drawRect(
            wall,
            Paint()
              ..shader = ui.Gradient.linear(wall.topCenter, wall.bottomCenter, [
                _l(0.16).withOpacity(0.30),
                _d(0.10).withOpacity(0.0),
              ]));
        _glow(canvas, Offset(w * 0.74, h * 0.24), h * 0.55,
            const Color(0xFFFFE9B8), 0.30);
        // پنجره
        final win = Rect.fromLTWH(w * 0.62, h * 0.09, w * 0.26, h * 0.34);
        final wr = RRect.fromRectAndRadius(win, const Radius.circular(8));
        canvas.drawRRect(
            wr,
            Paint()
              ..shader = ui.Gradient.linear(win.topCenter, win.bottomCenter, [
                const Color(0xFF9FD3FF).withOpacity(0.55),
                const Color(0xFFFFE2A8).withOpacity(0.45),
              ]));
        canvas.save();
        canvas.clipRRect(wr);
        _cloud(canvas, Offset(win.left + win.width * 0.35, win.top + win.height * 0.38), 0.8, 0.50);
        canvas.restore();
        canvas.drawRRect(wr, _line(Colors.white.withOpacity(0.55), 4));
        canvas.drawLine(win.topCenter, win.bottomCenter, _line(Colors.white.withOpacity(0.50), 3));
        canvas.drawLine(win.centerLeft, win.centerRight, _line(Colors.white.withOpacity(0.50), 3));
        for (final cx0 in [win.left - 20, win.right - 4]) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(cx0, win.top - 10, 24, win.height + 28),
                  const Radius.circular(6)),
              _fill(_d(0.30).withOpacity(0.50)));
        }
        canvas.drawLine(Offset(win.left - 26, win.top - 10), Offset(win.right + 26, win.top - 10),
            _line(const Color(0xFFD6B98C).withOpacity(0.75), 3));
        // قاب عکس
        final fr = Rect.fromLTWH(w * 0.07, h * 0.09, 50, 38);
        canvas.drawRRect(RRect.fromRectAndRadius(fr, const Radius.circular(3)),
            _fill(Colors.white.withOpacity(0.14)));
        canvas.drawRRect(RRect.fromRectAndRadius(fr, const Radius.circular(3)),
            _line(const Color(0xFFD6B98C).withOpacity(0.75), 3));
        canvas.drawPath(
            Path()
              ..moveTo(fr.left + 6, fr.bottom - 6)
              ..lineTo(fr.left + 20, fr.top + 16)
              ..lineTo(fr.left + 30, fr.bottom - 12)
              ..lineTo(fr.left + 36, fr.top + 22)
              ..lineTo(fr.right - 6, fr.bottom - 6)
              ..close(),
            _fill(Colors.white.withOpacity(0.28)));
        // قفسه‌ی شناور با کتاب و گلدان
        final shelfY = h * 0.33;
        final rb = math.Random(id.hashCode & 0xFFFF);
        var bx = w * 0.06;
        while (bx < w * 0.20) {
          final bw = 8 + rb.nextDouble() * 6;
          final bh = 22 + rb.nextDouble() * 16;
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(bx, shelfY - bh, bw, bh), const Radius.circular(2)),
              _fill(_l(0.25 + rb.nextDouble() * 0.45).withOpacity(0.55)));
          bx += bw + 2;
        }
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(w * 0.24, shelfY - 16, 15, 16), const Radius.circular(4)),
            _fill(const Color(0xFFC9784A).withOpacity(0.85)));
        canvas.drawCircle(Offset(w * 0.24 + 7.5, shelfY - 22), 8,
            _fill(const Color(0xFF3E8E5A).withOpacity(0.80)));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(w * 0.045, shelfY, w * 0.26, 6), const Radius.circular(3)),
            _fill(const Color(0xFFD6A86B).withOpacity(0.75)));
        // کفِ چوبی
        final floor = Rect.fromLTWH(0, h * 0.74, w, h * 0.26);
        canvas.drawRect(
            floor,
            Paint()
              ..shader = ui.Gradient.linear(floor.topCenter, floor.bottomCenter, [
                const Color(0xFF8A5A3B).withOpacity(0.45),
                const Color(0xFF4A2E1E).withOpacity(0.65),
              ]));
        for (final fy in [0.80, 0.87, 0.95]) {
          canvas.drawLine(Offset(0, h * fy), Offset(w, h * fy),
              _line(Colors.black.withOpacity(0.10), 1.5));
        }
        canvas.drawLine(Offset(0, h * 0.74), Offset(w, h * 0.74),
            _line(Colors.white.withOpacity(0.20), 3));
        canvas.drawOval(
            Rect.fromCenter(center: Offset(w * 0.5, h * 0.93), width: w * 0.72, height: 34),
            _fill(_l(0.30).withOpacity(0.25)));
        // گیاه و چراغِ ایستاده
        _plant(canvas, Offset(w * 0.10, h * 0.93), 1.3);
        canvas.drawLine(Offset(w * 0.93, h * 0.94), Offset(w * 0.93, h * 0.52),
            _line(const Color(0xFFD6B98C).withOpacity(0.75), 3));
        canvas.drawPath(
            Path()
              ..moveTo(w * 0.93 - 20, h * 0.54)
              ..lineTo(w * 0.93 + 20, h * 0.54)
              ..lineTo(w * 0.93 + 12, h * 0.46)
              ..lineTo(w * 0.93 - 12, h * 0.46)
              ..close(),
            _fill(const Color(0xFFFFD27A).withOpacity(0.90)));
        _glow(canvas, Offset(w * 0.93, h * 0.54), 80, const Color(0xFFFFD27A), 0.30);
        _bokeh(canvas, s, 8, id.hashCode & 0xFFFF, 0.05);
    }
    // سایه‌ی پایین برای خوانایی زیرنویس
    canvas.drawRect(
        Offset.zero & s,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, h * 0.5), Offset(0, h), [
            Colors.black.withOpacity(0),
            Colors.black.withOpacity(0.38),
          ]));
  }

  @override
  bool shouldRepaint(covariant _CallBackdropPainter old) =>
      old.id != id || old.base != base || old.hint != hint;
}
