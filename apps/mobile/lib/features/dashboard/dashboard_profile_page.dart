import 'package:flutter/material.dart';

import '../bmi/bmi_snapshot.dart';

class DashboardProfileData {
  const DashboardProfileData({
    required this.firstName,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.age,
    required this.heightCm,
    required this.heightFeet,
    required this.heightInches,
    required this.weightKg,
    required this.weightLb,
    required this.foodPreference,
    required this.selectedProblems,
    required this.primaryProblem,
    required this.activePlanLabel,
    required this.profileContext,
    required this.bmiSnapshot,
  });

  final String firstName;
  final String fullName;
  final String phone;
  final String email;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String age;
  final String heightCm;
  final String heightFeet;
  final String heightInches;
  final String weightKg;
  final String weightLb;
  final String foodPreference;
  final List<String> selectedProblems;
  final String primaryProblem;
  final String activePlanLabel;
  final String profileContext;
  final BmiSnapshot? bmiSnapshot;

  String get displayName {
    if (fullName.trim().isNotEmpty) {
      return fullName.trim();
    }
    if (firstName.trim().isNotEmpty) {
      return firstName.trim();
    }
    return 'Flicko user';
  }

  String get initials {
    final parts = displayName
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
    return parts.isEmpty ? 'F' : parts;
  }
}

class DashboardProfilePage extends StatelessWidget {
  const DashboardProfilePage({
    super.key,
    required this.data,
    required this.onEditProfile,
    required this.onEditProblems,
    required this.onLogout,
  });

  final DashboardProfileData data;
  final VoidCallback onEditProfile;
  final VoidCallback onEditProblems;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFCF8),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _ProfileTopBar(onBack: () => Navigator.of(context).pop()),
                  const SizedBox(height: 18),
                  _ProfileHero(data: data, onEditProfile: onEditProfile),
                  const SizedBox(height: 16),
                  _MetricsSection(data: data),
                  const SizedBox(height: 14),
                  _ProblemsSection(data: data, onEditProblems: onEditProblems),
                  const SizedBox(height: 14),
                  _LogoutSection(onLogout: onLogout),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoutSection extends StatelessWidget {
  const _LogoutSection({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0D9D9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Account',
            style: TextStyle(
              color: Color(0xFF0B372D),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Logout clears this saved session on the phone. Next app start will open the welcome screen.',
            style: TextStyle(
              color: Color(0xFF66736D),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: onLogout,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFD64343),
                side: const BorderSide(color: Color(0xFFE9B8B8)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text(
                'Logout',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTopBar extends StatelessWidget {
  const _ProfileTopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back to dashboard',
          onTap: onBack,
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Profile',
            style: TextStyle(
              color: Color(0xFF0B372D),
              fontSize: 22,
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
              size: 36,
            );
          },
        ),
      ],
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.data, required this.onEditProfile});

  final DashboardProfileData data;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF5FFF8), Color(0xFFE8F6EE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDCEDE2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF168878).withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 16),
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
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  data.initials,
                  style: const TextStyle(
                    color: Color(0xFF149447),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0B372D),
                        fontSize: 22,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      data.activePlanLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF51625C),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ContactPill(
                  icon: Icons.phone_rounded,
                  value: _clean(data.phone, 'Phone not added'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ContactPill(
                  icon: Icons.mail_rounded,
                  value: _clean(data.email, 'Email not added'),
                ),
              ),
            ],
          ),
          if (_hasEmergencyContact(data)) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _ContactPill(
                icon: Icons.contact_emergency_rounded,
                value: _emergencyContactLabel(data),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: onEditProfile,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF149447),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text(
                'Edit setup',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsSection extends StatelessWidget {
  const _MetricsSection({required this.data});

  final DashboardProfileData data;

  @override
  Widget build(BuildContext context) {
    final bmi = data.bmiSnapshot;
    return _SectionCard(
      title: 'Health details',
      icon: Icons.monitor_heart_rounded,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: Icons.cake_rounded,
                  label: 'Age',
                  value: _clean(data.age, 'Not added'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  icon: Icons.height_rounded,
                  label: 'Height',
                  value: bmi?.heightLabel ?? _heightFallback(data),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: Icons.scale_rounded,
                  label: 'Weight',
                  value: _weightFallback(data),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  icon: Icons.speed_rounded,
                  label: 'BMI',
                  value: bmi == null
                      ? 'Not ready'
                      : '${bmi.bmiLabel} ${bmi.category}',
                  accent: bmi?.color ?? const Color(0xFF149447),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MetricTile(
            icon: Icons.restaurant_rounded,
            label: 'Food preference',
            value: _clean(data.foodPreference, 'Not added'),
            wide: true,
          ),
        ],
      ),
    );
  }
}

class _ProblemsSection extends StatelessWidget {
  const _ProblemsSection({required this.data, required this.onEditProblems});

  final DashboardProfileData data;
  final VoidCallback onEditProblems;

  @override
  Widget build(BuildContext context) {
    final problems = data.selectedProblems.isEmpty
        ? <String>[data.primaryProblem]
        : data.selectedProblems;
    return _SectionCard(
      title: 'Selected problems',
      icon: Icons.health_and_safety_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final problem in problems)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: problem == data.primaryProblem
                        ? const Color(0xFF149447)
                        : const Color(0xFFEAF7EE),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: problem == data.primaryProblem
                          ? const Color(0xFF149447)
                          : const Color(0xFFD8ECDE),
                    ),
                  ),
                  child: Text(
                    problem,
                    style: TextStyle(
                      color: problem == data.primaryProblem
                          ? Colors.white
                          : const Color(0xFF0B5B2D),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: onEditProblems,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF149447),
                side: const BorderSide(color: Color(0xFFCFE7D8)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text(
                'Edit problems',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5EEE8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF7EE),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: const Color(0xFF149447), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0B372D),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = const Color(0xFF149447),
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EFE9)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF75827C),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF12372D),
                    fontSize: 13.2,
                    fontWeight: FontWeight.w900,
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

class _ContactPill extends StatelessWidget {
  const _ContactPill({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF149447), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF33423C),
                fontSize: 12.2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: Color(0xFFEAF7EE),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFF0B5B2D), size: 22),
        ),
      ),
    );
  }
}

String _clean(String value, String fallback) {
  final cleaned = value.trim();
  return cleaned.isEmpty ? fallback : cleaned;
}

bool _hasEmergencyContact(DashboardProfileData data) {
  return data.emergencyContactName.trim().isNotEmpty ||
      data.emergencyContactPhone.trim().isNotEmpty;
}

String _emergencyContactLabel(DashboardProfileData data) {
  final name = data.emergencyContactName.trim();
  final phone = data.emergencyContactPhone.trim();
  if (name.isNotEmpty && phone.isNotEmpty) {
    return '$name - $phone';
  }
  if (phone.isNotEmpty) {
    return phone;
  }
  return name;
}

String _heightFallback(DashboardProfileData data) {
  if (data.heightCm.trim().isNotEmpty) {
    return '${data.heightCm.trim()} cm';
  }
  if (data.heightFeet.trim().isNotEmpty) {
    final inches = data.heightInches.trim().isEmpty
        ? '0'
        : data.heightInches.trim();
    return '${data.heightFeet.trim()} ft $inches in';
  }
  return 'Not added';
}

String _weightFallback(DashboardProfileData data) {
  if (data.weightKg.trim().isNotEmpty && data.weightLb.trim().isNotEmpty) {
    return '${data.weightKg.trim()} kg / ${data.weightLb.trim()} lb';
  }
  if (data.weightKg.trim().isNotEmpty) {
    return '${data.weightKg.trim()} kg';
  }
  if (data.weightLb.trim().isNotEmpty) {
    return '${data.weightLb.trim()} lb';
  }
  return 'Not added';
}
