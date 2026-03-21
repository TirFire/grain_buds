import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/home_page.dart';

// 💡 阶段 B 核心：全局状态管理器
final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<ThemeMode> globalThemeMode = ValueNotifier(ThemeMode.light);
final ValueNotifier<bool> globalEyeCareMode = ValueNotifier(false);
bool globalEnableTypingSound = false; // 供编辑器直接读取

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final prefs = await SharedPreferences.getInstance();
  final bool useLock = prefs.getBool('use_lock') ?? false;
  final String lockPwd = prefs.getString('lock_pwd') ?? '';
  // 💡 读取密保数据传给锁屏
  final String lockQuestion = prefs.getString('lock_question') ?? '';
  final String lockAnswer = prefs.getString('lock_answer') ?? '';
  
  globalThemeMode.value = (prefs.getBool('is_dark') ?? false) ? ThemeMode.dark : ThemeMode.light;
  globalEyeCareMode.value = prefs.getBool('is_eye_care') ?? false;
  globalEnableTypingSound = prefs.getBool('typing_sound') ?? false;

  runApp(MyDiaryApp(useLock: useLock, lockPwd: lockPwd, lockQuestion: lockQuestion, lockAnswer: lockAnswer));
}

class MyDiaryApp extends StatefulWidget {
  final bool useLock;
  final String lockPwd;
  final String lockQuestion; // 💡 新增
  final String lockAnswer;   // 💡 新增

  const MyDiaryApp({super.key, required this.useLock, required this.lockPwd, required this.lockQuestion, required this.lockAnswer});

  @override
  State<MyDiaryApp> createState() => _MyDiaryAppState();
}

class _MyDiaryAppState extends State<MyDiaryApp> {
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _resetIdleTimer();
  }

  void _resetIdleTimer([_]) {
    _idleTimer?.cancel();
    if (widget.useLock && widget.lockPwd.isNotEmpty) {
      _idleTimer = Timer(const Duration(minutes: 1), () {
        if (globalNavigatorKey.currentState != null) {
          globalNavigatorKey.currentState!.pushAndRemoveUntil(
            // 💡 传参给 LockScreen
            MaterialPageRoute(builder: (context) => LockScreen(correctPwd: widget.lockPwd, question: widget.lockQuestion, answer: widget.lockAnswer)),
            (route) => false,
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
      // 💡 监听主题变化，实时刷新
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: globalThemeMode,
        builder: (context, themeMode, _) {
          return ValueListenableBuilder<bool>(
            valueListenable: globalEyeCareMode,
            builder: (context, isEyeCare, _) {
              
              // 💡 动态生成主题配色
              final lightTheme = isEyeCare 
                ? ThemeData(
                    fontFamily: 'Microsoft YaHei',
                    colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
                    scaffoldBackgroundColor: const Color(0xFFFAF3E0), // 暖色护眼纸张底色
                    appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFD7CCC8), foregroundColor: Colors.black87),
                    cardColor: const Color(0xFFFFFDF8),
                    useMaterial3: true,
                  )
                : ThemeData(
                    fontFamily: 'Microsoft YaHei',
                    colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
                    useMaterial3: true,
                  );

              return MaterialApp(
                navigatorKey: globalNavigatorKey,
                title: 'GrainBuds',
                debugShowCheckedModeBanner: false,
                themeMode: themeMode,
                theme: lightTheme,
                darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
                  colorScheme: const ColorScheme.dark(primary: Colors.tealAccent),
                  appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1E1E1E)),
                ),
                home: widget.useLock && widget.lockPwd.isNotEmpty
                    ? LockScreen(correctPwd: widget.lockPwd, question: widget.lockQuestion, answer: widget.lockAnswer)
                    : const HomePage(),
              );
            }
          );
        }
      ),
    );
  }
}

// ================= 锁屏页面 =================
// ================= 锁屏页面 =================
class LockScreen extends StatefulWidget {
  final String correctPwd;
  final String question; // 💡 密保问题
  final String answer;   // 💡 密保答案

  const LockScreen({super.key, required this.correctPwd, required this.question, required this.answer});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pwdController = TextEditingController();
  bool _hasError = false;

  void _checkPwd() {
    if (_pwdController.text == widget.correctPwd) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomePage()));
    } else {
      setState(() { _hasError = true; _pwdController.clear(); });
    }
  }

  // 💡 核心找回逻辑：弹出验证密保的弹窗
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
                // 💡 验证成功！清除密码锁，并进入主页
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('use_lock', false);
                await prefs.setString('lock_pwd', '');
                
                if (mounted) {
                  Navigator.pop(c); // 关掉弹窗
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomePage()));
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
              // 💡 忘记密码的入口
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