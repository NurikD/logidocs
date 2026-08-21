import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:pdfx/pdfx.dart';
import 'package:photo_view/photo_view.dart';
import 'package:intl/intl.dart';
import 'api.dart';

// -------------------- design tokens --------------------
// Официальная бело-синяя гамма: строго, минималистично, без градиентов и теней.
const kInk = Color(0xFF1A1F2B);
const kInkMuted = Color(0xFF6B7280);
const kLine = Color(0xFFE3E6EA);
const kPaper2 = Color(0xFFF6F7F9);
const kAccent = Color(0xFF1E2A47);
const kStatusValid = Color(0xFF3C7A5C);
const kStatusSoon = Color(0xFFB07A20);
const kStatusExpired = Color(0xFFB23A34);
const kChevron = Color(0xFFB9BEC7);

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
          seedColor: kAccent,
        ).copyWith(secondary: kAccent),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: kInk,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: kInk,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: kLine),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: kLine),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: kAccent, width: 1.5),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            minimumSize: const Size.fromHeight(52),
            elevation: 0,
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: kLine),
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
        backgroundColor: isError ? kStatusExpired : kStatusValid,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(height: 3, width: double.infinity, color: kAccent),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            border: Border.all(color: kLine),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.account_balance, size: 26, color: kAccent),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'LogiDocs',
                          style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w700,
                            color: kInk, letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Электронный документооборот',
                          style: TextStyle(fontSize: 11, color: kInkMuted, letterSpacing: 0.8),
                        ),
                        const SizedBox(height: 32),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: kLine),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _login,
                                decoration: const InputDecoration(
                                  labelText: 'Логин', hintText: 'Введите ваш логин',
                                  prefixIcon: Icon(Icons.person_outline, color: kInkMuted),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _pass,
                                obscureText: _isObscured,
                                decoration: InputDecoration(
                                  labelText: 'Пароль', hintText: 'Введите пароль',
                                  prefixIcon: const Icon(Icons.lock_outline, color: kInkMuted),
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(() => _isObscured = !_isObscured),
                                    icon: Icon(_isObscured ? Icons.visibility : Icons.visibility_off, color: kInkMuted),
                                  ),
                                ),
                                onSubmitted: (_) => _submit(),
                              ),
                              const SizedBox(height: 22),
                              ElevatedButton(
                                onPressed: _loading ? null : _submit,
                                child: Text(_loading ? 'Вход...' : 'Войти в систему'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'Служба поддержки · +996 501 433 914',
                          style: TextStyle(color: kInkMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
        backgroundColor: isError ? kStatusExpired : kStatusValid,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.description_outlined, size: 18, color: kAccent),
            SizedBox(width: 10),
            Text('LogiDocs'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить', onPressed: _refresh,
            icon: const Icon(Icons.refresh, color: kInkMuted),
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
            icon: const Icon(Icons.logout, color: kInkMuted),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: kLine),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text('Мои документы', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: kInk)),
                    const Spacer(),
                    Text('${_documents.length} документа', style: const TextStyle(fontSize: 12, color: kInkMuted)),
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
                        decoration: const BoxDecoration(color: kPaper2, shape: BoxShape.circle),
                        child: const Icon(Icons.folder_open, size: 56, color: kInkMuted),
                      ),
                      const SizedBox(height: 24),
                      const Text('Документы не найдены', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: kInk)),
                      const SizedBox(height: 8),
                      const Text('Документы появятся здесь автоматически', style: TextStyle(fontSize: 13, color: kInkMuted)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return DocumentRow(doc: _documents[index]);
                  }, childCount: _documents.length),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        ),
      ),
    );
  }
}

class DocumentRow extends StatelessWidget {
  const DocumentRow({Key? key, required this.doc}) : super(key: key);
  final Doc doc;

  Color get _statusColor {
    if (doc.isExpired) return kStatusExpired;
    if (doc.isExpiringSoon) return kStatusSoon;
    if (doc.expiresAt != null) return kStatusValid;
    return kInkMuted;
  }

  String get _statusText {
    if (doc.expiresAt == null) return '';
    if (doc.isExpired) return 'Просрочен ${doc.expiresAt}';
    if (doc.isExpiringSoon) return 'Истекает ${doc.expiresAt}';
    return 'до ${doc.expiresAt}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kLine)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DocumentViewerPage(
                  docId: doc.id,
                  title: doc.title,
                  kindLabel: doc.kindLabel,
                  expiresAt: doc.expiresAt,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    border: Border.all(color: kLine),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(doc.icon, color: kAccent, size: 19),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: kInk),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Text(doc.kindLabel, style: const TextStyle(fontSize: 10.5, letterSpacing: 0.8, color: kInkMuted)),
                          if (doc.expiresAt != null) ...[
                            const SizedBox(width: 6),
                            Container(width: 3, height: 3, decoration: const BoxDecoration(color: kLine, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _statusText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: _statusColor),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (doc.expiresAt != null)
                  Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle),
                  ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: kChevron, size: 15),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Doc {
  final int id;
  final String title;
  final String? kind;
  final String kindLabel;
  final String? expiresAt;
  final IconData icon;
  final bool isExpired;
  final bool isExpiringSoon;

  Doc({
    required this.id,
    required this.title,
    this.kind,
    required this.kindLabel,
    this.expiresAt,
    required this.icon,
    required this.isExpired,
    required this.isExpiringSoon,
  });

  static ({IconData icon, String label}) _kindMeta(String? kind) {
    switch ((kind ?? '').toLowerCase()) {
      case 'license':
        return (icon: Icons.verified_user, label: 'ЛИЦЕНЗИЯ');
      case 'permit':
        return (icon: Icons.route, label: 'РАЗРЕШЕНИЕ');
      case 'policy':
        return (icon: Icons.security, label: 'ПОЛИС');
      case 'cert':
        return (icon: Icons.assignment_turned_in, label: 'СЕРТИФИКАТ');
      default:
        return (icon: Icons.description, label: 'ДОКУМЕНТ');
    }
  }

  factory Doc.fromJson(Map<String, dynamic> m) {
    final kind = m['kind']?.toString();
    final meta = _kindMeta(kind);

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
      kind: kind,
      kindLabel: meta.label,
      expiresAt: m['expires_at']?.toString(),
      icon: meta.icon,
      isExpired: isExpired,
      isExpiringSoon: isExpiringSoon,
    );
  }
}

class DocumentViewerPage extends StatefulWidget {
  const DocumentViewerPage({
    Key? key,
    required this.docId,
    required this.title,
    this.kindLabel,
    this.expiresAt,
  }) : super(key: key);
  final int docId;
  final String title;
  final String? kindLabel;
  final String? expiresAt;

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
    final subtitleParts = <String>[
      if (widget.kindLabel != null) widget.kindLabel!,
      if (widget.expiresAt != null) 'до ${widget.expiresAt}',
    ];

    return Scaffold(
      backgroundColor: kPaper2,
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: kInk)),
            if (subtitleParts.isNotEmpty)
              Text(subtitleParts.join(' · '), style: const TextStyle(fontSize: 11, color: kInkMuted, fontWeight: FontWeight.normal)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: kLine),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: kStatusExpired)))
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
