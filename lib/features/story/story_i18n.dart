// 📁 مسیر: lib/features/story/story_i18n.dart
//
// متن‌های نمایشگرِ PDF / نوارِ ترجمه‌ی کتاب / حالت‌های نمایشِ ترجمه — بر اساسِ زبانِ رابطِ برنامه
// (fa, en, ar, de, es, fr). زبانِ ناشناخته ← انگلیسی. {n} و {m} با مقدار جایگزین می‌شوند.
import 'package:flutter/widgets.dart';

const Map<String, List<String>> _t = {
  // کلید: [fa, en, ar, de, es, fr]
  'pageText': ['متنِ صفحه‌ی {n}', 'Page {n} text', 'نص الصفحة {n}', 'Text von Seite {n}', 'Texto de la página {n}', 'Texte de la page {n}'],
  'pageOf': ['صفحه‌ی {n} از {m}', 'Page {n} of {m}', 'الصفحة {n} من {m}', 'Seite {n} von {m}', 'Página {n} de {m}', 'Page {n} sur {m}'],
  'reading': ['در حال خواندنِ متنِ این صفحه...', 'Reading this page’s text…', 'جارٍ قراءة نص هذه الصفحة…', 'Text dieser Seite wird gelesen …', 'Leyendo el texto de esta página…', 'Lecture du texte de cette page…'],
  'noText': [
    'این صفحه متنِ قابل‌خواندن نداره — احتمالاً فقط عکسه. برای دیدنِ ترجمه روی خودِ عکس، دکمه‌ی «ترجمه‌ی عکسیِ صفحه‌ها» رو بزن.',
    'This page has no readable text — it is probably just an image. To see the translation on the image itself, use the page image translation button.',
    'لا يوجد نص قابل للقراءة في هذه الصفحة — غالباً هي صورة فقط. لرؤية الترجمة على الصورة نفسها، استخدم زر ترجمة صور الصفحات.',
    'Diese Seite enthält keinen lesbaren Text – wahrscheinlich nur ein Bild. Für die Übersetzung direkt auf dem Bild nutze die Schaltfläche zur Bildübersetzung der Seiten.',
    'Esta página no tiene texto legible; probablemente solo es una imagen. Para ver la traducción sobre la propia imagen, usa el botón de traducción de imágenes de páginas.',
    'Cette page n’a pas de texte lisible — c’est probablement juste une image. Pour voir la traduction sur l’image elle-même, utilise le bouton de traduction d’image des pages.',
  ],
  'close': ['بستن', 'Close', 'إغلاق', 'Schließen', 'Cerrar', 'Fermer'],
  'save': ['ذخیره', 'Save', 'حفظ', 'Speichern', 'Guardar', 'Enregistrer'],
  'saving': ['در حال ذخیره…', 'Saving…', 'جارٍ الحفظ…', 'Wird gespeichert …', 'Guardando…', 'Enregistrement…'],
  'savePdf': ['ذخیره‌ی PDF', 'Save PDF', 'حفظ PDF', 'PDF speichern', 'Guardar PDF', 'Enregistrer le PDF'],
  'savingPdf': ['در حال ساختنِ PDF…', 'Building PDF…', 'جارٍ إنشاء PDF…', 'PDF wird erstellt …', 'Creando PDF…', 'Création du PDF…'],
  'savedOk': ['ذخیره شد ✓', 'Saved ✓', 'تم الحفظ ✓', 'Gespeichert ✓', 'Guardado ✓', 'Enregistré ✓'],
  'saveFail': ['ذخیره انجام نشد', 'Could not save', 'تعذّر الحفظ', 'Speichern fehlgeschlagen', 'No se pudo guardar', 'Échec de l’enregistrement'],
  'whichText': ['کدام متن ذخیره شود؟', 'Which text to save?', 'أي نص تريد حفظه؟', 'Welcher Text soll gespeichert werden?', '¿Qué texto guardar?', 'Quel texte enregistrer ?'],
  'onlyThisPage': ['فقط همین صفحه', 'This page only', 'هذه الصفحة فقط', 'Nur diese Seite', 'Solo esta página', 'Cette page seulement'],
  'allPages': ['همه‌ی صفحه‌ها', 'All pages', 'كل الصفحات', 'Alle Seiten', 'Todas las páginas', 'Toutes les pages'],
  'textSavedPage': ['متنِ صفحه در داستان‌ساز ذخیره شد ✓', 'Page text saved to Story maker ✓', 'تم حفظ نص الصفحة في صانع القصص ✓', 'Seitentext im Story-Maker gespeichert ✓', 'Texto de la página guardado en el creador de historias ✓', 'Texte de la page enregistré dans le créateur d’histoires ✓'],
  'noTextPage': ['این صفحه متنی برای ذخیره ندارد', 'This page has no text to save', 'لا يوجد نص لحفظه في هذه الصفحة', 'Diese Seite hat keinen Text zum Speichern', 'Esta página no tiene texto para guardar', 'Cette page n’a pas de texte à enregistrer'],
  'textSavedAll': ['متنِ همه‌ی صفحه‌ها در داستان‌ساز ذخیره شد ✓', 'Text of all pages saved to Story maker ✓', 'تم حفظ نص كل الصفحات في صانع القصص ✓', 'Text aller Seiten im Story-Maker gespeichert ✓', 'Texto de todas las páginas guardado en el creador de historias ✓', 'Texte de toutes les pages enregistré dans le créateur d’histoires ✓'],
  'noTextFound': ['متنی برای ذخیره پیدا نشد', 'No text found to save', 'لم يُعثر على نص للحفظ', 'Kein Text zum Speichern gefunden', 'No se encontró texto para guardar', 'Aucun texte à enregistrer'],
  'saveTextFail': ['ذخیره‌ی متن انجام نشد', 'Could not save the text', 'تعذّر حفظ النص', 'Text konnte nicht gespeichert werden', 'No se pudo guardar el texto', 'Échec de l’enregistrement du texte'],
  'whichImage': ['کدام عکس ذخیره شود؟', 'Which image to save?', 'أي صورة تريد حفظها؟', 'Welches Bild speichern?', '¿Qué imagen guardar?', 'Quelle image enregistrer ?'],
  'imgOrig': ['عکسِ اصلی', 'Original image', 'الصورة الأصلية', 'Originalbild', 'Imagen original', 'Image originale'],
  'imgTrans': ['عکسِ ترجمه‌شده', 'Translated image', 'الصورة المترجمة', 'Übersetztes Bild', 'Imagen traducida', 'Image traduite'],
  'transNotReady': ['ترجمه‌ی این صفحه هنوز آماده نیست', 'This page’s translation isn’t ready yet', 'ترجمة هذه الصفحة ليست جاهزة بعد', 'Die Übersetzung dieser Seite ist noch nicht fertig', 'La traducción de esta página aún no está lista', 'La traduction de cette page n’est pas encore prête'],
  'imgNotReady': ['عکسِ این صفحه هنوز آماده نیست', 'This page’s image isn’t ready yet', 'صورة هذه الصفحة ليست جاهزة بعد', 'Das Bild dieser Seite ist noch nicht fertig', 'La imagen de esta página aún no está lista', 'L’image de cette page n’est pas encore prête'],
  'imgSaved': ['عکس ذخیره شد ✓', 'Image saved ✓', 'تم حفظ الصورة ✓', 'Bild gespeichert ✓', 'Imagen guardada ✓', 'Image enregistrée ✓'],
  'imgSaveFail': ['ذخیره‌ی عکس انجام نشد', 'Could not save the image', 'تعذّر حفظ الصورة', 'Bild konnte nicht gespeichert werden', 'No se pudo guardar la imagen', 'Échec de l’enregistrement de l’image'],
  'whichPdf': ['کدام PDF ذخیره شود؟', 'Which PDF to save?', 'أي PDF تريد حفظه؟', 'Welches PDF speichern?', '¿Qué PDF guardar?', 'Quel PDF enregistrer ?'],
  'pdfTrans': ['PDFِ ترجمه‌شده', 'Translated PDF', 'PDF المترجم', 'Übersetztes PDF', 'PDF traducido', 'PDF traduit'],
  'pdfOrig': ['PDFِ اصلی', 'Original PDF', 'PDF الأصلي', 'Original-PDF', 'PDF original', 'PDF original'],
  'pdfSaved': ['PDF ذخیره شد ✓', 'PDF saved ✓', 'تم حفظ PDF ✓', 'PDF gespeichert ✓', 'PDF guardado ✓', 'PDF enregistré ✓'],
  'pdfSavedMissing': [
    'PDF ذخیره شد ✓ ({n} صفحه هنوز ترجمه نشده بود و به‌صورتِ اصلی آمد)',
    'PDF saved ✓ ({n} pages weren’t translated yet and were kept as original)',
    'تم حفظ PDF ✓ ({n} صفحة لم تُترجم بعد وبقيت كما هي)',
    'PDF gespeichert ✓ ({n} Seiten waren noch nicht übersetzt und blieben im Original)',
    'PDF guardado ✓ ({n} páginas aún no estaban traducidas y se dejaron originales)',
    'PDF enregistré ✓ ({n} pages n’étaient pas encore traduites et sont restées en version originale)',
  ],
  'pdfFail': ['ساختن/ذخیره‌ی PDF انجام نشد', 'Could not build/save the PDF', 'تعذّر إنشاء/حفظ PDF', 'PDF konnte nicht erstellt/gespeichert werden', 'No se pudo crear/guardar el PDF', 'Impossible de créer/enregistrer le PDF'],
  'segBoth': ['اصلی + ترجمه', 'Original + translation', 'الأصل + الترجمة', 'Original + Übersetzung', 'Original + traducción', 'Original + traduction'],
  'segSeeOrig': ['دیدنِ اصلی', 'View original', 'عرض الأصل', 'Original ansehen', 'Ver original', 'Voir l’original'],
  'segSeeTrans': ['دیدنِ ترجمه', 'View translation', 'عرض الترجمة', 'Übersetzung ansehen', 'Ver traducción', 'Voir la traduction'],
  'segOrig': ['اصلی', 'Original', 'الأصل', 'Original', 'Original', 'Original'],
  'segTrans': ['ترجمه', 'Translation', 'الترجمة', 'Übersetzung', 'Traducción', 'Traduction'],
  'msgStart': ['برای دیدنِ ترجمه‌ی عکسی، ترجمه را با دکمه‌ی ▶ شروع کن.', 'To see the image translation, start translating with the ▶ button.', 'لرؤية ترجمة الصورة، ابدأ الترجمة بزر ▶.', 'Für die Bildübersetzung starte die Übersetzung mit ▶.', 'Para ver la traducción de la imagen, inicia la traducción con el botón ▶.', 'Pour voir la traduction de l’image, lance la traduction avec le bouton ▶.'],
  'msgWorking': ['⏳ ترجمه‌ی این صفحه در حال انجام است…', '⏳ Translating this page…', '⏳ جارٍ ترجمة هذه الصفحة…', '⏳ Diese Seite wird übersetzt …', '⏳ Traduciendo esta página…', '⏳ Traduction de cette page…'],
  'msgFailed': ['ترجمه‌ی این صفحه انجام نشد — «تلاشِ دوباره» را بزن.', 'This page couldn’t be translated — tap “Retry”.', 'تعذّرت ترجمة هذه الصفحة — اضغط «إعادة المحاولة».', 'Diese Seite konnte nicht übersetzt werden – tippe auf „Erneut versuchen“.', 'No se pudo traducir esta página: pulsa «Reintentar».', 'Cette page n’a pas pu être traduite — appuie sur « Réessayer ».'],

  'msgEmpty': ['این صفحه متنی برای ترجمه ندارد (همان عکسِ اصلی است).', 'This page has no text to translate (it is the original image).', 'لا يوجد نص للترجمة في هذه الصفحة (هي الصورة الأصلية).', 'Diese Seite hat keinen Text zum Übersetzen (es ist das Originalbild).', 'Esta página no tiene texto para traducir (es la imagen original).', 'Cette page n’a pas de texte à traduire (c’est l’image originale).'],
  'msgNotReady': ['ترجمه‌ی این صفحه هنوز آماده نیست — ▶ را بزن.', 'This page’s translation isn’t ready yet — tap ▶.', 'ترجمة هذه الصفحة ليست جاهزة بعد — اضغط ▶.', 'Die Übersetzung dieser Seite ist noch nicht fertig – tippe auf ▶.', 'La traducción de esta página aún no está lista: pulsa ▶.', 'La traduction de cette page n’est pas encore prête — appuie sur ▶.'],

  // نوارِ ترجمه‌ی کتاب
  'barStopped': ['⏹ متوقف — ادامه از صفحه‌ی {n}', '⏹ Stopped — resume from page {n}', '⏹ متوقف — المتابعة من الصفحة {n}', '⏹ Gestoppt – weiter ab Seite {n}', '⏹ Detenido: continuar desde la página {n}', '⏹ Arrêté — reprendre à la page {n}'],
  'barAllDone': ['✓ همه‌ی صفحه‌ها ترجمه شد', '✓ All pages translated', '✓ تمت ترجمة كل الصفحات', '✓ Alle Seiten übersetzt', '✓ Todas las páginas traducidas', '✓ Toutes les pages sont traduites'],
  'barIdle': ['🌐 ترجمه‌ی عکسیِ صفحه‌ها', '🌐 Page image translation', '🌐 ترجمة صور الصفحات', '🌐 Bildübersetzung der Seiten', '🌐 Traducción de imágenes de páginas', '🌐 Traduction d’images des pages'],
  'barPaused': ['⏸ متوقفِ موقت', '⏸ Paused', '⏸ متوقف مؤقتاً', '⏸ Pausiert', '⏸ En pausa', '⏸ En pause'],
  'barWorking': ['⏳ در حال ترجمه‌ی صفحه‌ی {n}', '⏳ Translating page {n}', '⏳ جارٍ ترجمة الصفحة {n}', '⏳ Seite {n} wird übersetzt', '⏳ Traduciendo la página {n}', '⏳ Traduction de la page {n}'],
  'barReady': ['✓ آماده‌ی ترجمه‌ی صفحه‌ی بعد', '✓ Ready to translate the next page', '✓ جاهز لترجمة الصفحة التالية', '✓ Bereit für die nächste Seite', '✓ Listo para traducir la página siguiente', '✓ Prêt à traduire la page suivante'],
  'resumeFrom': ['ادامه از صفحه‌ی {n}', 'Resume from page {n}', 'المتابعة من الصفحة {n}', 'Weiter ab Seite {n}', 'Continuar desde la página {n}', 'Reprendre à la page {n}'],
  'retranslate': ['ترجمه‌ی دوباره', 'Translate again', 'إعادة الترجمة', 'Erneut übersetzen', 'Traducir de nuevo', 'Traduire à nouveau'],
  'startHere': ['شروع (از همین صفحه)', 'Start (from this page)', 'ابدأ (من هذه الصفحة)', 'Start (ab dieser Seite)', 'Empezar (desde esta página)', 'Démarrer (depuis cette page)'],
  'resume': ['ادامه', 'Resume', 'متابعة', 'Fortsetzen', 'Continuar', 'Reprendre'],
  'pause': ['مکث', 'Pause', 'إيقاف مؤقت', 'Pause', 'Pausa', 'Pause'],
  'stopTip': ['توقف ترجمه‌ی عکسی', 'Stop image translation', 'إيقاف ترجمة الصور', 'Bildübersetzung stoppen', 'Detener la traducción de imágenes', 'Arrêter la traduction d’images'],
  'wholeBook': ['کلِ کتاب (پس‌زمینه)', 'Whole book (background)', 'الكتاب كاملاً (في الخلفية)', 'Ganzes Buch (im Hintergrund)', 'Libro completo (en segundo plano)', 'Livre entier (en arrière-plan)'],
  'retry': ['تلاشِ دوباره ({n} صفحه)', 'Retry ({n} pages)', 'إعادة المحاولة ({n} صفحة)', 'Erneut versuchen ({n} Seiten)', 'Reintentar ({n} páginas)', 'Réessayer ({n} pages)'],
  'pageFailed': ['ترجمه‌ی این صفحه انجام نشد', 'This page couldn’t be translated', 'تعذّرت ترجمة هذه الصفحة', 'Diese Seite konnte nicht übersetzt werden', 'No se pudo traducir esta página', 'Cette page n’a pas pu être traduite'],
  'noteAllDone': ['ترجمه‌ی همه‌ی صفحه‌ها تموم شد ✓', 'All pages translated ✓', 'تمت ترجمة كل الصفحات ✓', 'Alle Seiten übersetzt ✓', 'Todas las páginas traducidas ✓', 'Toutes les pages sont traduites ✓'],
  'noteStopped': ['متوقف شد', 'Stopped', 'تم الإيقاف', 'Gestoppt', 'Detenido', 'Arrêté'],
  'noteNet': [
    'چند صفحه‌ی پشت‌سرهم ترجمه نشد — اینترنتت رو چک کن و «ادامه» رو بزن',
    'Several pages in a row failed — check your internet and tap “Resume”',
    'فشلت ترجمة عدة صفحات متتالية — تحقق من الإنترنت واضغط «متابعة»',
    'Mehrere Seiten hintereinander sind fehlgeschlagen – prüfe dein Internet und tippe auf „Fortsetzen“',
    'Fallaron varias páginas seguidas: revisa tu internet y pulsa «Continuar»',
    'Plusieurs pages d’affilée ont échoué — vérifie ta connexion et appuie sur « Reprendre »',
  ],

  // ناوبریِ صفحه‌ها
  'gotoTitle': ['رفتن به صفحه (۱ تا {n})', 'Go to page (1–{n})', 'الانتقال إلى صفحة (1–{n})', 'Gehe zu Seite (1–{n})', 'Ir a la página (1–{n})', 'Aller à la page (1–{n})'],
  'cancel': ['لغو', 'Cancel', 'إلغاء', 'Abbrechen', 'Cancelar', 'Annuler'],
  'go': ['برو', 'Go', 'انتقال', 'Los', 'Ir', 'Aller'],
  'firstTip': ['صفحه‌ی اول', 'First page', 'الصفحة الأولى', 'Erste Seite', 'Primera página', 'Première page'],
  'prevTip': ['صفحه‌ی قبل (نگه‌دار: ۵ صفحه)', 'Previous page (hold: 5 pages)', 'الصفحة السابقة (اضغط مطولاً: 5 صفحات)', 'Vorherige Seite (halten: 5 Seiten)', 'Página anterior (mantén: 5 páginas)', 'Page précédente (maintenir : 5 pages)'],
  'nextTip': ['صفحه‌ی بعد (نگه‌دار: ۵ صفحه)', 'Next page (hold: 5 pages)', 'الصفحة التالية (اضغط مطولاً: 5 صفحات)', 'Nächste Seite (halten: 5 Seiten)', 'Página siguiente (mantén: 5 páginas)', 'Page suivante (maintenir : 5 pages)'],
  'lastTip': ['صفحه‌ی آخر', 'Last page', 'الصفحة الأخيرة', 'Letzte Seite', 'Última página', 'Dernière page'],

  // حالت‌های نمایشِ ترجمه (در یک ردیف)
  'modeSentence': ['حالت جمله', 'Sentence mode', 'وضع الجملة', 'Satzmodus', 'Modo oración', 'Mode phrase'],
  'modeParagraph': ['حالت پاراگراف', 'Paragraph mode', 'وضع الفقرة', 'Absatzmodus', 'Modo párrafo', 'Mode paragraphe'],
  'modeNone': ['هیچ', 'None', 'بدون', 'Aus', 'Ninguno', 'Aucun'],
};

const List<String> _order = ['fa', 'en', 'ar', 'de', 'es', 'fr'];

/// ترجمه‌ی [key] به زبانِ رابطِ برنامه؛ [n] و [m] جایگزینِ {n} و {m} می‌شوند.
String stTr(BuildContext context, String key, {Object? n, Object? m}) {
  final code = Localizations.localeOf(context).languageCode;
  final idx = _order.indexOf(code);
  final row = _t[key];
  if (row == null) return key;
  var s = row[idx < 0 ? 1 : idx];
  if (n != null) s = s.replaceAll('{n}', '$n');
  if (m != null) s = s.replaceAll('{m}', '$m');
  return s;
}
