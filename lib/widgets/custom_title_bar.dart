import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class CustomTitleBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final Color backgroundColor;
  final List<Widget>? actions;
  final Widget? leading;

  const CustomTitleBar({
    super.key,
    required this.title,
    required this.backgroundColor,
    this.actions,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Row(
            children: [
              if (leading != null) leading!,
              
              // 💡 核心魔法：DragToMoveArea，包裹住这个区域，鼠标按住就能拖动整个窗口
              Expanded(
                child: DragToMoveArea(
                  child: Container(
                    color: Colors.transparent, // 必须有颜色才能响应拖拽事件
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.only(left: leading == null ? 16 : 0),
                    child: title,
                  ),
                ),
              ),

              // 右侧自定义操作按钮（如搜索、设置）
              if (actions != null) ...actions!,

              // 💡 手绘的系统控制按钮：最小化、最大化、关闭
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.minimize, color: Colors.white, size: 20),
                    onPressed: () async => await windowManager.minimize(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.crop_square, color: Colors.white, size: 18),
                    onPressed: () async {
                      if (await windowManager.isMaximized()) {
                        await windowManager.unmaximize();
                      } else {
                        await windowManager.maximize();
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    hoverColor: Colors.red, // 鼠标悬停变红
                    onPressed: () async => await windowManager.close(),
                  ),
                  const SizedBox(width: 8), // 留出一点边距
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}