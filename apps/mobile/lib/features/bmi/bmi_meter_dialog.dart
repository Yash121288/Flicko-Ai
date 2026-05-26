import 'package:flutter/material.dart';

import 'bmi_meter_painter.dart';
import 'bmi_snapshot.dart';

class BmiMeterDialog extends StatelessWidget {
  const BmiMeterDialog({super.key, required this.snapshot});

  final BmiSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final maxDialogHeight = MediaQuery.sizeOf(context).height - 48;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxWidth: 430, maxHeight: maxDialogHeight),
        decoration: BoxDecoration(
          color: const Color(0xFFFCFEFA),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F6358).withValues(alpha: 0.22),
              blurRadius: 38,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            children: [
              Positioned(
                right: -90,
                top: -80,
                child: _GlowBlob(color: snapshot.color),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: snapshot.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.monitor_heart_outlined,
                            color: snapshot.color,
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 11),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your BMI meter',
                                style: TextStyle(
                                  color: Color(0xFF16211F),
                                  fontSize: 21,
                                  height: 1.05,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Based on your saved weight, height, and age.',
                                style: TextStyle(
                                  color: Color(0xFF65736F),
                                  fontSize: 12.5,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: CustomPaint(
                        painter: BmiMeterPainter(
                          value: snapshot.meterValue,
                          pointerColor: snapshot.color,
                        ),
                        child: const SizedBox(width: 254, height: 124),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(child: _BmiScorePill(snapshot: snapshot)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _BmiFactTile(
                            icon: Icons.monitor_weight_outlined,
                            label: 'Weight',
                            value: '${snapshot.weightKg} kg',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _BmiFactTile(
                            icon: Icons.height_rounded,
                            label: 'Height',
                            value: snapshot.heightLabel,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _BmiFactTile(
                            icon: Icons.cake_outlined,
                            label: 'Age',
                            value: snapshot.ageLabel,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F6F1),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.tips_and_updates_outlined,
                            color: snapshot.color,
                            size: 19,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              snapshot.guidance,
                              style: const TextStyle(
                                color: Color(0xFF16211F),
                                fontSize: 12.7,
                                height: 1.38,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF168878),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Ignore for now',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BmiFactTile extends StatelessWidget {
  const _BmiFactTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDFE8E3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF0F6358), size: 18),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF65736F),
              fontSize: 10.8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF16211F),
              fontSize: 11.2,
              height: 1.15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BmiScorePill extends StatelessWidget {
  const _BmiScorePill({required this.snapshot});

  final BmiSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 11),
      decoration: BoxDecoration(
        color: snapshot.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: snapshot.color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            snapshot.bmiLabel,
            style: TextStyle(
              color: snapshot.color,
              fontSize: 34,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BMI',
                style: TextStyle(
                  color: Color(0xFF65736F),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                snapshot.category,
                style: const TextStyle(
                  color: Color(0xFF16211F),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      height: 190,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
      ),
    );
  }
}
