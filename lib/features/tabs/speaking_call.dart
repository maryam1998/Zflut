import 'dart:async';
import 'dart:convert' show base64Decode, base64Encode;
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;
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
      return GestureDetector(
        onTap: busy ? null : () => onModeChanged(call),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: active ? c.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: active ? c.headerTo : c.inkSoft),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: active ? c.headerTo : c.inkSoft,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: busy ? null : onPickPersona,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.cardBorder),
              ),
              child: Row(
                children: [
                  _EmojiAvatar(persona: persona, size: 34),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(persona.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w800)),
                        if (role.isNotEmpty)
                          Text(role,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(color: c.inkSoft, fontSize: 10.5)),
                      ],
                    ),
                  ),
                  Icon(Icons.unfold_more, size: 18, color: c.inkSoft),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: c.paperDark,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.cardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              seg(false, Icons.chat_bubble_outline, _tr(context, 'چت', 'Chat')),
              seg(true, Icons.videocam_outlined,
                  _tr(context, 'ویدیو کال', 'Call')),
            ],
          ),
        ),
      ],
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
      child: img != null
          ? Image.memory(img,
              width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true)
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
      }
    } catch (_) {}
  }

  void _restoreRepeat() {
    try {
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
            _info = _tr(context, 'آماده شد! حالا میکروفون رو بزن.',
                'Ready! Tap the mic now.');
          });
        }
      } else if (e.name == 'whisperDownloadError') {
        _dlSub?.cancel();
        if (mounted) {
          setState(() {
            _dlRunning = false;
            _error = _tr(context, 'دانلود ناموفق بود. اینترنت رو چک کن.',
                'Download failed. Check your connection.');
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
          _error = _tr(context, 'دانلود شروع نشد.', 'Could not start the download.');
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
                    : _TalkingJaw(
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
          ],
        );
      },
    );
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── «ویدیو» ──
        Container(
          height: 330,
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
              Align(alignment: const Alignment(0, -0.18), child: _avatar()),
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
              Align(alignment: const Alignment(0, 0.5), child: _bars()),
              // پایین: زیرنویس
              Positioned(
                left: 10,
                right: 92,
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
                bottom: 10,
                child: Container(
                  width: 70,
                  height: 92,
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

        // ── بسته‌ی تشخیصِ گفتار ──
        if (_needModel)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.goldSoft,
              border: Border.all(color: c.gold),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _tr(
                    context,
                    'برای این‌که صدات رو بفهمم، یک بسته‌ی صوتی باید روی گوشی باشه${_approxMb > 0 ? ' (حدود $_approxMb مگابایت)' : ''}. فقط یک بار دانلود می‌شه و بعدش بدونِ اینترنت کار می‌کنه.',
                    'To understand your voice I need a voice pack on your device${_approxMb > 0 ? ' (about $_approxMb MB)' : ''}. It downloads once and then works offline.',
                  ),
                  style: TextStyle(color: c.ink, fontSize: 12.5, height: 1.5),
                ),
                const SizedBox(height: 8),
                if (_dlRunning)
                  LinearProgressIndicator(
                    value: _dlFrac > 0 ? _dlFrac : null,
                    color: c.teal,
                    backgroundColor: Colors.white,
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.teal,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _downloadModel,
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(_tr(context, 'دانلودِ بسته', 'Download pack')),
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
