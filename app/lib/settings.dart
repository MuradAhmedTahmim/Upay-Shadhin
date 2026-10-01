/// App-level display settings: language and theme.
///
/// These are deliberately global rather than threaded through an InheritedWidget.
/// Both the colour palette (`theme.dart`) and the string table (`i18n.dart`) are read
/// in hundreds of places, many inside `const` constructors, and the root widget rebuilds
/// the whole tree whenever either changes - so a lookup is always consistent with what
/// is on screen. The trade-off is that neither can vary per subtree, which this app
/// never needs.
library;

enum Lang { bn, en }

class Settings {
  Settings._();

  static bool dark = false;
  static Lang lang = Lang.bn;

  static bool get isBn => lang == Lang.bn;

  /// Key into the API's bilingual narrative objects: `{"bn": ..., "en": ...}`.
  static String get narrativeKey => isBn ? 'bn' : 'en';
}
