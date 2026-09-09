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
    await _storage.write(key: 'is_superuser', value: data['is_superuser'] == true ? '1' : '0');
    dio.options.headers['Authorization'] = 'Bearer $access';
    return data;
  }

  /// Диспетчер логинится тем же admin-аккаунтом — по этому флагу приложение
  /// показывает ему экран истекающих путёвок вместо своих документов.
  Future<bool> isSuperUser() async {
    return (await _storage.read(key: 'is_superuser')) == '1';
  }

  Future<void> changePassword(String oldPw, String newPw) async {
    await dio.post(
      '/api/auth/change-password/',
      data: {'old_password': oldPw, 'new_password': newPw},
    );
  }

  /// Автомобили текущего пользователя. Пустой список — клиент с одной
  /// машиной, папки в приложении показывать не нужно.
  Future<List<Map<String, dynamic>>> getVehicles() async {
    await _ensureAuthHeader();
    final res = await dio.get('/api/vehicles/');
    final list = (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return list;
  }

  /// Документы (список). vehicleId — только документы конкретной машины;
  /// null — все документы пользователя (как раньше, для клиента с одной машиной).
  Future<List<Map<String, dynamic>>> getDocuments({int? vehicleId}) async {
    await _ensureAuthHeader();
    final res = await dio.get(
      '/api/documents/',
      queryParameters: vehicleId != null ? {'vehicle': vehicleId} : null,
    );
    final list = (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return list;
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    dio.options.headers.remove('Authorization');
  }

  /// ----- Уведомления об истечении путёвки -----

  /// Клиент нажал "Понятно" — больше не напоминать по этому документу.
  Future<void> dismissNotification(int docId) async {
    await _ensureAuthHeader();
    await dio.post('/api/documents/$docId/dismiss-notification/');
  }

  /// Экран диспетчера: путёвки всех клиентов, которые скоро истекут или истекли.
  Future<List<Map<String, dynamic>>> getExpiringDocuments() async {
    await _ensureAuthHeader();
    final res = await dio.get('/api/documents/expiring/');
    final list = (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return list;
  }

  /// Регистрация FCM-токена устройства за текущим пользователем.
  Future<void> registerDeviceToken(String token, String platform) async {
    await _ensureAuthHeader();
    await dio.post('/api/devices/register/', data: {'token': token, 'platform': platform});
  }

  /// ----- Загрузка/открытие файла -----
  /// Документ теперь может содержать несколько файлов — качаем по паре (docId, fileId).

  /// Качаем байты конкретного файла документа (JWT обязателен)
  Future<Uint8List> fetchFileBytes(int docId, int fileId) async {
    await _ensureAuthHeader(); // ← НЕ снимаем токен
    final res = await dio.get(
      '/api/documents/$docId/download/$fileId/',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data as List<int>);
  }

  /// Сохранить во временный файл и открыть (mobile/desktop)
  Future<void> downloadFileAndOpen(int docId, int fileId, String filename) async {
    if (kIsWeb) {
      // для web прямой openFileInBrowser может дать 401 (браузер не шлёт Authorization)
      // оставляем как есть, если на сервере настроены подписанные ссылки — сработает
      await openFileInBrowser(docId, fileId);
      return;
    }
    final bytes = await fetchFileBytes(docId, fileId);
    final dir = await getTemporaryDirectory();
    final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = '${dir.path}/$safeName';
    await File(path).writeAsBytes(bytes);
    await OpenFilex.open(path);
  }

  /// Открыть в браузере (web). Нужна публичная/подписанная ссылка на бэке.
  Future<void> openFileInBrowser(int docId, int fileId) async {
    final uri = Uri.parse('$kBaseUrl/api/documents/$docId/download/$fileId/');
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
