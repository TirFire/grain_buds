import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart'; // 💡 补全了核心数据库引用
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart'; // 💡 引入媒体引擎
import 'package:window_manager/window_manager.dart'; 
import 'core/database_helper.dart';
import 'pages/home_page.dart';
import '../core/encryption_service.dart'; 
import 'package:flutter_native_splash/flutter_native_splash.dart';

final ValueNotifier<Color> globalThemeColor = ValueNotifier<Color>(Colors.teal);
final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<ThemeMode> globalThemeMode = ValueNotifier(ThemeMode.light);
final ValueNotifier<bool> globalEyeCareMode = ValueNotifier(false);

void main() async {
  // 1. 绑定 Flutter 引擎
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  // 2. 数据库工厂分离 (仅需执行一次)
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 3. 窗口管理器 (仅限桌面端)
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1000, 750), 
      minimumSize: Size(800, 600), 
      center: true, 
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, 
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // 4. 读取轻量级配置 (SharedPreferences)
  final prefs = await SharedPreferences.getInstance();
  final int autoCleanDays = prefs.getInt('auto_clean_days') ?? 30;
  DatabaseHelper.instance.autoCleanTrash(autoCleanDays);
  
  final bool useLock = prefs.getBool('use_lock') ?? false;
  final String lockPwd = prefs.getString('lock_pwd') ?? '';
  final String lockQuestion = prefs.getString('lock_question') ?? '';
  final String lockAnswer = prefs.getString('lock_answer') ?? '';
  
  globalThemeMode.value = (prefs.getBool('is_dark') ?? false) ? ThemeMode.dark : ThemeMode.light;
  globalEyeCareMode.value = prefs.getBool('is_eye_care') ?? false;
  
  final int? colorValue = prefs.getInt('themeColor');
  if (colorValue != null) {
    globalThemeColor.value = Color(colorValue);
  }

  // 5. 💡 媒体引擎初始化：放在最后，且带有错误拦截，不卡死主界面
  try {
    MediaKit.ensureInitialized(); 
  } catch (e) {
    debugPrint("媒体引擎初始化警告: $e");
  }
  FlutterNativeSplash.remove();

  // 6. 瞬间点亮 UI
  runApp(MyDiaryApp(
    useLock: useLock, 
    lockPwd: lockPwd, 
    lockQuestion: lockQuestion, 
    lockAnswer: lockAnswer
  ));
}

class MyDiaryApp extends StatefulWidget {
  final bool useLock;
  final String lockPwd;
  final String lockQuestion; 
  final String lockAnswer;   

  const MyDiaryApp({super.key, required this.useLock, required this.lockPwd, required this.lockQuestion, required this.lockAnswer});

  @override
  State<MyDiaryApp> createState() => _MyDiaryAppState();
}

class _MyDiaryAppState extends State<MyDiaryApp> {
  Timer? _idleTimer;
  bool _isLockedNow = false;

  

  @override
  void initState() {
    super.initState();
    _resetIdleTimer();
  }

  void _resetIdleTimer([_]) {
    if (_isLockedNow) return; // 💡 如果已经锁了，别再计时了
    _idleTimer?.cancel();
    if (widget.useLock && widget.lockPwd.isNotEmpty) {
      _idleTimer = Timer(const Duration(minutes: 1), () {
        if (globalNavigatorKey.currentState != null && !_isLockedNow) {
          _isLockedNow = true;
          globalNavigatorKey.currentState!.push(
            PageRouteBuilder(
              pageBuilder: (c, a1, a2) => LockScreen(
                correctPwd: widget.lockPwd, question: widget.lockQuestion, answer: widget.lockAnswer, 
                isInitialLaunch: false, // 💡 挂机弹出的标记为 false
                onUnlock: () => _isLockedNow = false, // 💡 解锁后恢复状态
              ),
              transitionsBuilder: (c, a1, a2, child) => FadeTransition(opacity: a1, child: child),
            )
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _resetIdleTimer,
      onPointerMove: _resetIdleTimer,
      behavior: HitTestBehavior.translucent,
      // 💡 核心修改：在这里多套一层 ValueListenableBuilder 来监听我们定义的 globalThemeColor
      child: ValueListenableBuilder<Color>(
        valueListenable: globalThemeColor,
        builder: (context, themeColor, _) {
          return ValueListenableBuilder<ThemeMode>(
            valueListenable: globalThemeMode,
            builder: (context, themeMode, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: globalEyeCareMode,
                builder: (context, isEyeCare, _) {
                  final lightTheme = isEyeCare 
                    ? ThemeData(
                        fontFamily: 'Microsoft YaHei',
                        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
                        scaffoldBackgroundColor: const Color(0xFFFAF3E0), 
                        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFD7CCC8), foregroundColor: Colors.black87),
                        cardColor: const Color(0xFFFFFDF8),
                        useMaterial3: true,
                      )
                    : ThemeData(
                        fontFamily: 'Microsoft YaHei',
                        // 💡 替换：这里把原本写死的 Colors.teal 换成了动态的 themeColor
                        colorScheme: ColorScheme.fromSeed(seedColor: themeColor),
                        useMaterial3: true,
                      );

                 return MaterialApp(
                    navigatorKey: globalNavigatorKey,
                    title: 'GrainBuds',
                    debugShowCheckedModeBanner: false,
                    themeMode: themeMode,
                    theme: lightTheme,
                    darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
                      // 💡 替换：暗黑模式的主色调也同步跟随
                      colorScheme: ColorScheme.dark(primary: themeColor),
                      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1E1E1E)),
                    ),
                    
                    // ==========================================
                    // 💡 核心修复：全局屏蔽手机系统的字体与显示比例放大
                    // ==========================================
                    builder: (context, child) {
                      return MediaQuery(
                        // 强制将字体缩放比例锁定为 1.0（不受手机系统设置影响）
                        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
                        child: child!,
                      );
                    },
                    
                    home: widget.useLock && widget.lockPwd.isNotEmpty
                        ? LockScreen(correctPwd: widget.lockPwd, question: widget.lockQuestion, answer: widget.lockAnswer, isInitialLaunch: true) 
                        : const HomePage(),
                  );
                }
              );
            }
          );
        }
      ),
    );
  }
}

class LockScreen extends StatefulWidget {
  final String correctPwd;
  final String question; 
  final String answer;   
  final bool isInitialLaunch; // 💡 接收标记，判断是不是刚打开软件
  final VoidCallback? onUnlock; // 💡 接收解锁成功的回调

  const LockScreen({
    super.key, 
    required this.correctPwd, 
    required this.question, 
    required this.answer, 
    this.isInitialLaunch = true, 
    this.onUnlock
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pwdController = TextEditingController();
  bool _hasError = false;

  void _checkPwd() {
    if (EncryptionService.verifyPassword(_pwdController.text, widget.correctPwd)) {
      if (widget.onUnlock != null) widget.onUnlock!();
      
      if (widget.isInitialLaunch) {
        // 如果是刚打开软件，解锁后推入主页
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomePage()));
      } else {
        // 💡 如果是挂机弹出的锁屏，直接 Pop 关掉自己就行，千万不要再推入一个新的主页了！
        Navigator.pop(context); 
      }
    } else {
      setState(() { _hasError = true; _pwdController.clear(); });
    }
  }

  void _showRecoveryDialog() {
    if (widget.question.isEmpty || widget.answer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('您之前未设置密保问题，无法找回密码')));
      return;
    }

    final answerCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('找回密码', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('密保问题：${widget.question}', style: const TextStyle(fontSize: 16, color: Colors.teal)),
            const SizedBox(height: 16),
            TextField(
              controller: answerCtrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: '请输入密保答案', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              if (answerCtrl.text.trim() == widget.answer) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('use_lock', false);
                await prefs.setString('lock_pwd', '');
                
                if (mounted) {
                  Navigator.pop(c); 
                  
                  if (widget.onUnlock != null) widget.onUnlock!(); // 💡 找回密码也属于解锁成功
                  
                  // 💡 同样修复找回密码时的路由跳转套娃问题
                  if (widget.isInitialLaunch) {
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomePage()));
                  } else {
                    Navigator.pop(context);
                  }
                  
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🔓 密码已被强制清除，请前往设置重新绑定！'), backgroundColor: Colors.teal));
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ 密保答案错误'), backgroundColor: Colors.red));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            child: const Text('验 证'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 80, color: Theme.of(context).primaryColor),
              const SizedBox(height: 20),
              const Text('欢迎回来，请输入密码', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              SizedBox(
                width: 250,
                child: TextField(
                  controller: _pwdController,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(border: const OutlineInputBorder(), errorText: _hasError ? '密码错误' : null),
                  onSubmitted: (_) => _checkPwd(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _checkPwd,
                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
                child: const Text('解 锁'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _showRecoveryDialog,
                child: const Text('忘记密码？', style: TextStyle(color: Colors.grey)),
              )
            ],
          ),
        ),
      ),
    );
  }
}