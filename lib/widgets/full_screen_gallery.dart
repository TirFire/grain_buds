import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as p;

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
          
          // 💡 如果发现扩展名是视频，就调用专属的视频全屏播放器
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

// ================= 子组件：全屏视频播放器 =================
class _FullScreenVideoItem extends StatefulWidget {
  final String videoPath;
  const _FullScreenVideoItem({required this.videoPath});
  @override
  State<_FullScreenVideoItem> createState() => _FullScreenVideoItemState();
}

class _FullScreenVideoItemState extends State<_FullScreenVideoItem> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..setLooping(true) // 默认循环播放
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _controller.play(); // 自动播放
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _controller.value.isInitialized
          ? AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(_controller),
                  // 💡 点击画面可以暂停/继续，并有平滑的动画图标
                  GestureDetector(
                    onTap: () => setState(() => _controller.value.isPlaying ? _controller.pause() : _controller.play()),
                    child: Container(
                      color: Colors.transparent,
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: _controller.value.isPlaying ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: const Icon(Icons.play_circle_fill, color: Colors.white70, size: 80),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            )
          : const CircularProgressIndicator(color: Colors.amber),
    );
  }
}