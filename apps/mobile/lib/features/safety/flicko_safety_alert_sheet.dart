import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'flicko_safety_engine.dart';

const MethodChannel _flickoEmergencyCallChannel = MethodChannel(
  'flicko.health/emergency_call',
);

Future<void> showFlickoSafetyAlertSheet({
  required BuildContext context,
  required FlickoSafetyEvent event,
  String emergencyContactName = '',
  String emergencyContactPhone = '',
  String userName = '',
  bool autoOpenEmergencyContact = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => FlickoSafetyAlertSheet(
      event: event,
      emergencyContactName: emergencyContactName,
      emergencyContactPhone: emergencyContactPhone,
      userName: userName,
      autoOpenEmergencyContact: autoOpenEmergencyContact,
    ),
  );
}

String normalizeFlickoDialNumber(String number) {
  final buffer = StringBuffer();
  for (final codeUnit in number.trim().codeUnits) {
    final char = String.fromCharCode(codeUnit);
    final isDigit = codeUnit >= 48 && codeUnit <= 57;
    if (isDigit) {
      buffer.write(char);
    } else if (char == '+' && buffer.isEmpty) {
      buffer.write(char);
    }
  }
  return buffer.toString();
}

Future<bool> launchFlickoPhoneDialer(String number) async {
  final clean = normalizeFlickoDialNumber(number);
  if (clean.isEmpty) {
    return false;
  }
  final uri = Uri(scheme: 'tel', path: clean);
  try {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (error) {
    debugPrint('Flicko emergency dialer launch failed: $error');
    return false;
  }
}

Future<bool> placeFlickoEmergencyPhoneCall(
  String number, {
  int preferredSimSlot = 0,
}) async {
  final clean = normalizeFlickoDialNumber(number);
  if (clean.isEmpty) {
    return false;
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      var status = await Permission.phone.status;
      if (!status.isGranted) {
        status = await Permission.phone.request();
      }
      if (status.isGranted) {
        final placed = await _flickoEmergencyCallChannel.invokeMethod<bool>(
          'placeEmergencyCall',
          <String, Object?>{'number': clean, 'simSlot': preferredSimSlot},
        );
        if (placed == true) {
          return true;
        }
      }
    } on PlatformException catch (error) {
      debugPrint('Flicko direct emergency call skipped: ${error.message}');
    } catch (error) {
      debugPrint('Flicko direct emergency call failed: $error');
    }
  }

  return launchFlickoPhoneDialer(clean);
}

String buildFlickoEmergencyHandoffMessage({
  required String userName,
  required FlickoSafetyEvent event,
}) {
  final name = userName.trim().isEmpty ? 'User' : userName.trim();
  final reason = event.ruleId == 'chest-pain'
      ? 'chest pain ya chest pressure'
      : event.title.toLowerCase();
  return '$name ko $reason ho raha hai. Yeh emergency ho sakti hai. '
      'Kripya abhi unse baat karein, unke paas rahein, aur zarurat ho to emergency medical help arrange karein.';
}

class FlickoSafetyAlertSheet extends StatefulWidget {
  const FlickoSafetyAlertSheet({
    super.key,
    required this.event,
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.userName = '',
    this.autoOpenEmergencyContact = false,
  });

  final FlickoSafetyEvent event;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String userName;
  final bool autoOpenEmergencyContact;

  @override
  State<FlickoSafetyAlertSheet> createState() => _FlickoSafetyAlertSheetState();
}

class _FlickoSafetyAlertSheetState extends State<FlickoSafetyAlertSheet> {
  bool _autoOpenAttempted = false;

  @override
  void initState() {
    super.initState();
    _scheduleAutoOpenIfNeeded();
  }

  @override
  void didUpdateWidget(covariant FlickoSafetyAlertSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.id != widget.event.id ||
        oldWidget.emergencyContactPhone != widget.emergencyContactPhone ||
        oldWidget.userName != widget.userName ||
        oldWidget.autoOpenEmergencyContact != widget.autoOpenEmergencyContact) {
      _autoOpenAttempted = false;
      _scheduleAutoOpenIfNeeded();
    }
  }

  void _scheduleAutoOpenIfNeeded() {
    if (_autoOpenAttempted ||
        !widget.autoOpenEmergencyContact ||
        widget.event.severity != FlickoSafetySeverity.emergency) {
      return;
    }
    _autoOpenAttempted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_openPreferredEmergencyNumber());
      }
    });
  }

  Future<void> _openPreferredEmergencyNumber() async {
    final contactPhone = widget.emergencyContactPhone.trim();
    final opened = await _callNumber(
      contactPhone.isEmpty ? '112' : contactPhone,
    );
    if (!opened || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Emergency call opened on this phone.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEmergency = widget.event.severity == FlickoSafetySeverity.emergency;
    final accent = isEmergency
        ? const Color(0xFFE53935)
        : const Color(0xFFE87919);
    final soft = isEmergency
        ? const Color(0xFFFFF0EF)
        : const Color(0xFFFFF5E9);
    final contactPhone = widget.emergencyContactPhone.trim();
    final contactName = widget.emergencyContactName.trim().isEmpty
        ? 'Emergency contact'
        : widget.emergencyContactName.trim();
    final handoffMessage = buildFlickoEmergencyHandoffMessage(
      userName: widget.userName,
      event: widget.event,
    );

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCE7E1),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                color: soft,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: accent.withValues(alpha: 0.22)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.emergency_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.event.severity.label,
                          style: TextStyle(
                            color: accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          widget.event.title,
                          style: const TextStyle(
                            color: Color(0xFF10231D),
                            fontSize: 20,
                            height: 1.08,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.event.action,
                          style: const TextStyle(
                            color: Color(0xFF45524D),
                            fontSize: 13.2,
                            height: 1.38,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SafetyDetailRow(
              icon: Icons.rule_rounded,
              label: 'Matched rule',
              value: widget.event.ruleId,
            ),
            _SafetyDetailRow(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Matched text',
              value: widget.event.matchedText,
            ),
            _SafetyDetailRow(
              icon: Icons.record_voice_over_rounded,
              label: 'Tell contact',
              value: handoffMessage,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  unawaited(
                    Clipboard.setData(ClipboardData(text: handoffMessage)),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 17),
                label: const Text(
                  'Copy emergency message',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _SafetyActionButton(
                    icon: Icons.local_phone_rounded,
                    label: 'Call 112',
                    color: accent,
                    onTap: () => unawaited(_callNumber('112')),
                  ),
                ),
                if (contactPhone.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SafetyActionButton(
                      icon: Icons.contact_emergency_rounded,
                      label: 'Call $contactName',
                      color: const Color(0xFF149447),
                      onTap: () => unawaited(_callNumber(contactPhone)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0B372D),
                  side: const BorderSide(color: Color(0xFFD9E6DE)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'I understand',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _callNumber(String number) async {
    final opened = await placeFlickoEmergencyPhoneCall(
      number,
      preferredSimSlot: 0,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Could not start a call or open the phone dialer.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return opened;
  }
}

class _SafetyDetailRow extends StatelessWidget {
  const _SafetyDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF149447), size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: Color(0xFF51625C),
                  fontSize: 12.6,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(
                      color: Color(0xFF10231D),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyActionButton extends StatelessWidget {
  const _SafetyActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.2, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
