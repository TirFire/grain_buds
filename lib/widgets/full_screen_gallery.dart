import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

// 💡 核心修复：引入 media_kit，隐藏冲突状态，并加载视频 UI 库
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
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: PageView.builder(
        itemCount: widget.images.length,
        controller: _pageController,
        itemBuilder: (context, index) {
          final path = widget.images[index];
          final ext = p.extension(path).toLowerCase();
          
          // 如果发现扩展名是视频，就调用专属的 media_kit 视频全屏播放器
          if (ext == '.mp4' || ext == '.mov') {
            return _FullScreenVideoItem(videoPath: path);
          }
          
          // 否则当作普通图片/GIF处理
          return InteractiveViewer(
            minScale: 1.0, maxScale: 4.0,
            child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
          );
        },
      ),
    );
  }
}

// ================= 子组件：全屏视频播放器 (media_kit 升级版) =================
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

  @override
  void initState() {
    super.initState();
    player.setPlaylistMode(PlaylistMode.loop); // 默认循环播放
    player.open(Media(widget.videoPath));      // 自动播放
    
    // 监听播放状态
    player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _isPlaying = playing);
      }
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 核心视频渲染组件
          Video(
            controller: controller, 
            controls: NoVideoControls // 禁用默认控制栏，我们自己画中间的播放键
          ),
          
          // 点击画面可以暂停/继续，并有平滑的动画图标
          GestureDetector(
            onTap: () {
              if (_isPlaying) {
                player.pause();
              } else {
                player.play();
              }
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