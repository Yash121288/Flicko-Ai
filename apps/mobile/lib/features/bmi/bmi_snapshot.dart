import 'package:flutter/material.dart';

class BmiSnapshot {
  const BmiSnapshot({
    required this.bmi,
    required this.weightKg,
    required this.heightCm,
    required this.age,
  });

  final double bmi;
  final int weightKg;
  final int heightCm;
  final int? age;

  static BmiSnapshot? fromProfileMetrics({
    required String weightKg,
    required String weightLb,
    required String heightCm,
    required String heightFeet,
    required String heightInches,
    required String age,
  }) {
    final parsedWeightKg = _parseWeightKg(weightKg, weightLb);
    final parsedHeightCm = _parseHeightCm(heightCm, heightFeet, heightInches);
    if (parsedWeightKg == null || parsedHeightCm == null) {
      return null;
    }

    final heightM = parsedHeightCm / 100;
    final bmi = parsedWeightKg / (heightM * heightM);
    if (bmi.isNaN || bmi.isInfinite) {
      return null;
    }

    return BmiSnapshot(
      bmi: bmi,
      weightKg: parsedWeightKg,
      heightCm: parsedHeightCm,
      age: int.tryParse(age.trim()),
    );
  }

  static int? _parseWeightKg(String weightKg, String weightLb) {
    final kg = int.tryParse(weightKg.trim());
    if (kg != null && kg > 0) {
      return kg;
    }

    final lb = int.tryParse(weightLb.trim());
    if (lb != null && lb > 0) {
      return (lb / 2.20462).round();
    }
    return null;
  }

  static int? _parseHeightCm(
    String heightCm,
    String heightFeet,
    String heightInches,
  ) {
    final cm = int.tryParse(heightCm.trim());
    if (cm != null && cm > 0) {
      return cm;
    }

    final feet = int.tryParse(heightFeet.trim());
    final inches = int.tryParse(heightInches.trim()) ?? 0;
    if (feet != null && feet > 0) {
      return ((feet * 12 + inches) * 2.54).round();
    }
    return null;
  }

  String get bmiLabel => bmi.toStringAsFixed(1);

  String get category {
    if (bmi < 18.5) {
      return 'Low BMI';
    }
    if (bmi < 25) {
      return 'Healthy range';
    }
    if (bmi < 30) {
      return 'Above range';
    }
    return 'High BMI';
  }

  String get guidance {
    if (age != null && age! < 20) {
      return 'For age below 20, BMI needs age-specific clinical charts.';
    }
    if (bmi < 18.5) {
      return 'Focus on steady nutrition, strength, sleep, and safe weight gain.';
    }
    if (bmi < 25) {
      return 'Maintain balanced meals, movement, sleep, and regular tracking.';
    }
    if (bmi < 30) {
      return 'Start with realistic fat-loss habits, protein, walking, and sleep.';
    }
    return 'Use a guided plan and consider clinician support for safer progress.';
  }

  Color get color {
    if (bmi < 18.5) {
      return const Color(0xFF4E8DE6);
    }
    if (bmi < 25) {
      return const Color(0xFF168878);
    }
    if (bmi < 30) {
      return const Color(0xFFE0A11B);
    }
    return const Color(0xFFD65353);
  }

  double get meterValue => ((bmi.clamp(15, 40) - 15) / 25).toDouble();

  String get heightLabel {
    final totalInches = (heightCm / 2.54).round();
    final feet = totalInches ~/ 12;
    final inches = totalInches % 12;
    return '$heightCm cm / $feet ft $inches in';
  }

  String get ageLabel => age == null ? 'Not added' : '$age years';
}
