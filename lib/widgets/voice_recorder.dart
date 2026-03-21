import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class VoiceRecorderDialog extends StatefulWidget {
  final Function(String) onRecordComplete;

  const VoiceRecorderDialog({super.key, required this.onRecordComplete});

  @override
  State<VoiceRecorderDialog> createState() => _VoiceRecorderDialogState();
}

class _VoiceRecorderDialogState extends State<VoiceRecorderDialog> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  Duration _duration = Duration.zero;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  // 💡 开始录音
  Future<void> _start() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final appDir = await getApplicationDocumentsDirectory();
        final path = p.join(appDir.path, 'REC_${DateTime.now().millisecondsSinceEpoch}.m4a');

        const config = RecordConfig(); // 默认高保真配置

        await _audioRecorder.start(config, path: path);

        setState(() {
          _isRecording = true;
          _duration = Duration.zero;
        });
        
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _duration += const Duration(seconds: 1));
        });
      }
    } catch (e) {
      debugPrint("录音启动失败: $e");
    }
  }

  // 💡 停止并保存
  Future<void> _stop() async {
    _timer?.cancel();
    final path = await _audioRecorder.stop();
    setState(() => _isRecording = false);
    
    if (path != null) {
      widget.onRecordComplete(path);
      Navigator.pop(context);
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("语音笔记", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 30),
          
          // 动态声波动画预览（V2简易版：用数字代替）
          Text(
            _formatDuration(_duration),
            style: TextStyle(
              fontSize: 48, 
              fontWeight: FontWeight.w300, 
              color: _isRecording ? Colors.red : Colors.grey
            ),
          ),
          
          const SizedBox(height: 30),
          
          GestureDetector(
            onTap: _isRecording ? _stop : _start,
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: _isRecording ? Colors.red : Colors.teal,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: (_isRecording ? Colors.red : Colors.teal).withOpacity(0.3), blurRadius: 15, spreadRadius: 5)]
              ),
              child: Icon(_isRecording ? Icons.stop : Icons.mic, color: Colors.white, size: 40),
            ),
          ),
          
          const SizedBox(height: 10),
          Text(_isRecording ? "点击停止并保存" : "点击开始录音", style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}