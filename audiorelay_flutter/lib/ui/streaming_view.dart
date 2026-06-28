import 'package:flutter/material.dart';

import '../state/audio_manager.dart';

class StreamingView extends StatelessWidget {
  final AudioRelayManager manager;

  const StreamingView({super.key, required this.manager});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(flex: 1),

            // Now playing animation
            _buildNowPlaying(theme),

            const SizedBox(height: 32),

            // Server info
            Text(
              'Streaming Audio',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'From: ${manager.currentServer?.name ?? "Unknown"}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 40),

            // Volume slider
            _buildVolumeControl(theme),

            const SizedBox(height: 32),

            // Stats row
            _buildStatsRow(theme),

            const Spacer(flex: 2),

            // Disconnect
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => manager.disconnect(),
                icon: const Icon(Icons.stop),
                label: const Text('Disconnect'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildNowPlaying(ThemeData theme) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withAlpha(25),
            ),
          ),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withAlpha(40),
            ),
          ),
          _AudioVisualizer(color: theme.colorScheme.primary),
        ],
      ),
    );
  }

  Widget _buildVolumeControl(ThemeData theme) {
    return Row(
      children: [
        Icon(Icons.volume_down, color: theme.colorScheme.onSurfaceVariant),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: manager.volume,
              onChanged: (v) => manager.setVolume(v),
            ),
          ),
        ),
        Icon(Icons.volume_up, color: theme.colorScheme.onSurfaceVariant),
      ],
    );
  }

  Widget _buildStatsRow(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _StatItem(
          icon: Icons.music_note,
          value: '${manager.bufferFill}',
          label: 'Buffer',
        ),
        _StatItem(
          icon: Icons.bluetooth_connected,
          value: manager.isPlaying ? 'Live' : 'Paused',
          label: 'Status',
        ),
        _StatItem(
          icon: Icons.speed,
          value: '48kHz',
          label: 'Quality',
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

/// Animated audio visualizer
class _AudioVisualizer extends StatefulWidget {
  final Color color;

  const _AudioVisualizer({required this.color});

  @override
  State<_AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<_AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return CustomPaint(
          size: const Size(60, 60),
          painter: _VisualizerPainter(
            color: widget.color,
            progress: _controller.value,
          ),
        );
      },
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  final Color color;
  final double progress;

  _VisualizerPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final centerX = size.width / 2;
    final barWidth = 4.0;
    final spacing = 8.0;
    final count = 5;

    for (int i = 0; i < count; i++) {
      final phase = (progress + i * 0.2) % 1.0;
      final height = 12 + 20 * (0.5 + 0.5 * (phase * 3.14159 * 2).sin);
      final x = centerX + (i - count / 2 + 0.5) * (barWidth + spacing);
      final y = (size.height - height) / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, height),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter old) => progress != old.progress;
}
