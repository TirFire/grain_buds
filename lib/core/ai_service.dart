import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';

class AIService {

  // 1. 💡 动态获取配置，告别写死！
  static Future<Map<String, String>> _getApiConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'apiKey': prefs.getString('ai_api_key') ?? '',
      'baseUrl': prefs.getString('ai_base_url') ?? '',
      'model': prefs.getString('ai_model') ?? '',
    };
  }

  // 2. 发送基础对话
  static Future<String> sendMessage(List<Map<String, String>> messages) async {
    final config = await _getApiConfig();
    
    if (config['apiKey']!.isEmpty) {
      return "⚠️ 尚未配置 API Key。\n请点击右上角的「⚙️齿轮」按钮填入您的密钥。";
    }

    try {
      final response = await http.post(
        Uri.parse(config['baseUrl']!),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${config['apiKey']}',
        },
        body: jsonEncode({
          'model': config['model'],
          'messages': messages,
          'temperature': 0.7, 
          'stream': false, // 确保非流式请求
        }),
      ).timeout(const Duration(minutes: 2)); // 💡 关键：给推理模型足够的响应时间

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final message = data['choices'][0]['message'];
        
        // 💡 适配逻辑：如果 content 为空，则尝试读取 reasoning_content (针对推理模型)
        String content = message['content'] ?? "";
        String reasoning = message['reasoning_content'] ?? "";
        
        if (content.isEmpty && reasoning.isNotEmpty) {
          return "【思考中...】\n$reasoning";
        }
        
        return content.isNotEmpty ? content : "AI 返回了空内容";
      } else {
        // 打印详细错误方便你调试
        return "请求失败 (码: ${response.statusCode})\n详情: ${response.body}";
      }
    } catch (e) {
      return "连接超时或网络异常，请检查网络设置或尝试更换模型。\n(错误详情: $e)";
    }
  }

  // 3. 一键周总结逻辑
  static Future<String> generateWeeklySummary() async {
    final config = await _getApiConfig();
    
    if (config['apiKey']!.isEmpty) {
      return "⚠️ 尚未配置 API Key。\n请点击右上角的「⚙️齿轮」按钮填入您的密钥。";
    }

    try {
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      
      final allDiaries = await DatabaseHelper.instance.getAllDiaries();
      List<Map<String, dynamic>> thisWeekDiaries = allDiaries.where((d) {
        try {
          DateTime date = DateTime.parse(d['date'] as String);
          return date.isAfter(weekAgo) && date.isBefore(now.add(const Duration(days: 1)));
        } catch (_) {
          return false;
        }
      }).toList();

      if (thisWeekDiaries.isEmpty) {
        return "这周你还没有写下任何日记或随手记哦。要不要现在跟我聊聊这周发生了什么？";
      }

      StringBuffer promptBuffer = StringBuffer();
      promptBuffer.writeln("以下是我过去一周的日记记录，请你以一个温暖、懂心理学的好友身份，帮我总结一下这周的生活状态、情绪起伏，并给我一些温暖的建议。\n");
      
      for (var diary in thisWeekDiaries) {
        String title = diary['title'] ?? '无标题';
        String content = diary['content'] ?? '';
        String date = diary['date'] ?? '';
        String mood = diary['mood'] ?? '平静';
        promptBuffer.writeln("日期: $date");
        promptBuffer.writeln("心情: $mood");
        promptBuffer.writeln("标题: $title");
        promptBuffer.writeln("内容: $content");
        promptBuffer.writeln("-----------------");
      }

      List<Map<String, String>> messages = [
        {
          "role": "system",
          "content": "你是用户的专属时光伴侣。你的语言温暖、治愈、有同理心，擅长从琐碎的生活记录中发现闪光点，并提供轻度的心理抚慰。"
        },
        {
          "role": "user",
          "content": promptBuffer.toString()
        }
      ];

      // 在 ai_service.dart 中
      return await sendMessage(messages).timeout(const Duration(minutes: 3));
    } catch (e) {
      return "提取日记进行总结时出错了：$e";
    }
  }
    // 在 AIService 类中增加此方法
  static Future<String> speechToText(String filePath) async {
    final config = await _getApiConfig();
    if (config['apiKey']!.isEmpty) return "未配置 API Key";

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.siliconflow.cn/v1/audio/transcriptions'),
      );
      request.headers['Authorization'] = 'Bearer ${config['apiKey']}';
    
      // ==========================================
      // 💡 终极修复：硅基流动的 Whisper 模型确切 ID
      // 平台规范：模型作者/模型名称
      // ==========================================
      request.fields['model'] = 'FunAudioLLM/SenseVoiceSmall'; // 推荐使用这个，速度极快且支持中文
      // 如果上面那个不行，或者你想用 OpenAI 原版，请替换为：
      // request.fields['model'] = 'openai/whisper-large-v3';
      // 或者：
      // request.fields['model'] = 'Qwen/Qwen2-Audio-7B-Instruct'; 
    
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      // 💡 增加 30 秒超时强制熔断，防止网络假死
      var streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['text'] ?? "未识别到文字";
      } else {
        return "识别失败: ${response.statusCode}\n${response.body}";
      }
    } catch (e) {
      return "语音处理异常: $e";
    }
  }
  // ================= ✍️ 智能写作助手核心逻辑 =================

  // 内部辅助方法：简化提问流程
  static Future<String> _ask(String prompt) async {
    final messages = [{"role": "user", "content": prompt}];
    return await sendMessage(messages); // 复用已有的 sendMessage
  }

  // 1. AI 起标题 (生成 3 个选项)
  static Future<List<String>> generateTitles(String content) async {
    if (content.trim().isEmpty) return [];
    String prompt = "请根据以下日记内容，生成3个简短、文艺的标题。请直接返回这3个标题，用换行符分隔，不要输出任何额外的解释、引号或序号。\n\n内容：$content";
    String res = await _ask(prompt);
    // 过滤掉 AI 可能自带的 "1.", "-", "*" 等序号
    return res.split('\n')
        .map((e) => e.replaceAll(RegExp(r'^[\d\.、\-\*]+\s*'), '').trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  // 2. AI 润色/扩写
  static Future<String> polishContent(String content) async {
    if (content.trim().isEmpty) return "";
    String prompt = "将以下简短的日记内容进行扩写和深度润色，使其更有画面感、细节和情感。必须保持第一人称，语气自然真实，不要像AI写的。直接返回润色后的正文，不要有任何开场白或多余解释。\n\n内容：$content";
    return await _ask(prompt);
  }

  // 3. 自动提取标签 (Auto-Tagging)
  static Future<String> extractTags(String content) async {
    if (content.trim().isEmpty) return "";
    String prompt = "根据以下日记内容，提取或生成3到5个核心情绪、场景或事件标签。只返回标签名（每个标签前面必须带#号），用空格分隔，绝对不要输出其他任何文字。\n\n内容：$content";
    return await _ask(prompt);
  }

  // 4. 智能心情/天气推断 (输出 JSON)
  static Future<Map<String, String>?> inferMoodWeather(String content) async {
    if (content.trim().isEmpty) return null;
    String prompt = """
请根据以下日记推测作者当时的心情和天气。
心情可选值(严格填纯英文): happy, calm, sad, angry, anxious, tired
天气可选值(严格填纯英文): sunny, cloudy, overcast, rain, snow, wind
你必须只返回纯JSON格式，绝对不要包含任何Markdown标记或多余的文字！格式如下：
{"mood": "happy", "weather": "sunny"}

日记内容：$content
""";
    String res = await _ask(prompt);
    try {
      // 剥离 AI 可能自带的 markdown 代码块包裹
      res = res.replaceAll(RegExp(r'```json|```'), '').trim();
      final map = jsonDecode(res);
      return {
        'mood': map['mood']?.toString() ?? 'happy',
        'weather': map['weather']?.toString() ?? 'sunny'
      };
    } catch (e) {
      return null; // 解析失败则返回 null
    }
  }
  // 5. 语音速记整理 (Voice Memo Organizer)
  static Future<String> organizeVoiceMemo(String rawText) async {
    if (rawText.trim().isEmpty) return "";
    String prompt = """
这是一段语音转文字的原始识别结果。请帮我去除其中的口语废话（如“呃”、“那个”、“然后”、“就是”等），将其整理成条理清晰、带准确标点符号的文本。
要求：
1. 如果这段话包含多个待办任务，请整理成 Markdown 的待办列表（- [ ] 格式）。
2. 如果是普通的日记叙述，请整理成精简通顺的段落，保留原始情感。
3. 绝对不要输出任何开场白、解释或总结，直接返回整理后的最终正文。

原始语音：$rawText
""";
    return await _ask(prompt);
  }
}