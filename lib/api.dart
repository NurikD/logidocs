import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'env.dart';

class Api {
  Api._();
  static final Api I = Api._();

  final Dio dio = Dio(BaseOptions(baseUrl: kBaseUrl));
  final _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await dio.post(
      '/api/auth/token/',
      data: {'username': username, 'password': password},
    );
    final data = res.data as Map<String, dynamic>;
    // сохраним токены
    await _storage.write(key: 'access', value: data['access']);
    await _storage.write(key: 'refresh', value: data['refresh']);
    dio.options.headers['Authorization'] = 'Bearer ${data['access']}';
    return data; // содержит must_change_pw
  }

  Future<void> changePassword(String oldPw, String newPw) async {
    await dio.post(
      '/api/auth/change-password/',
      data: {'old_password': oldPw, 'new_password': newPw},
    );
  }

  Future<List<dynamic>> getDocuments() async {
    final access = await _storage.read(key: 'access');
    if (access != null) {
      dio.options.headers['Authorization'] = 'Bearer $access';
    }
    final res = await dio.get('/api/documents/');
    return res.data as List<dynamic>;
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    dio.options.headers.remove('Authorization');
  }
}
