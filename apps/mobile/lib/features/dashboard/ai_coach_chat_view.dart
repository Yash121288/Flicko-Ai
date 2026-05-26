import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';

import '../protocols/local_protocol_pack.dart';
import '../safety/flicko_safety_alert_sheet.dart';
import '../safety/flicko_safety_engine.dart';
import 'gemini_health_chat_client.dart';

typedef BackendAiContextLoader = Future<String> Function(String userText);
typedef MedicalReportSaver =
    Future<String> Function({
      required String summary,
      required String fileName,
      required String mimeType,
    });

enum AiReportUploadSource { file, gallery, camera }

class AiCoachChatView extends StatefulWidget {
  const AiCoachChatView({
    super.key,
    required this.firstName,
    required this.problemName,
    required this.aiPrompt,
    required this.aiAssetPath,
    required this.profileContext,
    this.initialMessages = const <AiCoachMessage>[],
    this.onMessagesChanged,
    this.onSafetyEvent,
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    required this.onCallNow,
    required this.onBack,
    this.onLoadBackendContext,
    this.onMedicalReportExtracted,
    this.autoOpenReportUploadRequestId = 0,
    this.client = const GeminiHealthChatClient(),
  });

  final String firstName;
  final String problemName;
  final String aiPrompt;
  final String aiAssetPath;
  final String profileContext;
  final List<AiCoachMessage> initialMessages;
  final ValueChanged<List<AiCoachMessage>>? onMessagesChanged;
  final FlickoSafetyEventWriter? onSafetyEvent;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final VoidCallback onCallNow;
  final VoidCallback onBack;
  final BackendAiContextLoader? onLoadBackendContext;
  final MedicalReportSaver? onMedicalReportExtracted;
  final int autoOpenReportUploadRequestId;
  final GeminiHealthChatClient client;

  @override
  State<AiCoachChatView> createState() => _AiCoachChatViewState();
}

class _AiCoachChatViewState extends State<AiCoachChatView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final LocalProtocolPackRepository _protocolRepository =
      const LocalProtocolPackRepository();
  final List<AiCoachMessage> _messages = <AiCoachMessage>[];
  bool _sending = false;
  bool _pickingAttachment = false;
  String? _errorText;
  int _handledReportUploadRequestId = 0;

  static const int _maxReportUploadBytes = 18 * 1024 * 1024;

  static const List<String> _suggestions = [
    'Start health intake',
    'Check my meal',
    'Build today plan',
    'Add reminder',
    'Create report',
  ];

  @override
  void initState() {
    super.initState();
    _messages.addAll(widget.initialMessages);
    if (_messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    _scheduleAutoReportUploadIfNeeded();
  }

  @override
  void didUpdateWidget(covariant AiCoachChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoOpenReportUploadRequestId !=
        widget.autoOpenReportUploadRequestId) {
      _scheduleAutoReportUploadIfNeeded();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _sending) {
      return;
    }

    final history = List<AiCoachMessage>.from(
      _messages.where((message) => !message.isError),
    );
    final safetyEvent = FlickoSafetyEngine.evaluate(
      text: text,
      problemName: widget.problemName,
      source: 'chat',
    );

    setState(() {
      _errorText = null;
      _messages.add(AiCoachMessage.user(text));
      if (safetyEvent != null && safetyEvent.mustStopNormalCoaching) {
        _messages.add(
          AiCoachMessage.assistant(_emergencyCoachMessage(safetyEvent)),
        );
        _sending = false;
      } else {
        _sending = true;
      }
      if (preset == null) {
        _controller.clear();
      }
    });
    _persistMessages();
    _scrollToBottom();

    if (safetyEvent != null) {
      await Future<void>.delayed(Duration.zero);
      await widget.onSafetyEvent?.call(safetyEvent);
      if (!mounted) {
        return;
      }
      await showFlickoSafetyAlertSheet(
        context: context,
        event: safetyEvent,
        emergencyContactName: widget.emergencyContactName,
        emergencyContactPhone: widget.emergencyContactPhone,
        userName: widget.firstName,
        autoOpenEmergencyContact:
            safetyEvent.severity == FlickoSafetySeverity.emergency,
      );
      if (safetyEvent.mustStopNormalCoaching) {
        return;
      }
    }

    try {
      final protocolContext = await _loadProtocolContext(text);
      final reply = await widget.client.sendMessage(
        firstName: widget.firstName,
        problemName: widget.problemName,
        aiPrompt: widget.aiPrompt,
        profileContext: widget.profileContext,
        protocolContext: protocolContext,
        message: text,
        history: history,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(AiCoachMessage.assistant(reply));
      });
      _persistMessages();
    } on GeminiHealthChatException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.message;
        _messages.add(
          AiCoachMessage.assistant(
            error.message,
            isError: true,
            source: 'upload',
          ),
        );
      });
      _persistMessages();
    } catch (_) {
      if (!mounted) {
        return;
      }
      const fallback =
          'AI chat is unavailable right now. Try again in a moment.';
      setState(() {
        _errorText = fallback;
        _messages.add(const AiCoachMessage.assistant(fallback, isError: true));
      });
      _persistMessages();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  String _emergencyCoachMessage(FlickoSafetyEvent event) {
    if (event.severity != FlickoSafetySeverity.emergency) {
      return event.coachMessage;
    }
    final target = widget.emergencyContactPhone.trim().isNotEmpty
        ? 'aapke emergency contact'
        : 'local emergency number';
    return 'Emergency symptoms lag rahe hain. Main $target ka call abhi open kar rahi hoon. '
        'Agar call connect na ho, turant 112 ya local emergency service use karein.\n\n'
        '${event.action}';
  }

  void _scheduleAutoReportUploadIfNeeded() {
    final requestId = widget.autoOpenReportUploadRequestId;
    if (requestId <= 0 || requestId == _handledReportUploadRequestId) {
      return;
    }
    _handledReportUploadRequestId = requestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleAttach();
      }
    });
  }

  Future<String> _loadProtocolContext(String userText) async {
    final sections = <String>[];
    try {
      final context = await _protocolRepository.contextFor(
        problemName: widget.problemName,
        profileContext: widget.profileContext,
        userText: userText,
      );
      final localContext = context.toPromptText().trim();
      if (localContext.isNotEmpty) {
        sections.add(localContext);
      }
    } catch (_) {
      // Local protocol packs are an app-side enhancement; chat can continue
      // with backend memory and profile context when this load fails.
    }

    final backendLoader = widget.onLoadBackendContext;
    if (backendLoader != null) {
      try {
        final backendContext = (await backendLoader(userText)).trim();
        if (backendContext.isNotEmpty) {
          sections.add(backendContext);
        }
      } catch (_) {
        // Backend context is best-effort so chat remains usable on slow hosts.
      }
    }
    return sections.join('\n\n');
  }

  Future<void> _handleAttach() async {
    if (_sending || _pickingAttachment) {
      return;
    }

    final source = await showModalBottomSheet<AiReportUploadSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const AiReportUploadSheet(),
    );
    if (source == null || !mounted) {
      return;
    }

    setState(() => _pickingAttachment = true);
    try {
      switch (source) {
        case AiReportUploadSource.file:
          final picked = await FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
            withData: true,
          );
          final file = picked?.files.single;
          if (file == null || !mounted) {
            return;
          }

          Uint8List? bytes = file.bytes;
          if (bytes == null && file.path != null) {
            bytes = await File(file.path!).readAsBytes();
          }
          if (bytes == null) {
            throw const GeminiHealthChatException(
              'Could not read this report file. Try a smaller PDF or clear image.',
            );
          }

          final fileName = file.name.trim().isEmpty
              ? 'medical-report.${file.extension ?? 'pdf'}'
              : file.name.trim();
          await _analyzeAndSaveReport(
            bytes: bytes,
            mimeType: _mimeFromPath(fileName),
            fileName: fileName,
          );
          break;
        case AiReportUploadSource.gallery:
        case AiReportUploadSource.camera:
          final picked = await _imagePicker.pickImage(
            source: source == AiReportUploadSource.gallery
                ? ImageSource.gallery
                : ImageSource.camera,
            imageQuality: 92,
            maxWidth: 1800,
          );
          if (picked == null || !mounted) {
            return;
          }

          final bytes = await picked.readAsBytes();
          final fileName = picked.name.trim().isEmpty
              ? picked.path.split(RegExp(r'[\\/]')).last
              : picked.name.trim();
          await _analyzeAndSaveReport(
            bytes: bytes,
            mimeType: picked.mimeType ?? _mimeFromPath(fileName),
            fileName: fileName,
          );
          break;
      }
    } on GeminiHealthChatException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.message;
        _messages.add(AiCoachMessage.assistant(error.message, isError: true));
      });
      _persistMessages();
    } catch (_) {
      const message =
          'Could not read this report. Try a PDF, clear photo, or screenshot.';
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = message;
        _messages.add(
          const AiCoachMessage.assistant(
            message,
            isError: true,
            source: 'upload',
          ),
        );
      });
      _persistMessages();
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _pickingAttachment = false;
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _analyzeAndSaveReport({
    required Uint8List bytes,
    required String mimeType,
    required String fileName,
  }) async {
    if (bytes.isEmpty) {
      throw const GeminiHealthChatException('Medical report file is empty.');
    }
    if (bytes.length > _maxReportUploadBytes) {
      throw const GeminiHealthChatException(
        'This report file is too large. Upload a PDF or image under 18 MB.',
      );
    }

    setState(() {
      _errorText = null;
      _sending = true;
      _messages.add(
        AiCoachMessage.user(
          'Uploaded medical report: $fileName',
          source: 'upload',
        ),
      );
    });
    _persistMessages();
    _scrollToBottom();

    final summary = await widget.client.analyzeMedicalReportFile(
      fileBytes: bytes,
      mimeType: mimeType,
      fileName: fileName,
      problemName: widget.problemName,
      profileContext: widget.profileContext,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _messages.add(AiCoachMessage.assistant(summary, source: 'upload'));
    });
    _persistMessages();
    _scrollToBottom();

    final saver = widget.onMedicalReportExtracted;
    if (saver != null) {
      final savedMessage = await saver(
        summary: summary,
        fileName: fileName,
        mimeType: mimeType,
      );
      if (!mounted || savedMessage.trim().isEmpty) {
        return;
      }
      setState(() {
        _messages.add(
          AiCoachMessage.assistant(savedMessage.trim(), source: 'upload'),
        );
      });
      _persistMessages();
    }
  }

  void _showComingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label support will connect next.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _persistMessages() {
    widget.onMessagesChanged?.call(
      List<AiCoachMessage>.unmodifiable(_messages),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 140,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final firstName = widget.firstName.trim().isEmpty
        ? 'Guest'
        : widget.firstName.trim();

    return ColoredBox(
      color: const Color(0xFFFCFDFB),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                border: Border(
                  bottom: BorderSide(color: const Color(0xFFE6EEE8)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: AiCoachHeader(
                firstName: firstName,
                problemName: widget.problemName,
                aiAssetPath: widget.aiAssetPath,
                onBack: widget.onBack,
                onCallNow: widget.onCallNow,
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
                children: [
                  AiChatDayPill(problemName: widget.problemName),
                  if (_errorText != null) ...[
                    const SizedBox(height: 12),
                    AiChatErrorBanner(message: _errorText!),
                  ],
                  if (_messages.isEmpty) ...[
                    const SizedBox(height: 58),
                    AiCoachEmptyState(
                      aiPrompt: widget.aiPrompt,
                      onSuggestionTap: _sendMessage,
                    ),
                    const SizedBox(height: 26),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final suggestion in _suggestions)
                          AiSuggestionChip(
                            label: suggestion,
                            onTap: () => _sendMessage(suggestion),
                          ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 18),
                    for (var i = 0; i < _messages.length; i++) ...[
                      AiChatBubble(
                        message: _messages[i],
                        avatarPath: widget.aiAssetPath,
                      ),
                      if (i != _messages.length - 1) const SizedBox(height: 12),
                    ],
                    if (_sending) ...[
                      const SizedBox(height: 12),
                      AiTypingBubble(avatarPath: widget.aiAssetPath),
                    ],
                  ],
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                border: Border(top: BorderSide(color: const Color(0xFFE6EEE8))),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 18,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: AiChatComposer(
                  controller: _controller,
                  sending: _sending || _pickingAttachment,
                  onAttach: _handleAttach,
                  onVoice: () => _showComingSoon('Voice'),
                  onSend: _sendMessage,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AiCoachHeader extends StatelessWidget {
  const AiCoachHeader({
    super.key,
    required this.firstName,
    required this.problemName,
    required this.aiAssetPath,
    required this.onBack,
    required this.onCallNow,
  });

  final String firstName;
  final String problemName;
  final String aiAssetPath;
  final VoidCallback onBack;
  final VoidCallback onCallNow;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: 'Back to dashboard',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F8F6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Color(0xFF0B372D),
                  size: 18,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 47,
          height: 47,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF149447).withValues(alpha: 0.15),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            aiAssetPath,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return const ColoredBox(
                color: Color(0xFFDFF3E5),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFF149447),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Flicko AI Coach',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF0B372D),
                  fontSize: 18,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$firstName - $problemName plan',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF63736D),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 40,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF149447),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onCallNow,
            icon: const Icon(Icons.call_rounded, size: 18),
            label: const Text(
              'Call',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

class AiChatDayPill extends StatelessWidget {
  const AiChatDayPill({super.key, required this.problemName});

  final String problemName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF7EE),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$problemName context active',
          style: const TextStyle(
            color: Color(0xFF0B5B2D),
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class AiCoachEmptyState extends StatelessWidget {
  const AiCoachEmptyState({
    super.key,
    required this.aiPrompt,
    required this.onSuggestionTap,
  });

  final String aiPrompt;
  final ValueChanged<String> onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: Color(0xFFE9F8EE),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.favorite_rounded,
            color: Color(0xFF149447),
            size: 34,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Ask anything about your health plan',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF0B372D),
            fontSize: 18,
            height: 1.2,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          aiPrompt,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF61726C),
            fontSize: 13.5,
            height: 1.45,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            AiSuggestionChip(
              label: 'Check my symptoms',
              onTap: () => onSuggestionTap('Check my symptoms'),
            ),
            AiSuggestionChip(
              label: 'Build today routine',
              onTap: () => onSuggestionTap('Build today routine'),
            ),
            AiSuggestionChip(
              label: 'Score my meal',
              onTap: () => onSuggestionTap('Score my meal'),
            ),
          ],
        ),
      ],
    );
  }
}

class AiChatErrorBanner extends StatelessWidget {
  const AiChatErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6F4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF2D4CB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFC85A39),
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF8B442F),
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AiChatBubble extends StatelessWidget {
  const AiChatBubble({
    super.key,
    required this.message,
    required this.avatarPath,
  });

  final AiCoachMessage message;
  final String avatarPath;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final bubble = Flexible(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 290),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF149447)
              : message.isError
              ? const Color(0xFFFFF6F4)
              : const Color(0xFFF3F8F5),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 5),
            bottomRight: Radius.circular(isUser ? 5 : 18),
          ),
          border: message.isError
              ? Border.all(color: const Color(0xFFF1D5CE))
              : null,
        ),
        child: AiMarkdownText(
          text: message.text,
          color: isUser
              ? Colors.white
              : message.isError
              ? const Color(0xFF8B442F)
              : const Color(0xFF21372F),
        ),
      ),
    );

    return Row(
      mainAxisAlignment: isUser
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isUser) ...[
          AiTinyAvatar(assetPath: avatarPath),
          const SizedBox(width: 8),
        ],
        bubble,
      ],
    );
  }
}

class AiMarkdownText extends StatelessWidget {
  const AiMarkdownText({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      color: color,
      fontSize: 13.5,
      height: 1.35,
      fontWeight: FontWeight.w700,
    );

    return MarkdownBody(
      data: text,
      selectable: false,
      softLineBreak: true,
      shrinkWrap: true,
      styleSheet: MarkdownStyleSheet(
        p: base,
        pPadding: EdgeInsets.zero,
        a: base.copyWith(
          color: color,
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.w800,
        ),
        strong: base.copyWith(fontWeight: FontWeight.w900),
        em: base.copyWith(fontStyle: FontStyle.italic),
        code: base.copyWith(
          fontFamily: 'monospace',
          backgroundColor: color.withValues(alpha: 0.08),
        ),
        blockSpacing: 8,
        listIndent: 18,
        listBullet: base,
        codeblockPadding: const EdgeInsets.all(10),
        codeblockDecoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class AiTypingBubble extends StatelessWidget {
  const AiTypingBubble({super.key, required this.avatarPath});

  final String avatarPath;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AiTinyAvatar(assetPath: avatarPath),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F8F5),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Text(
            'Thinking...',
            style: TextStyle(
              color: Color(0xFF21372F),
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class AiTinyAvatar extends StatelessWidget {
  const AiTinyAvatar({super.key, required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: const BoxDecoration(
        color: Color(0xFFDFF3E5),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        assetPath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFF149447),
            size: 18,
          );
        },
      ),
    );
  }
}

class AiSuggestionChip extends StatelessWidget {
  const AiSuggestionChip({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFDDECE2)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF0B5B2D),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class AiReportUploadSheet extends StatelessWidget {
  const AiReportUploadSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Upload medical report',
              style: TextStyle(
                color: Color(0xFF0B372D),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Upload a PDF, clear photo, or screenshot of a lab, doctor, scan, or prescription report. Flicko will extract useful values and save the summary.',
              style: TextStyle(
                color: Color(0xFF5F7069),
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: _ReportUploadAction(
                icon: Icons.picture_as_pdf_rounded,
                label: 'PDF / file',
                onTap: () =>
                    Navigator.of(context).pop(AiReportUploadSource.file),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ReportUploadAction(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    onTap: () =>
                        Navigator.of(context).pop(AiReportUploadSource.gallery),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ReportUploadAction(
                    icon: Icons.photo_camera_rounded,
                    label: 'Camera',
                    onTap: () =>
                        Navigator.of(context).pop(AiReportUploadSource.camera),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportUploadAction extends StatelessWidget {
  const _ReportUploadAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEAF7EE),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF149447), size: 25),
              const SizedBox(height: 7),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF0B5B2D),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AiChatComposer extends StatelessWidget {
  const AiChatComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.onAttach,
    required this.onVoice,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onAttach;
  final VoidCallback onVoice;
  final Future<void> Function([String? preset]) onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE0EBE5)),
      ),
      child: Row(
        children: [
          AiComposerIcon(
            icon: Icons.attach_file_rounded,
            tooltip: 'Attach',
            onTap: onAttach,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Ask Flicko about your health...',
                border: InputBorder.none,
                isDense: true,
                hintStyle: TextStyle(
                  color: Color(0xFF7B8983),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: const TextStyle(
                color: Color(0xFF10231D),
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          AiComposerIcon(
            icon: Icons.mic_rounded,
            tooltip: 'Voice',
            onTap: onVoice,
          ),
          const SizedBox(width: 6),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: sending ? null : () => onSend(),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  gradient: sending
                      ? null
                      : const LinearGradient(
                          colors: [Color(0xFF19B456), Color(0xFF0D7D3C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: sending ? const Color(0xFFD3E5D9) : null,
                  shape: BoxShape.circle,
                ),
                child: sending
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF0B5B2D),
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.arrow_upward_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _mimeFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.pdf')) {
    return 'application/pdf';
  }
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  return 'application/pdf';
}

class AiComposerIcon extends StatelessWidget {
  const AiComposerIcon({
    super.key,
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 35,
            height: 35,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F5EC),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Color(0xFF149447), size: 19),
          ),
        ),
      ),
    );
  }
}
