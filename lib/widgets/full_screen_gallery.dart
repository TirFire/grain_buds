import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

// 💡 核心：引入 media_kit 相关库
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';

class FullScreenGallery extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const FullScreenGallery({super.key, required this.images, required this.initialIndex});

  @override
  State<FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<FullScreenGallery> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black, 
        iconTheme: const IconThemeData(color: Colors.white)
      ),
      body: PageView.builder(
        itemCount: widget.images.length,
        controller: _pageController,
        itemBuilder: (context, index) {
          final path = widget.images[index];
          final ext = p.extension(path).toLowerCase();
          
          // 💡 判断如果是视频，则调用下方的视频播放组件
          if (ext == '.mp4' || ext == '.mov') {
            return _FullScreenVideoItem(videoPath: path);
          }
          
          // 💡 否则当作普通图片处理，并加入“防红屏装甲”
          return InteractiveViewer(
            minScale: 1.0, 
            maxScale: 4.0,
            child: Center(
              child: Image.file(
                File(path), 
                fit: BoxFit.contain,
                // 💡 修复：正确配置 errorBuilder 及其内部括号结构
                errorBuilder: (context, error, stackTrace) {
                  return const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white54, size: 60),
                      SizedBox(height: 16),
                      Text("图片文件已丢失", style: TextStyle(color: Colors.white54, fontSize: 16)),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

// ================= 子组件：全屏视频播放器 (带文件存在检查) =================
class _FullScreenVideoItem extends StatefulWidget {
  final String videoPath;
  const _FullScreenVideoItem({required this.videoPath});
  @override
  State<_FullScreenVideoItem> createState() => _FullScreenVideoItemState();
}

class _FullScreenVideoItemState extends State<_FullScreenVideoItem> {
  late final player = Player();
  late final controller = VideoController(player);
  bool _isPlaying = true;
  bool _fileExists = true;

  @override
  void initState() {
    super.initState();
    // 💡 防死锁：只有文件存在才启动播放引擎
    _fileExists = File(widget.videoPath).existsSync();
    if (_fileExists) {
      player.setPlaylistMode(PlaylistMode.loop);
      player.open(Media(widget.videoPath));
      player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      });
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_fileExists) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, color: Colors.white54, size: 60),
            SizedBox(height: 16),
            Text("视频文件已丢失", style: TextStyle(color: Colors.white54, fontSize: 16)),
          ],
        ),
      );
    }
    
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Video(controller: controller, controls: NoVideoControls),
          GestureDetector(
            onTap: () {
              if (_isPlaying) player.pause();
              else player.play();
            },
            child: Container(
              color: Colors.transparent,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _isPlaying ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: const Icon(Icons.play_circle_fill, color: Colors.white70, size: 80),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}