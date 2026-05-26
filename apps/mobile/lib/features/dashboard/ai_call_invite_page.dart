import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ai_call_models.dart';

enum AiCallInviteDecision { accept, decline, later }

class AiCallInviteResponse {
  const AiCallInviteResponse({
    required this.decision,
    this.retryAfter,
    this.note = '',
  });

  final AiCallInviteDecision decision;
  final Duration? retryAfter;
  final String note;
}

class AiCallInvitePage extends StatefulWidget {
  const AiCallInvitePage({
    super.key,
    required this.spec,
    this.coachImageAsset = 'assets/images/dashboard/live_coach.png',
  });

  final AiCallInviteSpec spec;
  final String coachImageAsset;

  @override
  State<AiCallInvitePage> createState() => _AiCallInvitePageState();
}

class _AiCallInvitePageState extends State<AiCallInvitePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _finish(AiCallInviteResponse response) {
    Navigator.of(context).pop(response);
  }

  Future<void> _chooseLaterTime() async {
    final retryAfter = await showModalBottomSheet<Duration>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const _CallLaterSheet(),
    );
    if (!mounted) {
      return;
    }
    _finish(
      AiCallInviteResponse(
        decision: AiCallInviteDecision.later,
        retryAfter: retryAfter ?? const Duration(hours: 3),
        note: retryAfter == null
            ? 'No free time selected. Retry after 3 hours.'
            : 'User selected a later call time.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFDF9),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.1,
            colors: [Color(0xFFE9F8ED), Color(0xFFFBFDF9), Colors.white],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 680;
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                child: Column(
                  children: [
                    _InviteTopBar(
                      onEnd: () => _finish(
                        const AiCallInviteResponse(
                          decision: AiCallInviteDecision.decline,
                          retryAfter: Duration(minutes: 8),
                          note:
                              'Call declined. Retry once in 8 minutes unless the user chooses a later time.',
                        ),
                      ),
                      onPickUp: () => _finish(
                        const AiCallInviteResponse(
                          decision: AiCallInviteDecision.accept,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.only(
                          top: compact ? 14 : 34,
                          bottom: 18,
                        ),
                        child: Column(
                          children: [
                            AnimatedBuilder(
                              animation: _pulse,
                              builder: (context, child) {
                                return CustomPaint(
                                  painter: _CallPulsePainter(
                                    progress: _pulse.value,
                                  ),
                                  child: child,
                                );
                              },
                              child: _CoachAvatar(
                                imageAsset: widget.coachImageAsset,
                                size: compact ? 176 : 230,
                              ),
                            ),
                            SizedBox(height: compact ? 18 : 28),
                            Text(
                              widget.spec.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: const Color(0xFF0B372D),
                                fontSize: compact ? 25 : 30,
                                height: 1.04,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              widget.spec.subtitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF51625C),
                                fontSize: 16,
                                height: 1.35,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              widget.spec.body,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF6B7771),
                                fontSize: 13.5,
                                height: 1.48,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 22),
                            _FocusChips(points: widget.spec.focusPoints),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _RoundCallAction(
                          label: 'Decline',
                          icon: Icons.call_end_rounded,
                          color: const Color(0xFFF14135),
                          onTap: () => _finish(
                            const AiCallInviteResponse(
                              decision: AiCallInviteDecision.decline,
                              retryAfter: Duration(minutes: 8),
                              note: 'Call declined. Retry once in 8 minutes.',
                            ),
                          ),
                        ),
                        _RoundCallAction(
                          label: 'Later',
                          icon: Icons.schedule_rounded,
                          color: const Color(0xFFEEF4EF),
                          foreground: const Color(0xFF2B3B35),
                          onTap: _chooseLaterTime,
                        ),
                        _RoundCallAction(
                          label: 'Pick up',
                          icon: Icons.call_rounded,
                          color: const Color(0xFF149447),
                          onTap: () => _finish(
                            const AiCallInviteResponse(
                              decision: AiCallInviteDecision.accept,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Flicko will save the call memory for dashboard, reminders, tasks, and weekly reports.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF7A8782),
                        fontSize: 11.5,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CallLaterSheet extends StatelessWidget {
  const _CallLaterSheet();

  @override
  Widget build(BuildContext context) {
    final options = <({String title, String subtitle, Duration delay})>[
      (
        title: 'After 15 minutes',
        subtitle: 'Short retry if you are almost free',
        delay: const Duration(minutes: 15),
      ),
      (
        title: 'After 30 minutes',
        subtitle: 'Good for food, travel, or meeting break',
        delay: const Duration(minutes: 30),
      ),
      (
        title: 'After 2 hours',
        subtitle: 'Use when you are busy now',
        delay: const Duration(hours: 2),
      ),
      (
        title: 'Tomorrow morning',
        subtitle: 'Flicko will call after your routine starts',
        delay: const Duration(hours: 16),
      ),
    ];

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'When should Flicko call again?',
              style: TextStyle(
                color: Color(0xFF0B372D),
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'If you skip this, Flicko will retry after 3 hours.',
              style: TextStyle(
                color: Color(0xFF68756F),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            for (final option in options)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEAF6ED),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.schedule_rounded,
                    color: Color(0xFF149447),
                  ),
                ),
                title: Text(
                  option.title,
                  style: const TextStyle(
                    color: Color(0xFF18362D),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: Text(
                  option.subtitle,
                  style: const TextStyle(
                    color: Color(0xFF6A7771),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF149447),
                ),
                onTap: () => Navigator.of(context).pop(option.delay),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Use default 3 hours'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteTopBar extends StatelessWidget {
  const _InviteTopBar({required this.onEnd, required this.onPickUp});

  final VoidCallback onEnd;
  final VoidCallback onPickUp;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(
          'assets/images/mainlogo.png',
          width: 48,
          height: 48,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.favorite_rounded,
            color: Color(0xFF149447),
            size: 42,
          ),
        ),
        const SizedBox(width: 11),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Flicko AI',
                style: TextStyle(
                  color: Color(0xFF0B372D),
                  fontSize: 17.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Incoming health coach call',
                style: TextStyle(
                  color: Color(0xFF718079),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeaderCallButton(
              tooltip: 'End call',
              icon: Icons.call_end_rounded,
              background: const Color(0xFFFFE7E4),
              foreground: const Color(0xFFE0342A),
              onTap: onEnd,
            ),
            const SizedBox(width: 8),
            _HeaderCallButton(
              tooltip: 'Pick up',
              icon: Icons.call_rounded,
              background: const Color(0xFFE3F7E8),
              foreground: const Color(0xFF149447),
              onTap: onPickUp,
            ),
          ],
        ),
      ],
    );
  }
}

class _HeaderCallButton extends StatelessWidget {
  const _HeaderCallButton({
    required this.tooltip,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: foreground, size: 22),
          ),
        ),
      ),
    );
  }
}

class _CoachAvatar extends StatelessWidget {
  const _CoachAvatar({required this.imageAsset, required this.size});

  final String imageAsset;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFE9F8EC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF149447).withValues(alpha: 0.16),
            blurRadius: 38,
            spreadRadius: 4,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          imageAsset,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: const Color(0xFFE8F6EB),
              alignment: Alignment.center,
              child: const Icon(
                Icons.support_agent_rounded,
                color: Color(0xFF149447),
                size: 78,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FocusChips extends StatelessWidget {
  const _FocusChips({required this.points});

  final List<String> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final point in points.take(6))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFDCEBE1)),
            ),
            child: Text(
              point,
              style: const TextStyle(
                color: Color(0xFF23523A),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}

class _RoundCallAction extends StatelessWidget {
  const _RoundCallAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.foreground = Colors.white,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.24),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(icon, color: foreground, size: 30),
          ),
          const SizedBox(height: 9),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF28332F),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CallPulsePainter extends CustomPainter {
  const _CallPulsePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < 3; i++) {
      final phase = (progress + (i / 3)) % 1.0;
      final radius = 116 + (phase * 48);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(
          0xFF149447,
        ).withValues(alpha: math.max(0, 0.22 - (phase * 0.18)));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CallPulsePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
