// 📁 مسیر: lib/core/widgets/ai_guide_cards.dart
//
// «راهنمای سریعِ AI»: کارت‌های راهنمای کشویی زیر بخش مکالمه‌ی هوش مصنوعی.
//  • هر کارت با لمس، راهنمای کامل خودش را در یک شیتِ زیبا باز می‌کند
//    (مراحل شماره‌دار + نکته‌ی طلایی؛ می‌شود بین راهنماها ورق زد).
//  • بار اول که کاربر وارد این بخش می‌شود، تور خوش‌آمدگویی نشان داده می‌شود
//    با گزینه‌ی «دیگر نشان نده». تا وقتی تیک نزند، در اجرای بعدیِ برنامه
//    دوباره پیشنهاد می‌شود؛ با تیک‌زدن برای همیشه خاموش می‌شود.
//  • کارت‌ها همیشه در دسترس‌اند (حتی بعد از «دیگر نشان نده»).
// ویجتِ مستقل است و هیچ منطقِ دیگری را تغییر نمی‌دهد. ۶ زبانِ اپ پشتیبانی می‌شود.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/local_storage.dart' show sharedPrefsProvider;
import '../theme/app_theme_colors.dart';

const String _kHideKey = 'zflut-ai-guide-hide-v1';

/// تور فقط یک‌بار در هر اجرای برنامه خودکار باز می‌شود.
bool _shownThisSession = false;

class _Guide {
  final IconData icon;
  final List<Color> colors;
  final Map<String, String> title;
  final Map<String, String> teaser;
  final Map<String, List<String>> steps;
  final Map<String, String> tip;
  const _Guide({
    required this.icon,
    required this.colors,
    required this.title,
    required this.teaser,
    required this.steps,
    required this.tip,
  });
}

const Map<String, Map<String, String>> _ui = {
  'quick': {
    'fa': 'راهنمای سریع',
    'en': 'Quick guide',
    'es': 'Guía rápida',
    'de': 'Kurzanleitung',
    'fr': 'Guide rapide',
    'ar': 'دليل سريع',
  },
  'all': {
    'fa': 'نمایش همه',
    'en': 'Show all',
    'es': 'Ver todo',
    'de': 'Alle ansehen',
    'fr': 'Tout voir',
    'ar': 'عرض الكل',
  },
  'hint': {
    'fa': 'روی هر کارت بزن تا راهنمایش را ببینی',
    'en': 'Tap a card to see its guide',
    'es': 'Toca una tarjeta para ver su guía',
    'de': 'Tippe auf eine Karte für die Anleitung',
    'fr': 'Touche une carte pour voir son guide',
    'ar': 'المس بطاقة لعرض دليلها',
  },
  'welcome': {
    'fa': 'با مربیِ هوشمندت آشنا شو',
    'en': 'Meet your AI coach',
    'es': 'Conoce a tu coach de IA',
    'de': 'Lerne deinen KI-Coach kennen',
    'fr': 'Découvre ton coach IA',
    'ar': 'تعرّف على مدرّبك الذكي',
  },
  'tip': {
    'fa': 'نکته',
    'en': 'Pro tip',
    'es': 'Consejo',
    'de': 'Tipp',
    'fr': 'Astuce',
    'ar': 'نصيحة',
  },
  'next': {
    'fa': 'بعدی',
    'en': 'Next',
    'es': 'Siguiente',
    'de': 'Weiter',
    'fr': 'Suivant',
    'ar': 'التالي',
  },
  'back': {
    'fa': 'قبلی',
    'en': 'Back',
    'es': 'Atrás',
    'de': 'Zurück',
    'fr': 'Retour',
    'ar': 'السابق',
  },
  'done': {
    'fa': 'فهمیدم',
    'en': 'Got it',
    'es': 'Entendido',
    'de': 'Verstanden',
    'fr': 'Compris',
    'ar': 'فهمت',
  },
  'never': {
    'fa': 'دیگر نشان نده',
    'en': 'Don’t show again',
    'es': 'No volver a mostrar',
    'de': 'Nicht mehr anzeigen',
    'fr': 'Ne plus afficher',
    'ar': 'عدم الإظهار مجددًا',
  },
};

const List<_Guide> _guides = [
  // ── ۱) گفتگو با Jimmy ──
  _Guide(
    icon: Icons.chat_bubble_rounded,
    colors: [Color(0xFF8B7CF6), Color(0xFF6366F1)],
    title: {
      'fa': 'گفتگو با Jimmy',
      'en': 'Chat with Jimmy',
      'es': 'Chatea con Jimmy',
      'de': 'Chatten mit Jimmy',
      'fr': 'Discute avec Jimmy',
      'ar': 'الدردشة مع Jimmy',
    },
    teaser: {
      'fa': 'بنویس، اشتباهت را ببین و همان لحظه یاد بگیر',
      'en': 'Write, see your mistakes and learn instantly',
      'es': 'Escribe, ve tus errores y aprende al instante',
      'de': 'Schreibe, sieh deine Fehler und lerne sofort',
      'fr': 'Écris, vois tes erreurs et apprends aussitôt',
      'ar': 'اكتب، شاهد أخطاءك وتعلّم فورًا',
    },
    steps: {
      'fa': [
        'بالای صفحه «زبان تمرین» را انتخاب کن.',
        'هر چیزی را به همان زبان بنویس و بفرست.',
        'Jimmy جواب می‌دهد؛ اشتباه‌هایت با رنگ قرمز و شکل درستشان با رنگ سبز نشان داده می‌شود و به زبان مادری‌ات توضیح می‌دهد.',
      ],
      'en': [
        'Pick your “Practice language” at the top.',
        'Write anything in that language and send it.',
        'Jimmy replies, shows your mistakes in red and the corrected version in green, and explains in your native language.',
      ],
      'es': [
        'Elige tu «Idioma de práctica» arriba.',
        'Escribe lo que quieras en ese idioma y envíalo.',
        'Jimmy responde, marca tus errores en rojo y la versión correcta en verde, y lo explica en tu idioma nativo.',
      ],
      'de': [
        'Wähle oben deine „Übungssprache“.',
        'Schreibe etwas in dieser Sprache und sende es ab.',
        'Jimmy antwortet, markiert Fehler rot und die richtige Version grün und erklärt es in deiner Muttersprache.',
      ],
      'fr': [
        'Choisis ta « langue d’entraînement » en haut.',
        'Écris ce que tu veux dans cette langue et envoie.',
        'Jimmy répond, signale tes erreurs en rouge et la version correcte en vert, puis explique dans ta langue maternelle.',
      ],
      'ar': [
        'اختر «لغة التدرّب» في الأعلى.',
        'اكتب ما تشاء بهذه اللغة وأرسله.',
        'يردّ Jimmy ويُظهر أخطاءك بالأحمر والصيغة الصحيحة بالأخضر، ويشرح بلغتك الأم.',
      ],
    },
    tip: {
      'fa': 'از اشتباه نترس؛ هر اصلاح یک درس رایگان است.',
      'en': 'Don’t fear mistakes — every correction is a free lesson.',
      'es': 'No temas equivocarte: cada corrección es una lección gratis.',
      'de': 'Keine Angst vor Fehlern – jede Korrektur ist eine Gratis-Lektion.',
      'fr': 'N’aie pas peur des erreurs : chaque correction est une leçon gratuite.',
      'ar': 'لا تخَف من الأخطاء؛ كل تصحيح درس مجاني.',
    },
  ),

  // ── ۲) ویدیو کال ──
  _Guide(
    icon: Icons.videocam_rounded,
    colors: [Color(0xFF14B8A6), Color(0xFF0EA5E9)],
    title: {
      'fa': 'ویدیو کال با AI',
      'en': 'Video call with AI',
      'es': 'Videollamada con IA',
      'de': 'Videoanruf mit KI',
      'fr': 'Appel vidéo avec l’IA',
      'ar': 'مكالمة فيديو مع الذكاء الاصطناعي',
    },
    teaser: {
      'fa': 'حرف بزن و جواب صوتی بگیر، مثل یک تماس واقعی',
      'en': 'Speak and hear answers, like a real call',
      'es': 'Habla y escucha respuestas, como una llamada real',
      'de': 'Sprich und höre Antworten – wie ein echter Anruf',
      'fr': 'Parle et écoute les réponses, comme un vrai appel',
      'ar': 'تحدّث واسمع الردود كمكالمة حقيقية',
    },
    steps: {
      'fa': [
        'از نوار زیر شخصیت، از «چت» به «ویدیو کال» برو.',
        'میکروفون را بزن و حرف بزن؛ مربی با صدا جواب می‌دهد.',
        'با «دست‌آزاد» شروع و پایان صحبتت خودکار می‌شود. اگر نمی‌خواهی حرف بزنی، دکمه‌ی نوشتن را بزن.',
      ],
      'en': [
        'Switch from “Chat” to “Call” in the bar under the persona.',
        'Tap the mic and speak; your coach answers out loud.',
        'Turn on “Hands-free” to start and stop automatically. Prefer not to talk? Tap the keyboard button to type.',
      ],
      'es': [
        'Cambia de «Chat» a «Llamada» en la barra bajo el personaje.',
        'Toca el micrófono y habla; tu coach responde en voz alta.',
        'Activa «Manos libres» para empezar y parar solo. ¿No quieres hablar? Toca el teclado para escribir.',
      ],
      'de': [
        'Wechsle in der Leiste unter der Figur von „Chat“ zu „Anruf“.',
        'Tippe aufs Mikrofon und sprich; dein Coach antwortet laut.',
        'Mit „Freisprechen“ startet und stoppt es automatisch. Lieber tippen? Nutze die Tastatur-Taste.',
      ],
      'fr': [
        'Passe de « Chat » à « Appel » dans la barre sous le personnage.',
        'Touche le micro et parle ; ton coach répond à voix haute.',
        'Active « Mains libres » pour démarrer et arrêter automatiquement. Pas envie de parler ? Touche le clavier pour écrire.',
      ],
      'ar': [
        'بدّل من «دردشة» إلى «مكالمة» في الشريط أسفل الشخصية.',
        'المس الميكروفون وتحدّث؛ يردّ مدرّبك بصوت مسموع.',
        'فعّل «بدون استخدام اليدين» للبدء والإيقاف تلقائيًا. تفضّل الكتابة؟ المس زر لوحة المفاتيح.',
      ],
    },
    tip: {
      'fa': 'بار اول، دستیار صوتی چند لحظه آماده می‌شود. تشخیص صدا روی اندروید کار می‌کند.',
      'en': 'The first call takes a moment to set up the voice assistant. Voice recognition works on Android.',
      'es': 'La primera llamada tarda un momento en preparar el asistente de voz. El reconocimiento de voz funciona en Android.',
      'de': 'Beim ersten Anruf wird der Sprachassistent kurz vorbereitet. Spracherkennung funktioniert auf Android.',
      'fr': 'Le premier appel prépare l’assistant vocal quelques instants. La reconnaissance vocale fonctionne sur Android.',
      'ar': 'في أول مكالمة يستغرق تجهيز المساعد الصوتي لحظات. التعرّف على الصوت يعمل على أندرويد.',
    },
  ),

  // ── ۳) شخصیت‌ها ──
  _Guide(
    icon: Icons.theater_comedy_rounded,
    colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
    title: {
      'fa': 'شخصیت‌ها و سناریوها',
      'en': 'Personas & scenarios',
      'es': 'Personajes y escenarios',
      'de': 'Figuren & Szenarien',
      'fr': 'Personnages & scénarios',
      'ar': 'الشخصيات والسيناريوهات',
    },
    teaser: {
      'fa': 'با باریستا، مصاحبه‌گر یا هر نقشی که بخواهی صحبت کن',
      'en': 'Talk to a barista, an interviewer or any role you like',
      'es': 'Habla con un barista, un entrevistador o el rol que quieras',
      'de': 'Sprich mit Barista, Interviewer oder jeder Rolle',
      'fr': 'Parle à un barista, un recruteur ou le rôle de ton choix',
      'ar': 'تحدّث مع باريستا أو مُحاوِر أو أي دور تريده',
    },
    steps: {
      'fa': [
        'کارت شخصیت («با چه کسی صحبت کنم؟») را بزن و یک نقش انتخاب کن؛ مثلاً باریستا، مصاحبه‌گر، پزشک یا دوست.',
        'با «ساختِ شخصیتِ جدید» شخصیت دلخواهت را بساز: اسم، نقش، لحن، موقعیت، عکس و سطح زبان.',
        'شخصیت‌های آماده را می‌توانی کپی و ویرایش کنی.',
      ],
      'en': [
        'Tap the persona card (“Who do you want to talk to?”) and pick a role — barista, interviewer, doctor, friend…',
        'Tap “Create a new persona” to design your own: name, role, personality, situation, photo and language level.',
        'You can copy and edit the built-in personas.',
      ],
      'es': [
        'Toca la tarjeta del personaje («¿Con quién quieres hablar?») y elige un rol: barista, entrevistador, médico, amigo…',
        'Toca «Crear un nuevo personaje» para diseñar el tuyo: nombre, rol, personalidad, situación, foto y nivel.',
        'Puedes copiar y editar los personajes incluidos.',
      ],
      'de': [
        'Tippe auf die Figurenkarte („Mit wem möchtest du sprechen?“) und wähle eine Rolle – Barista, Interviewer, Arzt, Freund…',
        'Mit „Neue Figur erstellen“ gestaltest du deine eigene: Name, Rolle, Persönlichkeit, Situation, Foto und Sprachniveau.',
        'Vorhandene Figuren kannst du kopieren und bearbeiten.',
      ],
      'fr': [
        'Touche la carte du personnage (« Avec qui veux-tu parler ? ») et choisis un rôle : barista, recruteur, médecin, ami…',
        'Touche « Créer un nouveau personnage » pour concevoir le tien : nom, rôle, personnalité, situation, photo et niveau.',
        'Tu peux copier et modifier les personnages fournis.',
      ],
      'ar': [
        'المس بطاقة الشخصية («مع من تريد التحدّث؟») واختر دورًا: باريستا، مُحاوِر، طبيب، صديق…',
        'المس «إنشاء شخصية جديدة» لتصمّم شخصيتك: الاسم والدور والطباع والموقف والصورة ومستوى اللغة.',
        'يمكنك نسخ الشخصيات الجاهزة وتعديلها.',
      ],
    },
    tip: {
      'fa': 'موقعیتی را که واقعاً پیش می‌آید تمرین کن؛ مثل مصاحبه‌ی کاری یا کنترل پاسپورت.',
      'en': 'Rehearse a real situation before it happens — a job interview or airport check-in.',
      'es': 'Ensaya una situación real antes de vivirla: una entrevista o el control en el aeropuerto.',
      'de': 'Übe eine echte Situation vorab – Vorstellungsgespräch oder Check-in am Flughafen.',
      'fr': 'Répète une situation réelle avant qu’elle arrive : entretien d’embauche ou enregistrement à l’aéroport.',
      'ar': 'تدرّب على موقف حقيقي قبل حدوثه، كمقابلة عمل أو إجراءات المطار.',
    },
  ),

  // ── ۴) تصحیحات → گرامر ──
  _Guide(
    icon: Icons.spellcheck_rounded,
    colors: [Color(0xFF22C55E), Color(0xFF15803D)],
    title: {
      'fa': 'تصحیحات و گرامر',
      'en': 'Corrections & grammar',
      'es': 'Correcciones y gramática',
      'de': 'Korrekturen & Grammatik',
      'fr': 'Corrections & grammaire',
      'ar': 'التصحيحات والقواعد',
    },
    teaser: {
      'fa': 'اشتباه‌هایت را ذخیره کن و بعداً مرور کن',
      'en': 'Save your mistakes and review them later',
      'es': 'Guarda tus errores y repásalos después',
      'de': 'Speichere deine Fehler und wiederhole sie später',
      'fr': 'Enregistre tes erreurs et révise-les plus tard',
      'ar': 'احفظ أخطاءك وراجعها لاحقًا',
    },
    steps: {
      'fa': [
        'بعد از هر پیام، کادر «تصحیحات» نشان می‌دهد چه چیزی باید درست شود.',
        'روی «ذخیره در گرامر» بزن تا این تصحیحات نگه داشته شوند.',
        'بعداً در بخش گرامر آن‌ها را مرور کن.',
      ],
      'en': [
        'After each message, the “Corrections” box shows what to fix.',
        'Tap “Save to grammar” to keep those corrections.',
        'Review them later in the Grammar section.',
      ],
      'es': [
        'Tras cada mensaje, el cuadro «Correcciones» muestra qué mejorar.',
        'Toca «Guardar en gramática» para conservarlas.',
        'Repásalas después en la sección Gramática.',
      ],
      'de': [
        'Nach jeder Nachricht zeigt das Feld „Korrekturen“, was zu verbessern ist.',
        'Tippe auf „In Grammatik speichern“, um sie zu behalten.',
        'Wiederhole sie später im Bereich Grammatik.',
      ],
      'fr': [
        'Après chaque message, l’encadré « Corrections » montre quoi améliorer.',
        'Touche « Enregistrer dans la grammaire » pour les garder.',
        'Révise-les ensuite dans la section Grammaire.',
      ],
      'ar': [
        'بعد كل رسالة يعرض مربّع «التصحيحات» ما يجب إصلاحه.',
        'المس «حفظ في القواعد» للاحتفاظ بها.',
        'راجعها لاحقًا في قسم القواعد.',
      ],
    },
    tip: {
      'fa': 'تصحیحات ذخیره‌شده، فهرست شخصیِ نقطه‌ضعف‌های توست.',
      'en': 'Saved corrections become your personal list of weak spots.',
      'es': 'Las correcciones guardadas son tu lista personal de puntos débiles.',
      'de': 'Gespeicherte Korrekturen sind deine persönliche Schwächenliste.',
      'fr': 'Les corrections enregistrées forment ta liste personnelle de points faibles.',
      'ar': 'التصحيحات المحفوظة هي قائمتك الشخصية لنقاط الضعف.',
    },
  ),

  // ── ۵) ابزارهای پیام ──
  _Guide(
    icon: Icons.touch_app_rounded,
    colors: [Color(0xFFEC4899), Color(0xFFF43F5E)],
    title: {
      'fa': 'ابزارهای هر پیام',
      'en': 'Message tools',
      'es': 'Herramientas del mensaje',
      'de': 'Nachrichten-Werkzeuge',
      'fr': 'Outils du message',
      'ar': 'أدوات الرسائل',
    },
    teaser: {
      'fa': 'گوش بده، ترجمه کن، ویرایش یا دوباره بساز',
      'en': 'Listen, translate, edit or regenerate',
      'es': 'Escucha, traduce, edita o regenera',
      'de': 'Anhören, übersetzen, bearbeiten oder neu erzeugen',
      'fr': 'Écoute, traduis, modifie ou régénère',
      'ar': 'استمع، ترجم، عدّل أو أعد التوليد',
    },
    steps: {
      'fa': [
        'روی 🔊 بزن تا جواب را بشنوی. با «خوانش خودکار» همه‌ی جواب‌ها خودشان خوانده می‌شوند.',
        'روی هر کلمه یا جمله بزن تا کارت ترجمه‌اش باز شود.',
        'زیر پیامت می‌توانی ویرایش و دوباره ارسال کنی، یا جواب را «رفرش» کنی. روی پیام لمس طولانی کن تا چند پیام را انتخاب و حذف کنی.',
      ],
      'en': [
        'Tap 🔊 to hear a reply. Turn on “Auto-read” to hear every reply automatically.',
        'Tap any word or sentence to open its translation card.',
        'Under your message you can edit and resend, or “Refresh” the answer. Long-press a message to select and delete several.',
      ],
      'es': [
        'Toca 🔊 para oír una respuesta. Activa «Lectura automática» para oírlas todas solas.',
        'Toca cualquier palabra o frase para abrir su tarjeta de traducción.',
        'Bajo tu mensaje puedes editar y reenviar, o «Actualizar» la respuesta. Mantén pulsado un mensaje para seleccionar y borrar varios.',
      ],
      'de': [
        'Tippe auf 🔊, um eine Antwort zu hören. Mit „Automatisch vorlesen“ werden alle Antworten vorgelesen.',
        'Tippe auf ein Wort oder einen Satz, um die Übersetzungskarte zu öffnen.',
        'Unter deiner Nachricht kannst du bearbeiten und erneut senden oder die Antwort „Aktualisieren“. Lange drücken, um mehrere Nachrichten zu wählen und zu löschen.',
      ],
      'fr': [
        'Touche 🔊 pour écouter une réponse. Active « Lecture auto » pour toutes les entendre.',
        'Touche un mot ou une phrase pour ouvrir sa carte de traduction.',
        'Sous ton message, tu peux modifier et renvoyer, ou « Actualiser » la réponse. Appui long sur un message pour en sélectionner et supprimer plusieurs.',
      ],
      'ar': [
        'المس 🔊 لسماع الرد. فعّل «القراءة التلقائية» لسماع كل الردود تلقائيًا.',
        'المس أي كلمة أو جملة لفتح بطاقة ترجمتها.',
        'تحت رسالتك يمكنك التعديل وإعادة الإرسال أو «تحديث» الإجابة. اضغط مطولًا على رسالة لتحديد عدة رسائل وحذفها.',
      ],
    },
    tip: {
      'fa': 'برای شروع از صفر، «پاک کردن گفتگو» را بزن.',
      'en': 'Use “Clear conversation” to start fresh.',
      'es': 'Usa «Borrar conversación» para empezar de cero.',
      'de': 'Mit „Unterhaltung löschen“ beginnst du neu.',
      'fr': 'Utilise « Effacer la conversation » pour repartir de zéro.',
      'ar': 'استخدم «مسح المحادثة» للبدء من جديد.',
    },
  ),

  // ── ۶) تاریخچه ──
  _Guide(
    icon: Icons.history_rounded,
    colors: [Color(0xFF0EA5E9), Color(0xFF3B82F6)],
    title: {
      'fa': 'تاریخچه‌ی مکالمات',
      'en': 'Conversation history',
      'es': 'Historial de conversaciones',
      'de': 'Gesprächsverlauf',
      'fr': 'Historique des conversations',
      'ar': 'سجل المحادثات',
    },
    teaser: {
      'fa': 'هر مکالمه را نگه دار و هر وقت خواستی ادامه بده',
      'en': 'Keep any chat and continue it any time',
      'es': 'Guarda cualquier chat y continúalo cuando quieras',
      'de': 'Speichere jeden Chat und setze ihn jederzeit fort',
      'fr': 'Garde n’importe quel chat et reprends-le à tout moment',
      'ar': 'احتفظ بأي محادثة وتابعها في أي وقت',
    },
    steps: {
      'fa': [
        'روی «ذخیره در تاریخچه» بزن تا مکالمه نگه داشته شود.',
        'کارت «تاریخچه مکالمات» را باز کن؛ جدیدترین‌ها بالا هستند.',
        'هر مکالمه را باز کن تا ادامه بدهی، پیام‌هایت را ویرایش کنی یا پیام‌ها را حذف کنی.',
      ],
      'en': [
        'Tap “Save to history” to keep a conversation.',
        'Open the “Conversation history” card — newest chats come first.',
        'Open any chat to continue it, edit your messages or delete some.',
      ],
      'es': [
        'Toca «Guardar en el historial» para conservar una conversación.',
        'Abre la tarjeta «Historial de conversaciones»: los más recientes van primero.',
        'Abre cualquier chat para continuarlo, editar tus mensajes o borrar algunos.',
      ],
      'de': [
        'Tippe auf „Im Verlauf speichern“, um ein Gespräch zu behalten.',
        'Öffne die Karte „Gesprächsverlauf“ – die neuesten Chats stehen oben.',
        'Öffne einen Chat, um ihn fortzusetzen, deine Nachrichten zu bearbeiten oder einige zu löschen.',
      ],
      'fr': [
        'Touche « Enregistrer dans l’historique » pour garder une conversation.',
        'Ouvre la carte « Historique des conversations » : les plus récentes en premier.',
        'Ouvre un chat pour le continuer, modifier tes messages ou en supprimer.',
      ],
      'ar': [
        'المس «حفظ في السجل» للاحتفاظ بالمحادثة.',
        'افتح بطاقة «سجل المحادثات»؛ الأحدث في الأعلى.',
        'افتح أي محادثة لمتابعتها أو تعديل رسائلك أو حذف بعضها.',
      ],
    },
    tip: {
      'fa': 'مکالمه‌ها فقط روی همین گوشی ذخیره می‌شوند.',
      'en': 'Conversations are stored only on this phone.',
      'es': 'Las conversaciones se guardan solo en este teléfono.',
      'de': 'Gespräche werden nur auf diesem Handy gespeichert.',
      'fr': 'Les conversations sont stockées uniquement sur ce téléphone.',
      'ar': 'تُحفظ المحادثات على هذا الهاتف فقط.',
    },
  ),
];

String _lang(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  return const ['fa', 'en', 'es', 'de', 'fr', 'ar'].contains(code) ? code : 'en';
}

String _u(String lang, String key) => _ui[key]![lang] ?? _ui[key]!['en']!;

TextDirection _dir(String lang) =>
    (lang == 'fa' || lang == 'ar') ? TextDirection.rtl : TextDirection.ltr;

/// بخشِ «راهنمای سریع» — زیرِ کارت‌های سوئیچِ مکالمه گذاشته می‌شود.
class AiGuideSection extends ConsumerStatefulWidget {
  /// اگر false باشد تورِ خوش‌آمدگویی خودکار باز نمی‌شود.
  final bool autoShow;
  const AiGuideSection({super.key, this.autoShow = true});

  @override
  ConsumerState<AiGuideSection> createState() => _AiGuideSectionState();
}

class _AiGuideSectionState extends ConsumerState<AiGuideSection> {
  @override
  void initState() {
    super.initState();
    if (widget.autoShow) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoShow());
    }
  }

  void _maybeAutoShow() {
    if (!mounted || _shownThisSession) return;
    var hide = false;
    try {
      hide = ref.read(sharedPrefsProvider).getBool(_kHideKey) ?? false;
    } catch (_) {}
    if (hide) return;
    _shownThisSession = true;
    _open(0, welcome: true);
  }

  Future<void> _open(int start, {bool welcome = false}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GuideSheet(start: start, welcome: welcome),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final lang = _lang(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF8B7CF6), Color(0xFF6366F1)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  size: 15, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_u(lang, 'quick'),
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                  Text(_u(lang, 'hint'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.inkSoft, fontSize: 10.5)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _open(0),
              style: TextButton.styleFrom(
                foregroundColor: c.gold,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(_u(lang, 'all'),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: _guides.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _GuideCard(
              guide: _guides[i],
              lang: lang,
              index: i,
              onTap: () => _open(i),
            ),
          ),
        ),
      ],
    );
  }
}

class _GuideCard extends StatelessWidget {
  final _Guide guide;
  final String lang;
  final int index;
  final VoidCallback onTap;
  const _GuideCard({
    required this.guide,
    required this.lang,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final g = guide.colors.first;
    return Container(
      width: 152,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: guide.colors,
                        ),
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                            color: g.withOpacity(0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(guide.icon, size: 21, color: Colors.white),
                    ),
                    const Spacer(),
                    Text('${index + 1}',
                        style: TextStyle(
                            color: c.inkSoft.withOpacity(0.5),
                            fontSize: 18,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(guide.title[lang] ?? guide.title['en']!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.ink,
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(guide.teaser[lang] ?? guide.teaser['en']!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.inkSoft, fontSize: 10.5, height: 1.35)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideSheet extends ConsumerStatefulWidget {
  final int start;
  final bool welcome;
  const _GuideSheet({required this.start, required this.welcome});

  @override
  ConsumerState<_GuideSheet> createState() => _GuideSheetState();
}

class _GuideSheetState extends ConsumerState<_GuideSheet> {
  late final PageController _ctrl;
  late int _page;
  bool _never = false;

  @override
  void initState() {
    super.initState();
    _page = widget.start.clamp(0, _guides.length - 1);
    _ctrl = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _setNever(bool v) {
    setState(() => _never = v);
    try {
      ref.read(sharedPrefsProvider).setBool(_kHideKey, v);
    } catch (_) {}
  }

  void _go(int i) {
    _ctrl.animateToPage(i,
        duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final lang = _lang(context);
    final mq = MediaQuery.of(context);
    final h = (mq.size.height * 0.84).clamp(420.0, 680.0);
    final last = _page == _guides.length - 1;
    final cur = _guides[_page];

    return Directionality(
      textDirection: _dir(lang),
      child: Container(
        height: h,
        padding: EdgeInsets.only(bottom: mq.padding.bottom),
        decoration: BoxDecoration(
          color: c.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: c.cardBorder),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: c.inkSoft.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.welcome
                          ? _u(lang, 'welcome')
                          : _u(lang, 'quick'),
                      style: TextStyle(
                          color: c.inkSoft,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text('${_page + 1} / ${_guides.length}',
                      style: TextStyle(
                          color: c.inkSoft,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: c.inkSoft),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                itemCount: _guides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _GuidePage(guide: _guides[i], lang: lang),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _guides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? cur.colors.first
                          : c.inkSoft.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            if (widget.welcome)
              InkWell(
                onTap: () => _setNever(!_never),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _never,
                          activeColor: c.gold,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: (v) => _setNever(v ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_u(lang, 'never'),
                          style: TextStyle(color: c.ink, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                children: [
                  if (_page > 0) ...[
                    OutlinedButton(
                      onPressed: () => _go(_page - 1),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.ink,
                        side: BorderSide(color: c.cardBorder),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(_u(lang, 'back')),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: last
                          ? () => Navigator.of(context).pop()
                          : () => _go(_page + 1),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.gold,
                        foregroundColor: c.headerTo,
                        elevation: 0,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        last ? _u(lang, 'done') : _u(lang, 'next'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidePage extends StatelessWidget {
  final _Guide guide;
  final String lang;
  const _GuidePage({required this.guide, required this.lang});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final steps = guide.steps[lang] ?? guide.steps['en']!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: guide.colors,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: guide.colors.first.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(guide.icon, size: 38, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              guide.title[lang] ?? guide.title['en']!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.ink, fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              guide.teaser[lang] ?? guide.teaser['en']!,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkSoft, fontSize: 13, height: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.cardBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: guide.colors),
                        shape: BoxShape.circle,
                      ),
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(steps[i],
                          style: TextStyle(
                              color: c.ink, fontSize: 13.5, height: 1.6)),
                    ),
                  ],
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.goldSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.gold.withOpacity(0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_rounded, size: 20, color: c.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style:
                          TextStyle(color: c.ink, fontSize: 13, height: 1.55),
                      children: [
                        TextSpan(
                            text: '${_u(lang, 'tip')}: ',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        TextSpan(text: guide.tip[lang] ?? guide.tip['en']!),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
