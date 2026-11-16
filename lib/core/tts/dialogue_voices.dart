import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../native/native_bridge.dart';
import '../providers/language_selection_provider.dart';
import '../storage/local_storage.dart' show sharedPrefsProvider;

/// 🎭 انتخابِ صدای «مرد» و «زن» برای مکالمه‌ی دو نفره (مثلاً داستان‌های مکالمه‌ای).
///
/// همان منطقِ تبِ «مکالمه» (conversations_tab.dart):
///  • گوینده‌ی اول (A) = صدای مرد، گوینده‌ی دوم (B) = صدای زن
///  • برای متنِ اصلی و همه‌ی زبان‌های هدر (ترجمه‌ها) صدای همان جنسیت با مدلِ همان زبان
///  • اگر برای یک زبان فقط صدای یک جنسیت نصب باشد، صدای جنسیتِ دیگر یک‌بار خودکار دانلود می‌شود
///    و صدای فعالِ قبلیِ کاربر سرِ جایش برمی‌گردد
///  • اگر صدای اختصاصی نبود (وب/صدای گوشی) فقط جنسیت اعلام می‌شود: `gender:male` / `gender:female`
class DialogueVoices {
  DialogueVoices({
    required this.ref,
    required this.mainLang,
    required this.isMounted,
  });

  final WidgetRef ref;

  /// زبانِ متنِ اصلیِ داستان
  final String Function() mainLang;
  final bool Function() isMounted;

  final Map<String, ({String? male, String? female})> _langVoices = {};
  final Map<String, List<String>> _langIds = {}; // شناسه‌ی صداهای نصب‌شده (فعال اول)
  bool _voicesBusy = false;
  bool _voicesDirty = false;
  DateTime _lastLoad = DateTime.fromMillisecondsSinceEpoch(0);

  final Set<String> _autoVoiceAsked = <String>{}; // 'lang:gender'
  final Map<String, ({String? prevActive, String want})> _autoVoicePending = {};
  StreamSubscription<Map<String, dynamic>>? _dlSub;

  static bool _isFemale(String label) =>
      RegExp(r'·\s*F(\s*·|\s*$)').hasMatch(label);
  static bool _isMale(String label) =>
      RegExp(r'·\s*M(\s*·|\s*$)').hasMatch(label);

  /// شروعِ کار: خواندنِ صداها + گوش دادن به پایانِ دانلودِ خودکار
  void start() {
    unawaited(load());
    if (NativeBridge.instance.isSupported && _dlSub == null) {
      _dlSub = NativeBridge.instance
          .on('ttsModelDownloadDone')
          .listen((d) => unawaited(_onVoiceDownloaded(d)));
    }
  }

  void dispose() {
    _dlSub?.cancel();
    _dlSub = null;
  }

  Set<String> _wantedLangs() {
    final sel = ref.read(languageSelectionProvider);
    return <String>{
      mainLang().trim().toLowerCase(),
      for (final c in [sel.native, ...sel.targets]) c.trim().toLowerCase(),
    }..remove('');
  }

  Future<void> load() async {
    if (!NativeBridge.instance.isSupported) return;
    if (_voicesBusy) {
      _voicesDirty = true;
      return;
    }
    _voicesBusy = true;
    try {
      do {
        _voicesDirty = false;
        final next = <String, ({String? male, String? female})>{};
        final nextIds = <String, List<String>>{};
        for (final lang in _wantedLangs()) {
          try {
            final r = await NativeBridge.instance.getTtsVoices(lang: lang);
            final raw = r['voices'];
            final ok = <Map<String, dynamic>>[
              if (raw is List)
                for (final e in raw)
                  if (e is Map &&
                      e['downloaded'] == true &&
                      '${e['id']}'.isNotEmpty)
                    Map<String, dynamic>.from(e),
            ];
            String? pick(bool Function(String) isG) {
              Map<String, dynamic>? first;
              for (final v in ok) {
                if (!isG('${v['label']}')) continue;
                if (v['active'] == true) return '${v['id']}';
                first ??= v;
              }
              return first == null ? null : '${first['id']}';
            }

            next[lang] = (male: pick(_isMale), female: pick(_isFemale));
            nextIds[lang] = [
              for (final v in ok)
                if (v['active'] == true) '${v['id']}',
              for (final v in ok)
                if (v['active'] != true) '${v['id']}',
            ];
            _autoFetchMissingGender(lang, raw, next[lang]!, ok);
          } catch (_) {}
        }
        if (!isMounted()) return;
        _langVoices
          ..clear()
          ..addAll(next);
        _langIds
          ..clear()
          ..addAll(nextIds);
        _lastLoad = DateTime.now();
      } while (_voicesDirty);
    } catch (_) {
    } finally {
      _voicesBusy = false;
    }
  }

  void _autoFetchMissingGender(String lang, dynamic raw,
      ({String? male, String? female}) have, List<Map<String, dynamic>> installed) {
    try {
      if (raw is! List || installed.isEmpty) return;
      final pref = ref.read(sharedPrefsProvider).getString('voiceEnginePref');
      if (pref == 'phone') return;
      String? prevActive;
      for (final v in installed) {
        if (v['active'] == true) prevActive = '${v['id']}';
      }
      void want(String gender, String? haveId, bool Function(String) isG) {
        final key = '$lang:$gender';
        if (haveId != null || _autoVoiceAsked.contains(key)) return;
        // 🎭 اول صداهای سبک/متوسط (دانلودِ سریع‌تر و مطمئن‌تر)، بعد «high»
        for (final allowHigh in const [false, true]) {
          for (final e in raw) {
            if (e is! Map) continue;
            if (e['downloaded'] == true || e['downloading'] == true) continue;
            if (!isG('${e['label']}')) continue;
            if (!allowHigh &&
                '${e['label']}'.toLowerCase().contains('· high')) {
              continue;
            }
            final id = '${e['id']}';
            if (id.isEmpty) continue;
            _autoVoiceAsked.add(key);
            _autoVoicePending[lang] = (prevActive: prevActive, want: id);
            unawaited(NativeBridge.instance
                .downloadTtsModel(lang: lang, voice: id)
                .catchError((_) => <String, dynamic>{}));
            return;
          }
        }
      }

      want('male', have.male, _isMale);
      want('female', have.female, _isFemale);
    } catch (_) {}
  }

  Future<void> _onVoiceDownloaded(Map<String, dynamic> d) async {
    final lang = '${d['lang'] ?? ''}'.trim().toLowerCase();
    final p = _autoVoicePending[lang];
    if (p == null) return;
    try {
      final r = await NativeBridge.instance.getTtsVoices(lang: lang);
      final list = r['voices'];
      var installed = false;
      if (list is List) {
        for (final e in list) {
          if (e is Map && '${e['id']}' == p.want && e['downloaded'] == true) {
            installed = true;
          }
        }
      }
      if (!installed) return;
      _autoVoicePending.remove(lang);
      final prev = p.prevActive;
      if (prev != null && prev.isNotEmpty && prev != p.want) {
        await NativeBridge.instance.setTtsVoice(lang: lang, voice: prev);
      }
    } catch (_) {}
    if (isMounted()) unawaited(load());
  }

  /// صدای گوینده‌ی مرد (A) یا زن (B) برای یک زبان
  String voiceFor({required bool male, required String lang}) {
    final p = _langVoices[lang.trim().toLowerCase()];
    // صدای فعالِ تنظیمات هر لحظه ممکن است عوض شود → فهرست هر چند ثانیه تازه می‌شود
    // (تا صدا روی انتخابِ قدیمی قفل نماند).
    if (isMounted() &&
        !_voicesBusy &&
        (p == null ||
            DateTime.now().difference(_lastLoad) >
                const Duration(seconds: 2))) {
      unawaited(load());
    }
    final own = p == null ? null : (male ? p.male : p.female);
    final other = p == null ? null : (male ? p.female : p.male);
    final v = own ?? (p == null ? null : _distinctFallback(lang, other, male));
    return v ?? (male ? 'gender:male' : 'gender:female');
  }

  /// 🎭 صدای هم‌جنس نصب نیست → به‌جای «صدای فعال برای هر دو گوینده»، یک صدای
  /// نصب‌شده‌ی دیگر (متفاوت از صدای گوینده‌ی مقابل) انتخاب می‌شود.
  String? _distinctFallback(String lang, String? other, bool male) {
    final ids = _langIds[lang.trim().toLowerCase()] ?? const <String>[];
    if (ids.isEmpty) return null;
    if (other != null) {
      for (final id in ids) {
        if (id != other) return id;
      }
      return null;
    }
    // جنسیتِ هیچ‌کدام معلوم نیست: زن = صدای فعال، مرد = صدای بعدی
    if (male) return ids.length > 1 ? ids[1] : null;
    return ids.first;
  }
}
