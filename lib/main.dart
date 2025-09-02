import 'package:flutter/material.dart';

void main() {
  runApp(const LogiDocsApp());
}

class LogiDocsApp extends StatelessWidget {
  const LogiDocsApp({super.key});

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
          primary: const Color(0xFF0066CC),
          secondary: const Color(0xFF4CAF50),
        ),
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
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF0066CC), width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0066CC),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            minimumSize: const Size.fromHeight(56),
            elevation: 0,
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const LoginPage(),
    );
  }
}

/// -------------------- LOGIN --------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _login = TextEditingController();
  final _pass = TextEditingController();
  bool _isObscured = true;

  @override
  void dispose() {
    _login.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _submit() {
    if (_login.text.isEmpty || _pass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Введите логин и пароль'),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DocumentsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Логотип и заголовок
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

                    // Форма входа
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
                                onPressed: () => setState(() => _isObscured = !_isObscured),
                                icon: Icon(_isObscured ? Icons.visibility : Icons.visibility_off),
                              ),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _submit,
                            child: const Text('Войти в систему'),
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

                    // Дополнительная информация
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
      ),
    );
  }
}

/// -------------------- DOCUMENTS LIST --------------------
class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  final _search = TextEditingController();
  final List<_Doc> _all = const [
    _Doc(
      title: 'Лицензия на перевозку №123',
      type: 'Лицензия',
      version: 3,
      expiresAt: '31.12.2025',
      status: 'Действует',
      icon: Icons.verified_user,
      color: Color(0xFF4CAF50),
    ),
    _Doc(
      title: 'Разрешение на маршрут А-45',
      type: 'Разрешение',
      version: 2,
      expiresAt: '15.03.2026',
      status: 'Действует',
      icon: Icons.route,
      color: Color(0xFF2196F3),
    ),
    _Doc(
      title: 'Страховой полис ТС',
      type: 'Полис',
      version: 1,
      expiresAt: '01.05.2025',
      status: 'Истекает',
      icon: Icons.security,
      color: Color(0xFFFF9800),
    ),
    _Doc(
      title: 'Техосмотр транспорта',
      type: 'Сертификат',
      version: 1,
      expiresAt: '20.02.2025',
      status: 'Истекает',
      icon: Icons.build_circle,
      color: Color(0xFFFF5722),
    ),
  ];
  List<_Doc> _filtered = [];
  String _selectedFilter = 'Все';

  @override
  void initState() {
    super.initState();
    _filtered = _all;
    _search.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = _all.where((d) {
        final matchesSearch = d.title.toLowerCase().contains(q) ||
                             d.type.toLowerCase().contains(q);
        final matchesFilter = _selectedFilter == 'Все' ||
                             d.status == _selectedFilter;
        return matchesSearch && matchesFilter;
      }).toList();
    });
  }

  Future<void> _refresh() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Документы обновлены'),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0066CC), Color(0xFF004A99)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Мои документы',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                onPressed: () => _showProfileDialog(context),
                                icon: const Icon(Icons.account_circle, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Всего документов: ${_all.length}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Поиск
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: 'Поиск документов...',
                    prefixIcon: Icon(Icons.search),
                    border: InputBorder.none,
                    fillColor: Colors.transparent,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Фильтры
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: ['Все', 'Действует', 'Истекает'].map((filter) {
                    final isSelected = _selectedFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(filter),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedFilter = filter;
                            _applyFilter();
                          });
                        },
                        backgroundColor: Colors.white,
                        selectedColor: const Color(0xFF0066CC).withOpacity(0.1),
                        side: BorderSide(
                          color: isSelected 
                            ? const Color(0xFF0066CC) 
                            : Colors.grey[300]!,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // Статистика
              Row(
                children: [
                  Expanded(child: _StatCard(
                    title: 'Действующие',
                    count: _all.where((d) => d.status == 'Действует').length,
                    color: const Color(0xFF4CAF50),
                    icon: Icons.check_circle,
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _StatCard(
                    title: 'Истекающие',
                    count: _all.where((d) => d.status == 'Истекает').length,
                    color: const Color(0xFFFF9800),
                    icon: Icons.warning,
                  )),
                ],
              ),
              const SizedBox(height: 20),

              // Документы
              ..._filtered.map((d) => _DocumentCard(doc: d)).toList(),
              if (_filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Документы не найдены',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Попробуйте изменить условия поиска',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        backgroundColor: const Color(0xFF4CAF50),
        icon: const Icon(Icons.add),
        label: const Text('Добавить'),
      ),
    );
  }

  void _showProfileDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Профиль пользователя'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Настройки профиля'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.security),
              title: const Text('Безопасность'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.help),
              title: const Text('Справка'),
              onTap: () => Navigator.pop(context),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Выйти', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.count,
    required this.color,
    required this.icon,
  });

  final String title;
  final int count;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.doc});
  final _Doc doc;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Открыть: ${doc.title} (v${doc.version})'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                        _Chip(text: doc.type, color: Colors.grey[700]!),
                        const SizedBox(width: 8),
                        _Chip(text: 'v${doc.version}', color: const Color(0xFF0066CC)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          'до ${doc.expiresAt}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: doc.status == 'Действует' 
                              ? const Color(0xFF4CAF50).withOpacity(0.1)
                              : const Color(0xFFFF9800).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            doc.status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: doc.status == 'Действует' 
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFFFF9800),
                            ),
                          ),
                        ),
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
  const _Chip({required this.text, required this.color});
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

class _Doc {
  final String title;
  final String type;
  final int version;
  final String expiresAt;
  final String status;
  final IconData icon;
  final Color color;

  const _Doc({
    required this.title,
    required this.type,
    required this.version,
    required this.expiresAt,
    required this.status,
    required this.icon,
    required this.color,
  });
}