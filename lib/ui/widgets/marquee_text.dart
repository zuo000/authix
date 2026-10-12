import 'package:flutter/material.dart';

/// 当文本宽度超出可用空间时自动往返平滑滚动的跑马灯组件
/// 支持手动左右手势拖动与平滑往返动效，文字不超长时零开销静态渲染
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  /// 头部与尾部停留时间
  final Duration pauseDuration;
  /// 滚动速度（逻辑像素/秒，默认 28 像素/秒，柔和不眩晕）
  final double pixelsPerSecond;
  final Curve curve;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.pauseDuration = const Duration(milliseconds: 1400),
    this.pixelsPerSecond = 28.0,
    this.curve = Curves.easeInOut,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _scrollController = ScrollController();
  bool _isLoopRunning = false;
  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _isLoopRunning = false;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  void _triggerLoop() {
    if (_isLoopRunning || _isDisposed) return;
    _isLoopRunning = true;

    Future.microtask(() async {
      while (!_isDisposed && _isLoopRunning) {
        // 1. 头部停留
        await Future.delayed(widget.pauseDuration);
        if (_isDisposed || !_isLoopRunning || !_scrollController.hasClients) break;

        final maxScroll = _scrollController.position.maxScrollExtent;
        if (maxScroll <= 0) {
          // 当前不需要滚动
          _isLoopRunning = false;
          break;
        }

        final durationMs = ((maxScroll / widget.pixelsPerSecond) * 1000).toInt().clamp(800, 8000);
        final scrollDuration = Duration(milliseconds: durationMs);

        // 2. 匀速滚至末尾
        try {
          if (_scrollController.hasClients) {
            await _scrollController.animateTo(
              maxScroll,
              duration: scrollDuration,
              curve: widget.curve,
            );
          }
        } catch (_) {
          // 手势中断等异常忽略
        }

        // 3. 尾部停留展示
        await Future.delayed(widget.pauseDuration);
        if (_isDisposed || !_isLoopRunning || !_scrollController.hasClients) break;

        // 4. 滚回起始位置
        try {
          if (_scrollController.hasClients) {
            await _scrollController.animateTo(
              0,
              duration: scrollDuration,
              curve: widget.curve,
            );
          }
        } catch (_) {}
      }
      _isLoopRunning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = widget.style ?? DefaultTextStyle.of(context).style;

    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: textStyle),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: double.infinity);

        final textWidth = textPainter.width;
        final availableWidth = constraints.maxWidth;

        // 容器完全装得下，直接静态文本渲染
        if (textWidth <= availableWidth) {
          return Text(
            widget.text,
            style: textStyle,
            maxLines: 1,
          );
        }

        // 文字溢出，在当前帧渲染后触发平滑循环滚动
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isDisposed && _scrollController.hasClients) {
            _triggerLoop();
          }
        });

        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Text(
            widget.text,
            style: textStyle,
            maxLines: 1,
          ),
        );
      },
    );
  }
}
