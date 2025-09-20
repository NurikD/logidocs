import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:pdfx/pdfx.dart';
import 'package:photo_view/photo_view.dart';
import 'package:intl/intl.dart';
import 'api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.I.init();
  runApp(const LogiDocsApp());
}

class LogiDocsApp extends StatelessWidget {
  const LogiDocsApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LogiDocs',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0066CC),
        ).copyWith(secondary: const Color(0xFF4CAF50)),
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF333333),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: Color(0xFF333333),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF0066CC), width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0066CC),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            minimumSize: const Size.fromHeight(56),
            elevation: 0,
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _login = TextEditingController();
  final _pass = TextEditingController();
  bool _isObscured = true;
  bool _loading = false;

  @override
  void dispose() {
    _login.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final login = _login.text.trim();
    final pass = _pass.text.trim();
    if (login.isEmpty || pass.isEmpty) {
      _toast('Введите логин и пароль', isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await Api.I.login(login, pass);
      if (!mounted) return;
      if (data['must_change_pw'] == true) {
        _toast('Пожалуйста, смените пароль');
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DocumentsPage()),
        );
      }
    } on DioException catch (e) {
      final msg = e.response?.data['detail']?.toString() ?? 'Ошибка входа';
      if (!mounted) return;
      _toast(msg, isError: true);
    } catch (_) {
      if (!mounted) return;
      _toast('Сервер недоступен', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError
            ? Colors.red.withOpacity(0.9)
            : const Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0066CC),
                  Color(0xFF004A99),
                  Color(0xFF003D7A),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.account_balance,
                          size: 60,
                          color: Color(0xFF0066CC),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'LogiDocs',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Электронный документооборот',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 48),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Вход в систему',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _login,
                              decoration: const InputDecoration(
                                labelText: 'Логин',
                                hintText: 'Введите ваш логин',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _pass,
                              obscureText: _isObscured,
                              decoration: InputDecoration(
                                labelText: 'Пароль',
                                hintText: 'Введите пароль',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () => _isObscured = !_isObscured,
                                  ),
                                  icon: Icon(
                                    _isObscured
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                ),
                              ),
                              onSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _loading ? null : _submit,
                              child: Text(
                                _loading ? 'Вход...' : 'Войти в систему',
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton(
                                  onPressed: () {},
                                  child: const Text('Забыли пароль?'),
                                ),
                                TextButton(
                                  onPressed: () {},
                                  child: const Text('Регистрация'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Техническая поддержка: 8-800-123-45-67',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({Key? key}) : super(key: key);

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  List<Doc> _documents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rawList = await Api.I.getDocuments();
      final list = rawList.map((m) => Doc.fromJson(m)).toList();
      if (!mounted) return;
      setState(() {
        _documents = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('Ошибка загрузки документов: $e', isError: true);
    }
  }

  Future<void> _refresh() async {
    await _load();
    if (!mounted) return;
    _toast('Документы обновлены');
  }

  void _toast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError
            ? Colors.red.withOpacity(0.9)
            : const Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Мои документы'),
        actions: [
          IconButton(
            tooltip: 'Выход',
            onPressed: () async {
              await Api.I.logout();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final d in _documents) DocumentCard(doc: d),
                  if (_documents.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: Colors.grey.withOpacity(0.4),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Документы не найдены',
                            style: TextStyle(
                              color: Colors.grey.withOpacity(0.6),
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

class DocumentCard extends StatelessWidget {
  const DocumentCard({Key? key, required this.doc}) : super(key: key);
  final Doc doc;

  @override
  Widget build(BuildContext context) {
    final expiredColor = doc.isExpired
        ? Colors.red
        : Colors.grey.withOpacity(0.7);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: doc.isExpired
            ? Border.all(color: Colors.red.withOpacity(0.5))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // Убираем проверку kIsWeb и всегда открываем внутри приложения
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  DocumentViewerPage(docId: doc.id, title: doc.title),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: doc.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(doc.icon, color: doc.color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _Chip(text: doc.type ?? 'Документ', color: Colors.grey),
                        const SizedBox(width: 8),
                        _Chip(
                          text: 'v${doc.version ?? '-'}',
                          color: const Color(0xFF0066CC),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (doc.expiresAt != null)
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 14, color: expiredColor),
                          const SizedBox(width: 4),
                          Text(
                            'до ${doc.expiresAt}',
                            style: TextStyle(fontSize: 12, color: expiredColor),
                          ),
                          if (doc.isExpired) ...[
                            const SizedBox(width: 8),
                            const Text(
                              '(просрочен)',
                              style: TextStyle(fontSize: 12, color: Colors.red),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({Key? key, required this.text, required this.color})
    : super(key: key);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

class Doc {
  final int id;
  final String title;
  final String? type;
  final int? version;
  final String? expiresAt;
  final IconData icon;
  final Color color;
  final bool isExpired;

  Doc({
    required this.id,
    required this.title,
    this.type,
    this.version,
    this.expiresAt,
    required this.icon,
    required this.color,
    required this.isExpired,
  });

  factory Doc.fromJson(Map<String, dynamic> m) {
    final t = (m['type'] as String?)?.toLowerCase() ?? '';
    IconData icon = Icons.description;
    Color color = const Color(0xFF0066CC);
    if (t.contains('лиценз')) {
      icon = Icons.verified_user;
      color = const Color(0xFF4CAF50);
    } else if (t.contains('разреш')) {
      icon = Icons.route;
      color = const Color(0xFF2196F3);
    } else if (t.contains('полис')) {
      icon = Icons.security;
      color = const Color(0xFFFF9800);
    } else if (t.contains('сертифик')) {
      icon = Icons.assignment_turned_in;
      color = const Color(0xFF7E57C2);
    }

    bool isExpired = false;
    if (m['expires_at'] != null) {
      try {
        final expireDate = DateFormat('yyyy-MM-dd').parse(m['expires_at']);
        isExpired = expireDate.isBefore(DateTime.now());
      } catch (_) {
        // Invalid date - ignore
      }
    }

    return Doc(
      id: m['id'] as int,
      title: (m['title'] ?? '').toString(),
      type: m['type']?.toString(),
      version: m['version'] is int
          ? m['version'] as int
          : int.tryParse('${m['version']}'),
      expiresAt: m['expires_at']?.toString(),
      icon: icon,
      color: color,
      isExpired: isExpired,
    );
  }
}

class DocumentViewerPage extends StatefulWidget {
  const DocumentViewerPage({Key? key, required this.docId, required this.title})
    : super(key: key);
  final int docId;
  final String title;

  @override
  State<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends State<DocumentViewerPage> {
  Uint8List? _bytes;
  String? _fileType; // 'pdf', 'image', null if error
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final bytes = await Api.I.fetchDocumentBytes(widget.docId);
      final fileType = _detectFileType(bytes);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _fileType = fileType;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка загрузки: $e';
        _isLoading = false;
      });
    }
  }

  String? _detectFileType(Uint8List bytes) {
    if (bytes.length < 4) return null;
    final header = String.fromCharCodes(bytes.sublist(0, 4));
    if (header == '%PDF') return 'pdf';
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'image'; // JPEG
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47)
      return 'image'; // PNG
    return null; // Unknown
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : _bytes == null
          ? const Center(child: Text('Ошибка загрузки документа'))
          : _fileType == 'pdf'
          ? PdfView(
              controller: PdfController(
                document: PdfDocument.openData(_bytes!),
              ),
            )
          : _fileType == 'image'
          ? PhotoView(imageProvider: MemoryImage(_bytes!))
          : const Center(child: Text('Неподдерживаемый формат')),
    );
  }
}
