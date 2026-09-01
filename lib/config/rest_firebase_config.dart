/// Process-wide Firebase project config for the REST-backed service
/// implementations used on platforms `firebase_core` has no native plugin
/// for (Linux desktop — there is no native Firebase SDK for it at all, so
/// `Firebase.initializeApp()` itself would throw there).
///
/// The composing app calls [configure] exactly once at startup — instead
/// of `Firebase.initializeApp()`, not in addition to it — before
/// constructing any Firebase-backed SDK service, on Linux only.
class RestFirebaseConfig {
  RestFirebaseConfig._({required this.projectId, required this.apiKey});

  static RestFirebaseConfig? _current;

  static void configure({required String projectId, required String apiKey}) {
    _current = RestFirebaseConfig._(projectId: projectId, apiKey: apiKey);
  }

  static RestFirebaseConfig get current =>
      _current ??
      (throw StateError(
        'RestFirebaseConfig.configure() was never called. The composing '
        'app must call it once at startup, instead of Firebase.initializeApp(), '
        'on Linux.',
      ));

  final String projectId;
  final String apiKey;

  /// Returns a valid Firebase ID token for the current session, refreshing
  /// it first if necessary, or `null` if signed out. Set by [RestAuthService]
  /// as soon as it's constructed; read here at request time (not captured
  /// once) so construction order between the REST auth/repository services
  /// doesn't matter.
  Future<String?> Function()? idTokenProvider;
}
