import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/totp/totp_engine.dart';
import '../../providers/vault_provider.dart';

/// TOTP 动态倒计时圆环小组件（响应全局时钟流，与验证码完全同频）
class TotpTimerRing extends ConsumerWidget {
  final int period;
  final double size;

  const TotpTimerRing({
    super.key,
    this.period = 30,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 监听全局时钟，每秒同步重绘
    ref.watch(totpTickerProvider);

    final state = TotpEngine.getRemainingProgress(period: period);
    final remaining = state.remainingSeconds;
    final progress = state.progress;

    final theme = Theme.of(context);
    final isUrgent = remaining <= 5;
    final color = isUrgent ? Colors.redAccent : theme.colorScheme.primary;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 2.5,
            backgroundColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          Text(
            '$remaining',
            style: TextStyle(
              fontSize: size * 0.42,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
