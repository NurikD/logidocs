import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:pdfx/pdfx.dart';
import 'package:photo_view/photo_view.dart';
import 'package:intl/intl.dart';
import 'api.dart';

// -------------------- simple in-memory LRU caches --------------------
class _LruCache<K, V> {
  final _map = <K, V>{};
  final int capacity;
  _LruCache({this.capacity = 32});
  V? get(K k) {
    final v = _map.remove(k);
    if (v != null) _map[k] = v; // move to end (recent)
    return v;
  }
  void put(K k, V v) {
    if (_map.length >= capacity && !_map.containsKey(k)) {
      _map.remove(_map.keys.first);
    }
    _map[k] = v;
  }
  void remove(K k) => _map.remove(k);
  void clear() => _map.clear();
}

final _docsCache = _LruCache<String, List<Doc>>(capacity: 8);
final _bytesCache = _LruCache<int, Uint8List>(capacity: 32);

// --------------------------------------------------------------------

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
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({Key? key}) : super(key: key);
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Future<bool>? _future;

  @override
  void initState() {
    super.initState();
    _future = () async {
      await Api.I.init();
      return Api.I.hasSession();
    }();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snap.data! ? const DocumentsPage() : const LoginPage();
      },
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
                colors: [Color(0xFF0066CC), Color(0xFF004A99), Color(0xFF003D7A)],
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
                        child: const Icon(Icons.account_balance, size: 60, color: Color(0xFF0066CC)),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'LogiDocs',
                        style: TextStyle(
                          fontSize: 32, fontWeight: FontWeight.bold,
                          color: Colors.white, letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Электронный документооборот',
                        style: TextStyle(fontSize: 16, color: Colors.white70),
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
                                fontSize: 24, fontWeight: FontWeight.w600, color: Color(0xFF333333),
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _login,
                              decoration: const InputDecoration(
                                labelText: 'Логин', hintText: 'Введите ваш логин',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _pass,
                              obscureText: _isObscured,
                              decoration: InputDecoration(
                                labelText: 'Пароль', hintText: 'Введите пароль',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() => _isObscured = !_isObscured),
                                  icon: Icon(_isObscured ? Icons.visibility : Icons.visibility_off),
                                ),
                              ),
                              onSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _loading ? null : _submit,
                              child: Text(_loading ? 'Вход...' : 'Войти в систему'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Техническая поддержка: +996-501-433-914',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
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
    // 1) мгновенно показываем из кэша, если есть
    final cached = _docsCache.get('my_docs');
    if (cached != null && mounted) {
      setState(() { _documents = cached; _loading = false; });
    }
    // 2) обновляем с сервера
    try {
      final rawList = await Api.I.getDocuments();
      final list = rawList.map((m) => Doc.fromJson(m)).toList();
      if (!mounted) return;
      setState(() { _documents = list; _loading = false; });
      _docsCache.put('my_docs', list);
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
        backgroundColor: isError ? Colors.red.withOpacity(0.9) : const Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expiredDocs = _documents.where((doc) => doc.isExpired).length;
    final expiringSoon = _documents.where((doc) => doc.isExpiringSoon && !doc.isExpired).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 200,
              floating: false,
              pinned: true,
              backgroundColor: const Color(0xFF0066CC),
              flexibleSpace: FlexibleSpaceBar(
                title: const Text('Мои документы', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFF0066CC), Color(0xFF004A99), Color(0xFF003D7A)],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -50, top: -50,
                        child: Container(
                          width: 200, height: 200,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white10),
                        ),
                      ),
                      const Positioned(
                        right: 20, top: 100,
                        child: Icon(Icons.folder_open, size: 80, color: Colors.white24),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Обновить', onPressed: _refresh,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                ),
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
                  icon: const Icon(Icons.logout, color: Colors.white),
                ),
              ],
            ),
            if (!_loading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Icon(Icons.description, color: Color(0xFF0066CC)),
                          const SizedBox(width: 8),
                          const Text('Документы', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
                          const Spacer(),
                          if (_documents.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0066CC).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('${_documents.length}', style: const TextStyle(color: Color(0xFF0066CC), fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (_documents.isEmpty)
              SliverFillRemaining(
                child: Container(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120, height: 120,
                        decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), shape: BoxShape.circle),
                        child: Icon(Icons.folder_open, size: 60, color: Colors.grey.withOpacity(0.4)),
                      ),
                      const SizedBox(height: 24),
                      Text('Документы не найдены', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.grey.withOpacity(0.6))),
                      const SizedBox(height: 8),
                      Text('Документы появятся здесь автоматически', style: TextStyle(fontSize: 14, color: Colors.grey.withOpacity(0.5))),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return Padding(
                      padding: EdgeInsets.only(bottom: index == _documents.length - 1 ? 20 : 12),
                      child: DocumentCard(doc: _documents[index]),
                    );
                  }, childCount: _documents.length),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    Key? key,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  }) : super(key: key);

  final IconData icon;
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
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
        : doc.isExpiringSoon
            ? Colors.orange
            : Colors.grey.withOpacity(0.7);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: doc.isExpired
            ? Border.all(color: Colors.red.withOpacity(0.5), width: 2)
            : doc.isExpiringSoon
                ? Border.all(color: Colors.orange.withOpacity(0.5), width: 1)
                : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DocumentViewerPage(docId: doc.id, title: doc.title)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [doc.color, doc.color.withOpacity(0.7)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: doc.color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Icon(doc.icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doc.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _Chip(text: doc.type ?? 'Документ', color: Colors.grey),
                          const SizedBox(width: 8),
                          _Chip(text: 'v${doc.version ?? '-'}', color: const Color(0xFF0066CC)),
                        ],
                      ),
                      if (doc.expiresAt != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              doc.isExpired ? Icons.error : (doc.isExpiringSoon ? Icons.warning : Icons.schedule),
                              size: 16, color: expiredColor,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                doc.isExpired
                                    ? 'Просрочен ${doc.expiresAt}'
                                    : (doc.isExpiringSoon ? 'Истекает ${doc.expiresAt}' : 'до ${doc.expiresAt}'),
                                style: TextStyle(
                                  fontSize: 12, color: expiredColor,
                                  fontWeight: (doc.isExpired || doc.isExpiringSoon) ? FontWeight.w500 : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({Key? key, required this.text, required this.color}) : super(key: key);
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
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
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
  final bool isExpiringSoon;

  Doc({
    required this.id,
    required this.title,
    this.type,
    this.version,
    this.expiresAt,
    required this.icon,
    required this.color,
    required this.isExpired,
    required this.isExpiringSoon,
  });

  factory Doc.fromJson(Map<String, dynamic> m) {
    final t = (m['type'] as String?)?.toLowerCase() ?? '';
    IconData icon = Icons.description;
    Color color = const Color(0xFF0066CC);
    if (t.contains('лиценз')) {
      icon = Icons.verified_user; color = const Color(0xFF4CAF50);
    } else if (t.contains('разреш')) {
      icon = Icons.route; color = const Color(0xFF2196F3);
    } else if (t.contains('полис')) {
      icon = Icons.security; color = const Color(0xFFFF9800);
    } else if (t.contains('сертифик')) {
      icon = Icons.assignment_turned_in; color = const Color(0xFF7E57C2);
    }

    bool isExpired = false;
    bool isExpiringSoon = false;
    if (m['expires_at'] != null) {
      try {
        final expireDate = DateFormat('yyyy-MM-dd').parse(m['expires_at']);
        final now = DateTime.now();
        isExpired = expireDate.isBefore(now);
        if (!isExpired) {
          final daysUntilExpiration = expireDate.difference(now).inDays;
          isExpiringSoon = daysUntilExpiration <= 30;
        }
      } catch (_) {}
    }

    return Doc(
      id: m['id'] as int,
      title: (m['title'] ?? '').toString(),
      type: m['type']?.toString(),
      version: m['version'] is int ? m['version'] as int : int.tryParse('${m['version']}'),
      expiresAt: m['expires_at']?.toString(),
      icon: icon,
      color: color,
      isExpired: isExpired,
      isExpiringSoon: isExpiringSoon,
    );
  }
}

class DocumentViewerPage extends StatefulWidget {
  const DocumentViewerPage({Key? key, required this.docId, required this.title}) : super(key: key);
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
  PdfController? _pdf;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pdf?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final cached = _bytesCache.get(widget.docId);
      if (cached != null) {
        final ft = _detectFileType(cached);
        _setupPdfIfNeeded(ft, cached);
        if (!mounted) return;
        setState(() { _bytes = cached; _fileType = ft; _isLoading = false; });
        _refreshInBackground();
        return;
      }

      final bytes = await Api.I.fetchDocumentBytes(widget.docId);
      final ft = _detectFileType(bytes);
      _bytesCache.put(widget.docId, bytes);
      _setupPdfIfNeeded(ft, bytes);
      if (!mounted) return;
      setState(() { _bytes = bytes; _fileType = ft; _isLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Ошибка загрузки: $e'; _isLoading = false; });
    }
  }

  Future<void> _refreshInBackground() async {
    try {
      final fresh = await Api.I.fetchDocumentBytes(widget.docId);
      if (_bytes == null || fresh.lengthInBytes != _bytes!.lengthInBytes) {
        _bytesCache.put(widget.docId, fresh);
        final ft = _detectFileType(fresh);
        _setupPdfIfNeeded(ft, fresh);
        if (!mounted) return;
        setState(() { _bytes = fresh; _fileType = ft; });
      }
    } catch (_) {}
  }

  void _setupPdfIfNeeded(String? ft, Uint8List data) {
    if (ft == 'pdf') {
      _pdf?.dispose();
      _pdf = PdfController(document: PdfDocument.openData(data));
    }
  }

  String? _detectFileType(Uint8List bytes) {
    if (bytes.length < 4) return null;
    final b0 = bytes[0], b1 = bytes[1], b2 = bytes[2], b3 = bytes[3];
    if (b0 == 0x25 && b1 == 0x50 && b2 == 0x44 && b3 == 0x46) return 'pdf';  // %PDF
    if (b0 == 0xFF && b1 == 0xD8) return 'image'; // JPEG
    if (b0 == 0x89 && b1 == 0x50 && b2 == 0x4E && b3 == 0x47) return 'image'; // PNG
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _bytes == null
                  ? const Center(child: Text('Ошибка загрузки документа'))
                  : _fileType == 'pdf'
                      ? PdfView(controller: _pdf!)
                      : _fileType == 'image'
                          ? PhotoView(imageProvider: MemoryImage(_bytes!))
                          : const Center(child: Text('Неподдерживаемый формат')),
    );
  }
}
