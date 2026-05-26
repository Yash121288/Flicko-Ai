import 'package:flutter/material.dart';

class ConsentSafetyScreen extends StatefulWidget {
  const ConsentSafetyScreen({
    super.key,
    required this.onAccepted,
    required this.onBack,
  });

  final VoidCallback onAccepted;
  final VoidCallback onBack;

  @override
  State<ConsentSafetyScreen> createState() => _ConsentSafetyScreenState();
}

class _ConsentSafetyScreenState extends State<ConsentSafetyScreen> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFCF8),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _TopBar(onBack: widget.onBack),
                  const SizedBox(height: 22),
                  const _StepLabel('Step 7 of 7'),
                  const SizedBox(height: 8),
                  const _HeroPanel(),
                  const SizedBox(height: 16),
                  const _SafetyPoint(
                    icon: Icons.health_and_safety_rounded,
                    title: 'AI coach, not a doctor',
                    body:
                        'Flicko gives lifestyle guidance, food support, reminders, and health education. It does not diagnose, prescribe, or replace a licensed clinician.',
                  ),
                  const SizedBox(height: 12),
                  const _SafetyPoint(
                    icon: Icons.emergency_rounded,
                    title: 'Emergency symptoms need urgent help',
                    body:
                        'Chest pain, stroke signs, severe breathing trouble, very high or low sugar, severe allergy, self-harm thoughts, or pregnancy danger signs need immediate medical care.',
                  ),
                  const SizedBox(height: 12),
                  const _SafetyPoint(
                    icon: Icons.medication_liquid_rounded,
                    title: 'Medicine changes need clinician approval',
                    body:
                        'Do not change insulin, BP medicine, thyroid medicine, steroids, pregnancy medicine, or any prescription only because of AI advice.',
                  ),
                  const SizedBox(height: 12),
                  const _SafetyPoint(
                    icon: Icons.lock_outline_rounded,
                    title: 'Your profile powers personalization',
                    body:
                        'Your selected problems, profile, chat, call notes, meals, and progress can be used inside Flicko to personalize coaching and reports.',
                  ),
                  const SizedBox(height: 16),
                  _ConsentCheck(
                    accepted: _accepted,
                    onChanged: (value) => setState(() => _accepted = value),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _accepted ? widget.onAccepted : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF149447),
                        disabledBackgroundColor: const Color(0xFFDFE8E3),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: const Color(0xFF8A9692),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      icon: const Icon(Icons.verified_user_rounded, size: 19),
                      label: const Text('Accept and open dashboard'),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _FlowDots(activeIndex: 6, count: 7),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF149447),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: const Color(0xFFEAF7EE),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onBack,
            child: const SizedBox(
              width: 42,
              height: 42,
              child: Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF0B372D),
                size: 22,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Safety consent',
            style: TextStyle(
              color: Color(0xFF0B372D),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Image.asset(
          'assets/images/mainlogo.png',
          width: 42,
          height: 42,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.favorite_rounded,
              color: Color(0xFF149447),
              size: 34,
            );
          },
        ),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF7FFF9), Color(0xFFEAF7EE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDCEDE2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF149447).withValues(alpha: 0.12),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBadge(icon: Icons.shield_rounded, size: 54),
          SizedBox(height: 14),
          Text(
            'Before Flicko starts coaching',
            style: TextStyle(
              color: Color(0xFF0B372D),
              fontSize: 29,
              height: 1.08,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Read these safety rules once. They keep the AI useful for daily health support without crossing medical boundaries.',
            style: TextStyle(
              color: Color(0xFF5E6D67),
              fontSize: 14.5,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyPoint extends StatelessWidget {
  const _SafetyPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5EEE9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBadge(icon: icon, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0B372D),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF66736D),
                    fontSize: 13,
                    height: 1.38,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentCheck extends StatelessWidget {
  const _ConsentCheck({required this.accepted, required this.onChanged});

  final bool accepted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEAF7EE),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onChanged(!accepted),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: accepted,
                activeColor: const Color(0xFF149447),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                onChanged: (value) => onChanged(value ?? false),
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'I understand Flicko is a health assistant for coaching and education, not emergency care, diagnosis, or prescription treatment.',
                  style: TextStyle(
                    color: Color(0xFF0B372D),
                    fontSize: 13.5,
                    height: 1.38,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlowDots extends StatelessWidget {
  const _FlowDots({required this.activeIndex, required this.count});

  final int activeIndex;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: index == activeIndex ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: index == activeIndex
                  ? const Color(0xFF149447)
                  : const Color(0xFFD7E3DE),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFDFF3E5),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF149447).withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: const Color(0xFF149447), size: size * 0.46),
    );
  }
}
