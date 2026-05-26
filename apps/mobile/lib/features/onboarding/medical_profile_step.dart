import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MedicalProfileStep extends StatefulWidget {
  const MedicalProfileStep({
    super.key,
    required this.gender,
    required this.goalWeightKg,
    required this.goalWeightLb,
    required this.timezone,
    required this.language,
    required this.medications,
    required this.allergies,
    required this.diagnosis,
    required this.surgeryHistory,
    required this.familyHistory,
    required this.pregnancyCycle,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
  });

  final TextEditingController gender;
  final TextEditingController goalWeightKg;
  final TextEditingController goalWeightLb;
  final TextEditingController timezone;
  final TextEditingController language;
  final TextEditingController medications;
  final TextEditingController allergies;
  final TextEditingController diagnosis;
  final TextEditingController surgeryHistory;
  final TextEditingController familyHistory;
  final TextEditingController pregnancyCycle;
  final TextEditingController emergencyContactName;
  final TextEditingController emergencyContactPhone;

  @override
  State<MedicalProfileStep> createState() => _MedicalProfileStepState();
}

class _MedicalProfileStepState extends State<MedicalProfileStep> {
  static const _green = Color(0xFF149447);
  static const _dark = Color(0xFF0B372D);
  static const _muted = Color(0xFF66736D);
  static const _mint = Color(0xFFDFF3E5);
  static const _soft = Color(0xFFEAF7EE);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Panel(
          icon: Icons.badge_outlined,
          title: 'Identity and preferences',
          body:
              'These help Flicko use the right tone, units, and daily schedule.',
          children: [
            _ChoiceField(
              title: 'Gender',
              controller: widget.gender,
              options: const ['Female', 'Male', 'Other', 'Prefer not to say'],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TextField(
                    label: 'Goal weight kg optional',
                    controller: widget.goalWeightKg,
                    icon: Icons.flag_outlined,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TextField(
                    label: 'Goal weight lb optional',
                    controller: widget.goalWeightLb,
                    icon: Icons.flag_circle_outlined,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ChoiceField(
              title: 'Language',
              controller: widget.language,
              options: const ['Hindi', 'English', 'Gujarati', 'Hinglish'],
            ),
            const SizedBox(height: 12),
            _ChoiceField(
              title: 'Timezone',
              controller: widget.timezone,
              options: const ['Asia/Kolkata', 'UTC', 'Other'],
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Panel(
          icon: Icons.medical_information_outlined,
          title: 'Medical notes',
          body:
              'Optional details. Add only what you know. Flicko will use this for safer coaching, not diagnosis.',
          children: [
            _TextField(
              label: 'Current medications optional',
              controller: widget.medications,
              icon: Icons.medication_outlined,
              maxLines: 3,
              hintText: 'Example: Metformin 500 mg, Thyroid tablet morning',
            ),
            const SizedBox(height: 10),
            _TextField(
              label: 'Allergies optional',
              controller: widget.allergies,
              icon: Icons.warning_amber_rounded,
              maxLines: 2,
              hintText: 'Example: Penicillin, peanuts, lactose',
            ),
            const SizedBox(height: 10),
            _TextField(
              label: 'Recent diagnosis optional',
              controller: widget.diagnosis,
              icon: Icons.assignment_outlined,
              maxLines: 2,
              hintText: 'Example: Type 2 diabetes, high BP, PCOS',
            ),
            const SizedBox(height: 10),
            _TextField(
              label: 'Surgery history optional',
              controller: widget.surgeryHistory,
              icon: Icons.healing_outlined,
              maxLines: 2,
              hintText: 'Example: Appendix surgery in 2021',
            ),
            const SizedBox(height: 10),
            _TextField(
              label: 'Family history optional',
              controller: widget.familyHistory,
              icon: Icons.family_restroom_rounded,
              maxLines: 2,
              hintText: 'Example: Father diabetes, mother thyroid',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Panel(
          icon: Icons.woman_rounded,
          title: 'Women-specific notes',
          body:
              'Optional. Useful only when pregnancy, postpartum, PCOS, cycle, or fertility support is relevant.',
          children: [
            _TextField(
              label: 'Pregnancy / cycle details optional',
              controller: widget.pregnancyCycle,
              icon: Icons.calendar_month_outlined,
              maxLines: 3,
              hintText:
                  'Example: 2nd trimester, trying to conceive, irregular cycles',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Panel(
          icon: Icons.contact_emergency_outlined,
          title: 'Emergency contact',
          body:
              'Optional. Flicko shows this number in emergency safety alerts so you can open the dialer quickly.',
          children: [
            _TextField(
              label: 'Emergency contact name optional',
              controller: widget.emergencyContactName,
              icon: Icons.person_outline_rounded,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 10),
            _TextField(
              label: 'Emergency contact phone optional',
              controller: widget.emergencyContactPhone,
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.icon,
    required this.title,
    required this.body,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5EEE9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconBox(icon: icon),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _MedicalProfileStepState._dark,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      style: const TextStyle(
                        color: _MedicalProfileStepState._muted,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _ChoiceField extends StatefulWidget {
  const _ChoiceField({
    required this.title,
    required this.controller,
    required this.options,
  });

  final String title;
  final TextEditingController controller;
  final List<String> options;

  @override
  State<_ChoiceField> createState() => _ChoiceFieldState();
}

class _ChoiceFieldState extends State<_ChoiceField> {
  @override
  Widget build(BuildContext context) {
    final current = widget.controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            color: _MedicalProfileStepState._dark,
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in widget.options)
              ChoiceChip(
                label: Text(option),
                selected: current == option,
                showCheckmark: false,
                selectedColor: _MedicalProfileStepState._mint,
                backgroundColor: _MedicalProfileStepState._soft,
                side: BorderSide(
                  color: current == option
                      ? _MedicalProfileStepState._green
                      : Colors.transparent,
                ),
                labelStyle: TextStyle(
                  color: current == option
                      ? _MedicalProfileStepState._dark
                      : _MedicalProfileStepState._muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
                onSelected: (_) {
                  setState(() {
                    widget.controller.text = current == option ? '' : option;
                  });
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.controller,
    required this.icon,
    this.hintText,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.sentences,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? hintText;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        alignLabelWithHint: maxLines > 1,
        prefixIcon: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: 11,
              end: 9,
              top: maxLines > 1 ? 8 : 0,
            ),
            child: _IconBox(icon: icon, compact: true),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 48,
          minHeight: 48,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.96),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: _MedicalProfileStepState._green.withValues(alpha: 0.12),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: _MedicalProfileStepState._green.withValues(alpha: 0.12),
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: _MedicalProfileStepState._green),
        ),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, this.compact = false});

  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 30.0 : 36.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _MedicalProfileStepState._mint,
        borderRadius: BorderRadius.circular(compact ? 11 : 13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
      ),
      child: Icon(
        icon,
        color: _MedicalProfileStepState._dark,
        size: compact ? 16 : 18,
      ),
    );
  }
}
