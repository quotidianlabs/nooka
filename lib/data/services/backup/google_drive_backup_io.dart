import 'dart:convert';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'cloud_backup_io.dart';

/// Google Drive appDataFolder implementation of [CloudBackupIo].
/// EXCLUDED from coverage (platform auth + network) — see coverde.yaml.
class GoogleDriveBackupIo implements CloudBackupIo {
  static const _scope = drive.DriveApi.driveAppdataScope;
  static const _space = 'appDataFolder';

  /// Lazily initializes [GoogleSignIn.instance] exactly once.
  /// The `??=` assignment is safe in Dart's single-threaded event model.
  static Future<void>? _initFuture;

  Future<void> _ensureInitialized() =>
      _initFuture ??= GoogleSignIn.instance.initialize();

  /// Obtains a current OAuth2 access token for [_scope] (silent; no UI) and
  /// returns an authenticated [drive.DriveApi].
  ///
  /// Throws [StateError] if the scope is not yet authorized — callers must
  /// call [connect] first.
  Future<drive.DriveApi> _api() async {
    await _ensureInitialized();
    final auth = await GoogleSignIn.instance.authorizationClient
        .authorizationForScopes([_scope]);
    if (auth == null) {
      throw StateError(
        'Drive appdata scope not authorized; call connect() first.',
      );
    }
    return drive.DriveApi(_AuthenticatedClient(auth.accessToken));
  }

  /// Returns the currently signed-in account via a lightweight (silent)
  /// authentication attempt, or null if no account is available without
  /// showing any UI.
  ///
  /// Uses [GoogleSignIn.instance.attemptLightweightAuthentication], which
  /// returns a nullable Future: on platforms where silent auth is unavailable
  /// (e.g. web/FedCM), the method returns null.
  @override
  Future<CloudAccount?> currentAccount() async {
    await _ensureInitialized();
    final future = GoogleSignIn.instance.attemptLightweightAuthentication();
    if (future == null) return null;
    final account = await future;
    return account == null ? null : CloudAccount(account.email);
  }

  /// Runs the interactive Google Sign-In flow, then authorizes [_scope].
  ///
  /// Returns null if the user cancels ([GoogleSignInExceptionCode.canceled]).
  @override
  Future<CloudAccount?> connect() async {
    await _ensureInitialized();
    try {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: [_scope],
      );
      await account.authorizationClient.authorizeScopes([_scope]);
      return CloudAccount(account.email);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  /// Revokes authorization and signs the user out.
  @override
  Future<void> disconnect() async {
    await _ensureInitialized();
    await GoogleSignIn.instance.disconnect();
  }

  @override
  Future<List<CloudBackupRef>> list() async {
    final api = await _api();
    final res = await api.files.list(
      spaces: _space,
      $fields: 'files(id,name,createdTime)',
      pageSize: 100,
    );
    return [
      for (final f in res.files ?? const <drive.File>[])
        CloudBackupRef(
          id: f.id!,
          name: f.name ?? '',
          createdAt: f.createdTime ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
    ];
  }

  @override
  Future<void> upload(String name, String contents) async {
    final api = await _api();
    final bytes = utf8.encode(contents);
    await api.files.create(
      drive.File(name: name, parents: [_space]),
      uploadMedia: drive.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: 'application/json',
      ),
    );
  }

  @override
  Future<String> download(String id) async {
    final api = await _api();
    final media =
        await api.files.get(
              id,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;
    final chunks = <int>[];
    await for (final c in media.stream) {
      chunks.addAll(c);
    }
    return utf8.decode(chunks);
  }

  @override
  Future<void> delete(String id) async {
    final api = await _api();
    await api.files.delete(id);
  }
}

/// An [http.BaseClient] that injects a Bearer access token into every
/// outbound request. The token is fetched once per [drive.DriveApi] instance
/// (created per API operation); for user-initiated backup/restore calls this
/// is sufficient and avoids per-request async overhead.
class _AuthenticatedClient extends http.BaseClient {
  _AuthenticatedClient(this._accessToken);
  final String _accessToken;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }
}
