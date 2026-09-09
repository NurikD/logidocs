import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'dart:math' show sin, pi;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:pdfx/pdfx.dart';
import 'package:photo_view/photo_view.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:local_auth/local_auth.dart';
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
final _bytesCache = _LruCache<String, Uint8List>(capacity: 32);

// --------------------------------------------------------------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Веб пока без Firebase-конфига — инициализируем только на Android/iOS.
  if (!kIsWeb) {
    await Firebase.initializeApp();
    _listenForegroundPush();
  }
  await Api.I.init();
  runApp(const LogiDocsApp());
}

/// Просит разрешение на пуши, получает FCM-токен и регистрирует его за
/// текущим пользователем. Не критично для входа — ошибки молча проглатываем.
Future<void> _registerPushToken() async {
  if (kIsWeb) return;
  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    final token = await messaging.getToken();
    if (token != null) {
      await Api.I.registerDeviceToken(token, platform);
    }
    messaging.onTokenRefresh.listen((t) {
      Api.I.registerDeviceToken(t, platform).catchError((_) {});
    });
  } catch (_) {}
}

/// Пока приложение открыто, Android не кладёт push в шторку — показываем
/// его сами, иначе уведомление просто теряется.
void _listenForegroundPush() {
  if (kIsWeb) return;
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        backgroundColor: kAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((n.title ?? '').isNotEmpty)
              Text(n.title!, style: const TextStyle(fontWeight: FontWeight.w600)),
            if ((n.body ?? '').isNotEmpty) Text(n.body!),
          ],
        ),
      ),
    );
  });
}

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class LogiDocsApp extends StatelessWidget {
  const LogiDocsApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LogiDocs',
      scaffoldMessengerKey: scaffoldMessengerKey,
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

class _GateState {
  final bool logged;
  final bool needPin;
  const _GateState(this.logged, this.needPin);
}

class _AuthGateState extends State<AuthGate> {
  Future<_GateState>? _future;

  @override
  void initState() {
    super.initState();
    _future = () async {
      await Api.I.init();
      final logged = await Api.I.hasSession();
      if (logged) _registerPushToken();
      // PIN запирает уже сохранённую сессию — спрашиваем его до документов
      final needPin = logged && await Api.I.hasPin();
      return _GateState(logged, needPin);
    }();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GateState>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!data.logged) return const LoginPage();
        if (data.needPin) return const PinPage(mode: PinMode.unlock);
        return const HomePage();
      },
    );
  }
}

// -------------------- PIN-код --------------------

enum PinMode { unlock, setup }

/// Экран PIN-кода. В режиме setup код вводится дважды (ввод + подтверждение),
/// в режиме unlock — отпирает уже сохранённую сессию.
class PinPage extends StatefulWidget {
  const PinPage({Key? key, required this.mode, this.skippable = false}) : super(key: key);

  final PinMode mode;

  /// Показывать «Пропустить» — только когда PIN предлагается после входа.
  final bool skippable;

  @override
  State<PinPage> createState() => _PinPageState();
}

class _PinPageState extends State<PinPage> with SingleTickerProviderStateMixin {
  static const _pinLength = 4;

  String _entered = '';
  String? _firstEntry; // первый ввод в режиме setup
  String? _error;
  int _triesLeft = 5;
  bool _busy = false;

  late final AnimationController _shakeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  final _localAuth = LocalAuthentication();
  bool _biometryAvailable = false;

  @override
  void initState() {
    super.initState();
    if (widget.mode == PinMode.unlock) {
      Api.I.pinTriesLeft().then((n) {
        if (mounted) setState(() => _triesLeft = n);
      });
      _initBiometry();
    }
  }

  /// Биометрия доступна, только если она включена в приложении, поддержана
  /// телефоном и там реально зарегистрирован хотя бы один отпечаток/лицо.
  Future<void> _initBiometry() async {
    try {
      if (!await Api.I.biometryEnabled()) return;
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final enrolled = (await _localAuth.getAvailableBiometrics()).isNotEmpty;
      if (!mounted || !(supported && canCheck && enrolled)) return;
      setState(() => _biometryAvailable = true);
      _authBiometric(); // сразу предлагаем — как в банковских приложениях
    } catch (_) {}
  }

  Future<void> _authBiometric() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Вход в LogiDocs',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (ok) _goHome();
    } catch (_) {
      // отказ или сбой — молча остаёмся на вводе PIN
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  String get _title {
    if (widget.mode == PinMode.setup) {
      return _firstEntry == null ? 'Придумайте PIN-код' : 'Повторите PIN-код';
    }
    return 'Введите PIN-код';
  }

  String get _subtitle {
    if (widget.mode == PinMode.setup) {
      return _firstEntry == null
          ? '4 цифры для быстрого входа'
          : 'Ещё раз, чтобы не ошибиться';
    }
    return 'Для входа в LogiDocs';
  }

  void _fail(String message) {
    setState(() {
      _error = message;
      _entered = '';
    });
    _shakeCtrl.forward(from: 0);
  }

  Future<void> _onComplete() async {
    final pin = _entered;

    if (widget.mode == PinMode.setup) {
      if (_firstEntry == null) {
        setState(() {
          _firstEntry = pin;
          _entered = '';
          _error = null;
        });
        return;
      }
      if (_firstEntry != pin) {
        setState(() => _firstEntry = null);
        _fail('PIN-коды не совпали, попробуйте заново');
        return;
      }
      await Api.I.setPin(pin);
      if (!mounted) return;
      await _offerBiometry();
      if (!mounted) return;
      _goHome();
      return;
    }

    setState(() => _busy = true);
    final ok = await Api.I.verifyPin(pin);
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      _goHome();
      return;
    }

    final left = await Api.I.pinTriesLeft();
    if (!mounted) return;
    if (left <= 0) {
      await Api.I.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
      return;
    }
    setState(() => _triesLeft = left);
    _fail('Неверный PIN-код. Осталось попыток: $left');
  }

  /// После установки PIN предлагаем включить отпечаток/Face ID —
  /// но только если телефон это умеет и биометрия в нём настроена.
  Future<void> _offerBiometry() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final enrolled = (await _localAuth.getAvailableBiometrics()).isNotEmpty;
      if (!mounted || !(supported && canCheck && enrolled)) return;

      final agreed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          title: const Text('Вход по биометрии',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kInk)),
          content: const Text(
            'Использовать отпечаток или Face ID вместо ввода PIN-кода? '
            'PIN останется запасным способом входа.',
            style: TextStyle(fontSize: 14, color: kInkMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Не сейчас', style: TextStyle(color: kInkMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Включить',
                  style: TextStyle(color: kAccent, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
      if (agreed == true) await Api.I.setBiometryEnabled(true);
    } catch (_) {}
  }

  void _goHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  void _tap(String digit) {
    if (_busy || _entered.length >= _pinLength) return;
    setState(() {
      _entered += digit;
      _error = null;
    });
    if (_entered.length == _pinLength) _onComplete();
  }

  void _backspace() {
    if (_busy || _entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _forgotPin() async {
    await Api.I.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: kPaper2,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: kLine),
                  ),
                  child: const Icon(Icons.lock_outline, size: 24, color: kAccent),
                ),
                const SizedBox(height: 20),
                Text(_title,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700, color: kInk)),
                const SizedBox(height: 6),
                Text(_subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: kInkMuted)),
                const SizedBox(height: 28),
                _buildDots(),
                SizedBox(
                  height: 42,
                  child: Center(child: _buildHint()),
                ),
                _buildKeypad(),
                const SizedBox(height: 8),
                if (_biometryAvailable)
                  TextButton.icon(
                    onPressed: _authBiometric,
                    icon: const Icon(Icons.fingerprint, size: 20, color: kAccent),
                    label: const Text('Войти по биометрии',
                        style: TextStyle(fontSize: 13, color: kAccent)),
                  ),
                if (widget.mode == PinMode.unlock)
                  TextButton(
                    onPressed: _forgotPin,
                    child: const Text('Забыли PIN-код?',
                        style: TextStyle(fontSize: 13, color: kInkMuted)),
                  ),
                if (widget.skippable)
                  TextButton(
                    onPressed: _goHome,
                    child: const Text('Пропустить',
                        style: TextStyle(fontSize: 13, color: kInkMuted)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Ошибка последней попытки, а если её нет — напоминание об уже
  /// потраченных попытках (счётчик переживает перезапуск приложения).
  Widget? _buildHint() {
    if (_error != null) {
      return Text(_error!,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: kStatusExpired));
    }
    if (widget.mode == PinMode.unlock && _triesLeft < 5) {
      return Text('Осталось попыток: $_triesLeft',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: kStatusSoon));
    }
    return null;
  }

  Widget _buildDots() {
    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (context, child) {
        // затухающее колебание — привычная реакция на неверный код
        final t = _shakeCtrl.value;
        final dx = t == 0 ? 0.0 : sin(t * pi * 6) * 12 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_pinLength, (i) {
          final filled = i < _entered.length;
          return Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? kAccent : Colors.transparent,
              border: Border.all(color: filled ? kAccent : kChevron, width: 1.5),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildKeypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '<'];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.6,
        children: keys.map((k) {
          if (k.isEmpty) return const SizedBox.shrink();
          if (k == '<') {
            return _KeypadButton(
              onTap: _backspace,
              child: const Icon(Icons.backspace_outlined, size: 20, color: kInkMuted),
            );
          }
          return _KeypadButton(
            onTap: () => _tap(k),
            child: Text(k,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w500, color: kInk)),
          );
        }).toList(),
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Center(child: child),
      ),
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
        _registerPushToken();
        // PIN предлагаем только если его ещё нет; отказаться можно
        final hasPin = await Api.I.hasPin();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => hasPin
                ? const HomePage()
                : const PinPage(mode: PinMode.setup, skippable: true),
          ),
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

/// Решает, что показать сразу после входа: если у клиента одна машина
/// (или ни одной, для документов "как раньше") — список документов;
/// если несколько — список папок-автомобилей.
class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<_HomeData>? _future;

  @override
  void initState() {
    super.initState();
    _future = () async {
      if (await Api.I.isSuperUser()) {
        return const _HomeData.dispatcher();
      }
      final raw = await Api.I.getVehicles();
      final vehicles = raw.map((m) => Vehicle.fromJson(m)).toList();
      return _HomeData.client(vehicles);
    }();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HomeData>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData && !snap.hasError) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final data = snap.data ?? const _HomeData.client([]);
        if (data.isDispatcher) return const DispatcherHomePage();
        return data.vehicles.isEmpty ? const DocumentsPage() : VehiclesPage(vehicles: data.vehicles);
      },
    );
  }
}

class _HomeData {
  final bool isDispatcher;
  final List<Vehicle> vehicles;
  const _HomeData.client(this.vehicles) : isDispatcher = false;
  const _HomeData.dispatcher() : isDispatcher = true, vehicles = const [];
}

/// Экран диспетчера (superuser): все клиенты, у которых путёвка скоро истечёт
/// или уже истекла — вместо обычного списка документов.
class DispatcherHomePage extends StatefulWidget {
  const DispatcherHomePage({Key? key}) : super(key: key);

  @override
  State<DispatcherHomePage> createState() => _DispatcherHomePageState();
}

class _DispatcherHomePageState extends State<DispatcherHomePage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await Api.I.getExpiringDocuments();
      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Ошибка загрузки: $e'; _loading = false; });
    }
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
            tooltip: 'Обновить', onPressed: _load,
            icon: const Icon(Icons.refresh, color: kInkMuted),
          ),
          IconButton(
            tooltip: 'Выход',
            onPressed: () async {
              await Api.I.logout();
              if (!context.mounted) return;
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
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: kStatusExpired)))
                : _items.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(40),
                        children: [
                          const SizedBox(height: 80),
                          const Icon(Icons.check_circle_outline, size: 56, color: kStatusValid),
                          const SizedBox(height: 24),
                          const Center(child: Text('Ничего срочного', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: kInk))),
                          const SizedBox(height: 8),
                          const Center(child: Text('Нет путёвок, которые истекли или истекают в ближайшую неделю', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kInkMuted))),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                        itemCount: _items.length,
                        itemBuilder: (context, index) => ExpiringClientRow(item: _items[index]),
                      ),
      ),
    );
  }
}

class ExpiringClientRow extends StatelessWidget {
  const ExpiringClientRow({Key? key, required this.item}) : super(key: key);
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final isExpired = item['is_expired'] == true;
    final ownerName = (item['owner_name'] as String?)?.trim();
    final username = (item['owner_username'] ?? '').toString();
    final phone = (item['owner_phone'] as String?)?.trim();
    final plate = item['vehicle_plate']?.toString();
    final title = (item['title'] ?? '').toString();
    final expiresAt = item['expires_at']?.toString() ?? '';

    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kLine))),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7, height: 7,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: isExpired ? kStatusExpired : kStatusSoon, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (ownerName?.isNotEmpty ?? false) ? '$ownerName ($username)' : username,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: kInk),
                ),
                const SizedBox(height: 3),
                Text(
                  [title, if (plate != null) 'авто $plate', if (phone != null && phone.isNotEmpty) phone].join(' · '),
                  style: const TextStyle(fontSize: 12, color: kInkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isExpired ? 'Просрочена $expiresAt' : 'До $expiresAt',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: isExpired ? kStatusExpired : kStatusSoon),
          ),
        ],
      ),
    );
  }
}

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({Key? key, required this.vehicles}) : super(key: key);
  final List<Vehicle> vehicles;

  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  late List<Vehicle> _vehicles = widget.vehicles;

  Future<void> _load() async {
    try {
      final raw = await Api.I.getVehicles();
      final list = raw.map((m) => Vehicle.fromJson(m)).toList();
      if (!mounted) return;
      setState(() => _vehicles = list);
    } catch (e) {
      if (!mounted) return;
      _toast('Ошибка обновления: $e', isError: true);
    }
  }

  Future<void> _refresh() async {
    // документы машин могли измениться — сбрасываем кэш, иначе внутри папки
    // покажется старый список
    _docsCache.clear();
    await _load();
    if (!mounted) return;
    _toast('Данные обновлены');
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
              if (!context.mounted) return;
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          children: [
            const Text('Мои автомобили', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: kInk)),
            const SizedBox(height: 12),
            for (final v in _vehicles) VehicleRow(vehicle: v),
          ],
        ),
      ),
    );
  }
}

class VehicleRow extends StatelessWidget {
  const VehicleRow({Key? key, required this.vehicle}) : super(key: key);
  final Vehicle vehicle;

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
              MaterialPageRoute(builder: (_) => DocumentsPage(vehicle: vehicle)),
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
                  child: const Icon(Icons.local_shipping_outlined, color: kAccent, size: 19),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    vehicle.plate,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: kInk),
                  ),
                ),
                Text('${vehicle.documentsCount} документов', style: const TextStyle(fontSize: 12, color: kInkMuted)),
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

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({Key? key, this.vehicle}) : super(key: key);
  final Vehicle? vehicle;

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

  String get _cacheKey => widget.vehicle != null ? 'vehicle_${widget.vehicle!.id}_docs' : 'my_docs';

  Future<void> _load() async {
    // 1) мгновенно показываем из кэша, если есть
    final cached = _docsCache.get(_cacheKey);
    if (cached != null && mounted) {
      setState(() { _documents = cached; _loading = false; });
    }
    // 2) обновляем с сервера
    try {
      final rawList = await Api.I.getDocuments(vehicleId: widget.vehicle?.id);
      final list = rawList.map((m) => Doc.fromJson(m)).toList();
      if (!mounted) return;
      setState(() { _documents = list; _loading = false; });
      _docsCache.put(_cacheKey, list);
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
                    Text(
                      widget.vehicle?.plate ?? 'Мои документы',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: kInk),
                    ),
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
                    return DocumentRow(doc: _documents[index], onDismissed: _load);
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
  const DocumentRow({Key? key, required this.doc, this.onDismissed}) : super(key: key);
  final Doc doc;
  /// Вызывается после успешного "Понятно" — чтобы список перезагрузился.
  final VoidCallback? onDismissed;

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

  bool get _showExpiryBanner =>
      doc.kind == 'business' && !doc.notificationDismissed && (doc.isExpired || doc.isExpiringSoon);

  Future<void> _dismiss(BuildContext context) async {
    try {
      await Api.I.dismissNotification(doc.id);
      onDismissed?.call();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось отправить, попробуйте ещё раз')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRow(context),
        if (_showExpiryBanner) _buildBanner(context),
      ],
    );
  }

  Widget _buildBanner(BuildContext context) {
    final color = doc.isExpired ? kStatusExpired : kStatusSoon;
    return Container(
      color: color.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              doc.isExpired
                  ? 'Путёвка просрочена — нужно обновить'
                  : 'Путёвка скоро истекает — обратитесь за новой',
              style: TextStyle(fontSize: 11.5, color: color),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _dismiss(context),
            child: Text('Понятно', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kLine)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (doc.files.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('К документу не прикреплён файл')),
              );
              return;
            }
            if (doc.files.length == 1) {
              final f = doc.files.first;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DocumentViewerPage(
                    docId: doc.id,
                    fileId: f.id,
                    title: doc.title,
                    kindLabel: doc.kindLabel,
                    expiresAt: doc.expiresAt,
                  ),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DocumentFilesPage(doc: doc)),
              );
            }
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

class DocFile {
  final int id;
  final String fileName;
  final String? contentType;
  final int? size;

  DocFile({required this.id, required this.fileName, this.contentType, this.size});

  factory DocFile.fromJson(Map<String, dynamic> m) {
    return DocFile(
      id: m['id'] as int,
      fileName: (m['file_name'] ?? 'файл').toString(),
      contentType: m['content_type']?.toString(),
      size: m['size'] is int ? m['size'] as int : int.tryParse('${m['size']}'),
    );
  }
}

class Vehicle {
  final int id;
  final String plate;
  final int documentsCount;

  Vehicle({required this.id, required this.plate, required this.documentsCount});

  factory Vehicle.fromJson(Map<String, dynamic> m) {
    return Vehicle(
      id: m['id'] as int,
      plate: (m['plate'] ?? '').toString(),
      documentsCount: m['documents_count'] is int ? m['documents_count'] as int : int.tryParse('${m['documents_count']}') ?? 0,
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
  final List<DocFile> files;
  // null — документ висит прямо на пользователе (клиент с одной машиной)
  final int? vehicleId;
  final String? vehiclePlate;
  final bool notificationDismissed;

  Doc({
    required this.id,
    required this.title,
    this.kind,
    required this.kindLabel,
    this.expiresAt,
    required this.icon,
    required this.isExpired,
    required this.isExpiringSoon,
    required this.files,
    this.vehicleId,
    this.vehiclePlate,
    this.notificationDismissed = false,
  });

  static ({IconData icon, String label}) _kindMeta(String? kind) {
    switch ((kind ?? '').toLowerCase()) {
      case 'business':
        return (icon: Icons.assignment_outlined, label: 'ПУТЕВКА');
      case 'dozvol':
        return (icon: Icons.verified_outlined, label: 'ДОЗВОЛ');
      default:
        return (icon: Icons.description, label: 'ДОКУМЕНТ');
    }
  }

  factory Doc.fromJson(Map<String, dynamic> m) {
    final kind = m['kind']?.toString();
    final meta = _kindMeta(kind);

    final files = (m['files'] as List? ?? [])
        .map((e) => DocFile.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    return Doc(
      id: m['id'] as int,
      title: (m['title'] ?? '').toString(),
      kind: kind,
      kindLabel: meta.label,
      expiresAt: m['expires_at']?.toString(),
      icon: meta.icon,
      // Считает бэкенд (accounts.models.Document.is_expired/is_expiring_soon) —
      // единый порог (7 дней) для приложения, adminui и push-уведомлений.
      isExpired: m['is_expired'] == true,
      isExpiringSoon: m['is_expiring_soon'] == true,
      files: files,
      vehicleId: m['vehicle_id'] as int?,
      vehiclePlate: m['vehicle_plate']?.toString(),
      notificationDismissed: m['notification_dismissed'] == true,
    );
  }
}

String _formatFileSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
}

IconData _fileIcon(DocFile f) {
  final ct = (f.contentType ?? '').toLowerCase();
  if (ct.contains('pdf')) return Icons.picture_as_pdf_outlined;
  if (ct.startsWith('image/')) return Icons.image_outlined;
  return Icons.insert_drive_file_outlined;
}

class DocumentFilesPage extends StatelessWidget {
  const DocumentFilesPage({Key? key, required this.doc}) : super(key: key);
  final Doc doc;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: kInk)),
            Text('${doc.files.length} файла', style: const TextStyle(fontSize: 11, color: kInkMuted)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: kLine),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: doc.files.length,
        itemBuilder: (context, index) {
          final f = doc.files[index];
          return Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kLine))),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DocumentViewerPage(
                        docId: doc.id,
                        fileId: f.id,
                        title: doc.title,
                        kindLabel: doc.kindLabel,
                        expiresAt: doc.expiresAt,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Icon(_fileIcon(f), color: kAccent, size: 22),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          f.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, color: kInk),
                        ),
                      ),
                      if (f.size != null) ...[
                        const SizedBox(width: 8),
                        Text(_formatFileSize(f.size), style: const TextStyle(fontSize: 12, color: kInkMuted)),
                      ],
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right, color: kChevron, size: 15),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class DocumentViewerPage extends StatefulWidget {
  const DocumentViewerPage({
    Key? key,
    required this.docId,
    required this.fileId,
    required this.title,
    this.kindLabel,
    this.expiresAt,
  }) : super(key: key);
  final int docId;
  final int fileId;
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

  String get _cacheKey => '${widget.docId}:${widget.fileId}';

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final cached = _bytesCache.get(_cacheKey);
      if (cached != null) {
        final ft = _detectFileType(cached);
        _setupPdfIfNeeded(ft, cached);
        if (!mounted) return;
        setState(() { _bytes = cached; _fileType = ft; _isLoading = false; });
        _refreshInBackground();
        return;
      }

      final bytes = await Api.I.fetchFileBytes(widget.docId, widget.fileId);
      final ft = _detectFileType(bytes);
      _bytesCache.put(_cacheKey, bytes);
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
      final fresh = await Api.I.fetchFileBytes(widget.docId, widget.fileId);
      if (_bytes == null || fresh.lengthInBytes != _bytes!.lengthInBytes) {
        _bytesCache.put(_cacheKey, fresh);
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
