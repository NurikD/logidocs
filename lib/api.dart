// lib/api.dart
import 'dart:typed_data';
import 'dart:io' show File;
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

  /// Инициализация: читаем токен и ставим перехватчики
  Future<void> init() async {
    final access = await _storage.read(key: 'access');
    if (access != null && access.isNotEmpty) {
      dio.options.headers['Authorization'] = 'Bearer $access';
    }

    dio.interceptors.add(
      InterceptorsWrapper(
        // гарантируем, что на каждый запрос уйдёт актуальный токен
        onRequest: (options, handler) async {
          if (options.headers['Authorization'] == null) {
            final token = await _storage.read(key: 'access');
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },

        // авто-рефреш при 401 один раз
        onError: (e, handler) async {
          final status = e.response?.statusCode ?? 0;
          final req = e.requestOptions;
          final alreadyRetried = req.extra['__retried__'] == true;

          if (status == 401 && !alreadyRetried) {
            try {
              await _refreshAccessToken();
              req.extra['__retried__'] = true;

              final access = await _storage.read(key: 'access');
              if (access != null) {
                req.headers['Authorization'] = 'Bearer $access';
              }
              final clone = await dio.fetch(req);
              return handler.resolve(clone);
            } catch (_) {
              await logout();
            }
          }
          return handler.next(e);
        },
      ),
    );
  }

  /// Аутентификация
  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await dio.post(
      '/api/auth/token/',
      data: {'username': username, 'password': password},
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    final access = data['access'] as String?;
    final refresh = data['refresh'] as String?;
    if (access == null || refresh == null) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        message: 'Нет токенов в ответе',
        type: DioExceptionType.badResponse,
      );
    }
    await _storage.write(key: 'access', value: access);
    await _storage.write(key: 'refresh', value: refresh);
    dio.options.headers['Authorization'] = 'Bearer $access';
    return data;
  }

  Future<void> changePassword(String oldPw, String newPw) async {
    await dio.post(
      '/api/auth/change-password/',
      data: {'old_password': oldPw, 'new_password': newPw},
    );
  }

  /// Документы (список)
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

  /// ----- Загрузка/открытие файла -----

  /// Качаем байты документа (JWT обязателен)
  Future<Uint8List> fetchDocumentBytes(int id) async {
    await _ensureAuthHeader(); // ← НЕ снимаем токен
    final res = await dio.get(
      '/api/documents/$id/download/',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data as List<int>);
  }

  /// Сохранить во временный файл и открыть (mobile/desktop)
  Future<void> downloadToFileAndOpen(int id, String filename) async {
    if (kIsWeb) {
      // для web прямой openInBrowser может дать 401 (браузер не шлёт Authorization)
      // оставляем как есть, если на сервере настроены подписанные ссылки — сработает
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

  /// Открыть в браузере (web). Нужна публичная/подписанная ссылка на бэке.
  Future<void> openInBrowser(int id) async {
    final uri = Uri.parse('$kBaseUrl/api/documents/$id/download/');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// ----- Вспомогательные -----

  Future<void> _ensureAuthHeader() async {
    if (dio.options.headers['Authorization'] == null) {
      final access = await _storage.read(key: 'access');
      if (access != null && access.isNotEmpty) {
        dio.options.headers['Authorization'] = 'Bearer $access';
      }
    }
  }

  Future<void> _refreshAccessToken() async {
    if (_isRefreshing) {
      // дождаться текущего рефреша, чтобы не плодить конкурентных запросов
      while (_isRefreshing) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    _isRefreshing = true;
    try {
      final refresh = await _storage.read(key: 'refresh');
      if (refresh == null || refresh.isEmpty) {
        throw Exception('No refresh token');
      }
      final res = await dio.post(
        '/api/auth/token/refresh/',
        data: {'refresh': refresh},
        options: Options(
          // на рефреш Authorization не нужен
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

  // ДОБАВЬ в класс Api
  Future<bool> hasSession() async {
    // есть access — считаем, что сессия есть
    final access = await _storage.read(key: 'access');
    if (access != null && access.isNotEmpty) {
      dio.options.headers['Authorization'] = 'Bearer $access';
      return true;
    }
    // нет access, но есть refresh — пробуем рефрешнуться
    final refresh = await _storage.read(key: 'refresh');
    if (refresh != null && refresh.isNotEmpty) {
      try {
        await _refreshAccessToken();
        return true;
      } catch (_) {
        await logout();
        return false;
      }
    }
    return false;
  }
}
