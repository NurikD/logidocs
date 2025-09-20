// lib/api.dart
import 'dart:typed_data';
import 'dart:io' show File; // не ломает web — он не компилируется под web часть
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import 'env.dart';

class Api {
  Api._();
  static final Api I = Api._();

  final Dio dio = Dio(
    BaseOptions(
      baseUrl: kBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  final _storage = const FlutterSecureStorage();
  bool _isRefreshing = false;

  /// Подхватываем access из хранилища и подключаем интерсептор
  Future<void> init() async {
    final access = await _storage.read(key: 'access');
    if (access != null) {
      dio.options.headers['Authorization'] = 'Bearer $access';
    }

    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) async {
          final status = e.response?.statusCode ?? 0;
          final isAuthError = status == 401;
          final req = e.requestOptions;

          // Для отладки
          print('Interceptor error: $status, path: ${req.path}');

          final alreadyRetried = req.extra['__retried__'] == true;

          if (isAuthError && !alreadyRetried) {
            try {
              await _refreshAccessToken();
              req.extra['__retried__'] = true;
              final access = await _storage.read(key: 'access');
              if (access != null) {
                req.headers['Authorization'] = 'Bearer $access';
              }
              final clone = await dio.fetch(req);
              return handler.resolve(clone);
            } catch (e) {
              print('Refresh failed: $e');
              await logout();
            }
          }
          return handler.next(e);
        },
      ),
    );
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await dio.post(
      '/api/auth/token/', // Убедитесь, что путь совпадает
      data: {'username': username, 'password': password},
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    await _storage.write(key: 'access', value: data['access']);
    await _storage.write(key: 'refresh', value: data['refresh']);
    dio.options.headers['Authorization'] = 'Bearer ${data['access']}';
    return data;
  }

  Future<void> changePassword(String oldPw, String newPw) async {
    await dio.post(
      '/api/auth/change-password/',
      data: {'old_password': oldPw, 'new_password': newPw},
    );
  }

  Future<List<Map<String, dynamic>>> getDocuments() async {
    await _ensureAuthHeader();
    final res = await dio.get('/api/documents/');
    final list = (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return list;
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    dio.options.headers.remove('Authorization');
  }

  /// ----- Работа с PDF -----

  Future<Uint8List> fetchDocumentBytes(int id) async {
    // Временно убираем аутентификацию для тестирования
    dio.options.headers.remove('Authorization'); // Удаляем токен
    print(
      'Fetching document $id with headers: ${dio.options.headers}',
    ); // Для отладки
    try {
      final res = await dio.get(
        '/api/documents/$id/download/',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(res.data as List<int>);
    } on DioException catch (e) {
      print(
        'Fetch error: ${e.response?.statusCode}, ${e.message}',
      ); // Логируем ошибку
      rethrow; // Передаём ошибку дальше
    }
  }

  Future<void> downloadToFileAndOpen(int id, String filename) async {
    if (kIsWeb) {
      await openInBrowser(id);
      return;
    }
    final bytes = await fetchDocumentBytes(id);
    final dir = await getTemporaryDirectory();
    final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = '${dir.path}/$safeName';
    await File(path).writeAsBytes(bytes);
    await OpenFilex.open(path);
  }

  Future<void> openInBrowser(int id) async {
    final uri = Uri.parse('$kBaseUrl/api/documents/$id/download/');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// ----- Вспомогательные -----

  Future<void> _ensureAuthHeader() async {
    if (dio.options.headers['Authorization'] == null) {
      final access = await _storage.read(key: 'access');
      if (access != null) {
        dio.options.headers['Authorization'] = 'Bearer $access';
      }
    }
  }

  Future<void> _refreshAccessToken() async {
    if (_isRefreshing) {
      while (_isRefreshing) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    _isRefreshing = true;
    try {
      final refresh = await _storage.read(key: 'refresh');
      if (refresh == null) throw Exception('No refresh token');
      print('Attempting to refresh token with refresh: $refresh');
      final res = await dio.post(
        '/api/auth/token/refresh/', // Убедитесь, что путь совпадает
        data: {'refresh': refresh},
        options: Options(
          headers: {'Authorization': null, 'Content-Type': 'application/json'},
        ),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final newAccess = data['access'] as String?;
      if (newAccess == null) throw Exception('No access in refresh response');
      await _storage.write(key: 'access', value: newAccess);
      dio.options.headers['Authorization'] = 'Bearer $newAccess';
    } finally {
      _isRefreshing = false;
    }
  }
}
