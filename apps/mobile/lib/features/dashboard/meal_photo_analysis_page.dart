import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../meals/gemini_meal_analysis_client.dart';
import '../meals/meal_analysis_entry.dart';

class MealPhotoAnalysisPage extends StatefulWidget {
  const MealPhotoAnalysisPage({
    super.key,
    required this.firstName,
    required this.problemName,
    required this.profileContext,
    required this.history,
    required this.onSaveAnalysis,
  });

  final String firstName;
  final String problemName;
  final String profileContext;
  final List<MealAnalysisEntry> history;
  final MealAnalysisWriter onSaveAnalysis;

  @override
  State<MealPhotoAnalysisPage> createState() => _MealPhotoAnalysisPageState();
}

class _MealPhotoAnalysisPageState extends State<MealPhotoAnalysisPage> {
  static const _client = GeminiMealAnalysisClient();
  final ImagePicker _picker = ImagePicker();

  XFile? _image;
  MealAnalysisEntry? _analysis;
  bool _analyzing = false;
  String _error = '';

  @override
  Widget build(BuildContext context) {
    final history = [
      ?_analysis,
      ...widget.history.where((entry) => entry.id != _analysis?.id),
    ].take(8).toList(growable: false);

    return Scaffold(
      backgroundColor: const Color(0xFFFBFCF8),
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: const Color(0xFF0B372D),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Meal photo check',
                          style: TextStyle(
                            color: Color(0xFF0B372D),
                            fontSize: 22,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.problemName} food score and corrections',
                          style: const TextStyle(
                            color: Color(0xFF65736F),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 20),
                  children: [
                    _HeroPanel(
                      firstName: widget.firstName,
                      problemName: widget.problemName,
                      image: _image,
                      analyzing: _analyzing,
                      onCamera: () => _pickAndAnalyze(ImageSource.camera),
                      onGallery: () => _pickAndAnalyze(ImageSource.gallery),
                    ),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _ErrorCard(message: _error),
                    ],
                    if (_analysis != null) ...[
                      const SizedBox(height: 12),
                      _MealScoreCard(entry: _analysis!),
                    ],
                    const SizedBox(height: 14),
                    const Text(
                      'Meal history',
                      style: TextStyle(
                        color: Color(0xFF0B372D),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (history.isEmpty)
                      const _EmptyMealHistory()
                    else
                      for (final entry in history)
                        _MealHistoryTile(entry: entry),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndAnalyze(ImageSource source) async {
    if (_analyzing) {
      return;
    }
    setState(() {
      _error = '';
      _analysis = null;
    });
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1400,
      maxHeight: 1400,
    );
    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _image = picked;
      _analyzing = true;
    });

    try {
      final bytes = await picked.readAsBytes();
      final result = await _client.analyzeMeal(
        imageBytes: bytes,
        mimeType: picked.mimeType ?? _mimeFromPath(picked.path),
        problemName: widget.problemName,
        profileContext: widget.profileContext,
        imagePath: picked.path,
      );
      final saved = await widget.onSaveAnalysis(result);
      if (!mounted) {
        return;
      }
      setState(() {
        _analysis = result;
        _error = saved ? '' : 'Meal score created but could not be saved.';
      });
    } on GeminiMealAnalysisException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Could not analyze this meal photo.');
    } finally {
      if (mounted) {
        setState(() => _analyzing = false);
      }
    }
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.firstName,
    required this.problemName,
    required this.image,
    required this.analyzing,
    required this.onCamera,
    required this.onGallery,
  });

  final String firstName;
  final String problemName;
  final XFile? image;
  final bool analyzing;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final name = firstName.trim().isEmpty ? 'your' : firstName.trim();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF4FFF7), Color(0xFFE8F8EE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFD8EDDF)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF149447).withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Score $name meal for $problemName',
            style: const TextStyle(
              color: Color(0xFF0B372D),
              fontSize: 20,
              height: 1.12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Flicko checks food items, calorie range, carb load, nutrient levels out of 10, and eat/reduce/avoid guidance.',
            style: TextStyle(
              color: Color(0xFF51625C),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 15),
          _ImagePreview(image: image, analyzing: analyzing),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _MealActionButton(
                  icon: Icons.photo_camera_rounded,
                  label: 'Camera',
                  onTap: analyzing ? null : onCamera,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MealActionButton(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  soft: true,
                  onTap: analyzing ? null : onGallery,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.image, required this.analyzing});

  final XFile? image;
  final bool analyzing;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.45,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: double.infinity,
          color: Colors.white.withValues(alpha: 0.8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image == null)
                const _ImagePlaceholder()
              else if (kIsWeb)
                Image.network(image!.path, fit: BoxFit.cover)
              else
                Image.file(File(image!.path), fit: BoxFit.cover),
              if (analyzing)
                Container(
                  color: Colors.white.withValues(alpha: 0.72),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF149447)),
                        SizedBox(height: 12),
                        Text(
                          'Analyzing meal...',
                          style: TextStyle(
                            color: Color(0xFF0B372D),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
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

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.restaurant_menu_rounded,
            color: Color(0xFF149447),
            size: 42,
          ),
          SizedBox(height: 10),
          Text(
            'Add a clear meal photo',
            style: TextStyle(
              color: Color(0xFF0B372D),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Keep plate and drink visible',
            style: TextStyle(
              color: Color(0xFF65736F),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MealScoreCard extends StatelessWidget {
  const _MealScoreCard({required this.entry});

  final MealAnalysisEntry entry;

  @override
  Widget build(BuildContext context) {
    final scoreColor = entry.score >= 75
        ? const Color(0xFF149447)
        : entry.score >= 50
        ? const Color(0xFFF2A116)
        : const Color(0xFFE24B3B);
    final nutritionNotes = <Widget>[
      if (entry.carbLoad.trim().isNotEmpty)
        _InfoChip(label: 'Carbs', value: entry.carbLoad),
      if (entry.proteinQuality.trim().isNotEmpty)
        _InfoChip(label: 'Protein', value: entry.proteinQuality),
      if (entry.fiberQuality.trim().isNotEmpty)
        _InfoChip(label: 'Fiber', value: entry.fiberQuality),
    ];
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE3EAE6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${entry.score}',
                    style: TextStyle(
                      color: scoreColor,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.mealName,
                      style: const TextStyle(
                        color: Color(0xFF10231D),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      entry.decision,
                      style: TextStyle(
                        color: scoreColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (entry.calorieRange.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.calorieRange,
                        style: const TextStyle(
                          color: Color(0xFF65736F),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (entry.nutrientScores.isNotEmpty) ...[
            _NutrientScoreBlock(scores: entry.nutrientScores),
          ],
          if (nutritionNotes.isNotEmpty) ...[
            if (entry.nutrientScores.isNotEmpty) const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: nutritionNotes),
          ],
          if (entry.detectedFoods.isNotEmpty) ...[
            const SizedBox(height: 14),
            _ListBlock(title: 'Detected foods', items: entry.detectedFoods),
          ],
          if (entry.riskFlags.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ListBlock(title: 'Watch points', items: entry.riskFlags),
          ],
          if (entry.recommendations.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ListBlock(
              title: 'Flicko correction',
              items: entry.recommendations,
            ),
          ],
        ],
      ),
    );
  }
}

class _MealHistoryTile extends StatelessWidget {
  const _MealHistoryTile({required this.entry});

  final MealAnalysisEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3EAE6)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFEAF7EE),
            child: Text(
              '${entry.score}',
              style: const TextStyle(
                color: Color(0xFF149447),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.mealName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF10231D),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.compactSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF65736F),
                    fontSize: 12,
                    height: 1.25,
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

class _ListBlock extends StatelessWidget {
  const _ListBlock({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF0B372D),
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        for (final item in items.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF149447),
                  size: 15,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: Color(0xFF51625C),
                      fontSize: 12.5,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NutrientScoreBlock extends StatelessWidget {
  const _NutrientScoreBlock({required this.scores});

  final List<MealNutrientScore> scores;

  @override
  Widget build(BuildContext context) {
    final visibleScores = scores.take(8).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Nutrition levels',
          style: TextStyle(
            color: Color(0xFF0B372D),
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 9),
        for (var index = 0; index < visibleScores.length; index++) ...[
          _NutrientScoreRow(score: visibleScores[index]),
          if (index != visibleScores.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _NutrientScoreRow extends StatelessWidget {
  const _NutrientScoreRow({required this.score});

  final MealNutrientScore score;

  @override
  Widget build(BuildContext context) {
    final color = score.score >= 7
        ? const Color(0xFF149447)
        : score.score >= 4
        ? const Color(0xFFF2A116)
        : const Color(0xFFE24B3B);
    final level = score.level.trim();
    final note = score.note.trim();
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF8),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE1EAE4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  score.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF10231D),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${score.score}/10',
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: score.score / 10,
              backgroundColor: const Color(0xFFE7EEE9),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          if (level.isNotEmpty || note.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              [level, note].where((part) => part.isNotEmpty).join(' - '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF51625C),
                fontSize: 11.5,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1FAF4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDDEDE3)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: Color(0xFF0B5B2D),
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MealActionButton extends StatelessWidget {
  const _MealActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.soft = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool soft;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: soft
            ? const Color(0xFFEAF7EE)
            : const Color(0xFF149447),
        foregroundColor: soft ? const Color(0xFF0B5B2D) : Colors.white,
        disabledBackgroundColor: const Color(0xFFE1E9E4),
        disabledForegroundColor: const Color(0xFF7C8A84),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFD4CA)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF9E2F20),
          fontSize: 12.5,
          height: 1.3,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyMealHistory extends StatelessWidget {
  const _EmptyMealHistory();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3EAE6)),
      ),
      child: const Text(
        'No meal scores yet. Upload a meal photo to start food history.',
        style: TextStyle(
          color: Color(0xFF65736F),
          fontSize: 12.5,
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _mimeFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  return 'image/jpeg';
}
