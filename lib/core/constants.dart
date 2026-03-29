import 'package:flutter/material.dart';
class AppConstants {
  // 天气状态码 -> 界面显示 映射字典
  static const Map<String, String> weatherMap = {
    'sunny': '☀️',
    'cloudy': '☁️',
    'rainy': '🌧️',
    'snowy': '❄️',
    'stormy': '🌩️',
  };

  // 心情状态码 -> 界面显示 映射字典
  static const Map<String, String> moodMap = {
    'happy': '😊',
    'joyful': '😄',
    'sad': '😔',
    'angry': '😠',
    'sleepy': '😴',
  };

  // 💡 智能解析辅助方法：输入状态码，输出 Emoji
  // 兼顾了极高的健壮性，防止脏数据导致崩溃
  static String getWeatherEmoji(String? key) {
    if (key == null) return weatherMap['sunny']!;
    // 兼容防御：如果你之前测试时存了旧的 "☀️" 符号，也能安全识别
    if (weatherMap.values.contains(key)) return key; 
    return weatherMap[key] ?? weatherMap['sunny']!;
  }

  static String getMoodEmoji(String? key) {
    if (key == null) return moodMap['happy']!;
    if (moodMap.values.contains(key)) return key;
    return moodMap[key] ?? moodMap['happy']!;
  }
  // 💡 升级版：支持传入底部栏，这样键盘弹出时布局会自动调整
  static Widget getNativeAppBar(BuildContext context, {
    required String title, 
    required Widget body, 
    List<Widget>? actions,
    Widget? bottomNavigationBar, // 💡 新增参数
  }) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: actions,
      ),
      body: body,
      bottomNavigationBar: bottomNavigationBar, // 💡 将底部栏绑定到 Scaffold 专用位置
    );
  }
}