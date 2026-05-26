import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DashboardReportCreationResult {
  const DashboardReportCreationResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

typedef DashboardReportCreator =
    Future<DashboardReportCreationResult> Function();
typedef DashboardReportOpenUrlResolver =
    Future<String> Function({
      required String title,
      required String url,
      required String apiUrl,
      required bool isPdf,
    });

class DashboardReportsView extends StatefulWidget {
  const DashboardReportsView({
    super.key,
    required this.firstName,
    required this.problemName,
    required this.reports,
    required this.fallbackTitle,
    required this.fallbackBody,
    required this.dashboardNotes,
    required this.reminders,
    required this.healthLogCount,
    required this.mealAnalysisCount,
    required this.averageMealScore,
    required this.highRiskMealCount,
    required this.careTaskCount,
    this.onCreateReport,
    this.onResolveOpenUrl,
  });

  final String firstName;
  final String problemName;
  final List<String> reports;
  final String fallbackTitle;
  final String fallbackBody;
  final List<String> dashboardNotes;
  final List<String> reminders;
  final int healthLogCount;
  final int mealAnalysisCount;
  final int averageMealScore;
  final int highRiskMealCount;
  final int careTaskCount;
  final DashboardReportCreator? onCreateReport;
  final DashboardReportOpenUrlResolver? onResolveOpenUrl;

  @override
  State<DashboardReportsView> createState() => _DashboardReportsViewState();
}

class _DashboardReportsViewState extends State<DashboardReportsView> {
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    final parsedReports = widget.reports
        .map(_ReportEntry.fromRaw)
        .toList(growable: false);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _ReportIconBubble(icon: Icons.bar_chart_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reports',
                        style: TextStyle(
                          color: Color(0xFF0B372D),
                          fontSize: 23,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${widget.problemName} PDFs, history, and doctor-ready summaries.',
                        style: const TextStyle(
                          color: Color(0xFF65736F),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _CreateReportButton(creating: _creating, onTap: _createReport),
              ],
            ),
            const SizedBox(height: 16),
            _ReportSummaryPanel(
              firstName: widget.firstName,
              problemName: widget.problemName,
              reportCount: parsedReports.length,
              healthLogCount: widget.healthLogCount,
              mealAnalysisCount: widget.mealAnalysisCount,
              averageMealScore: widget.averageMealScore,
              careTaskCount: widget.careTaskCount,
              reminderCount: widget.reminders.length,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.only(bottom: 18),
                children: [
                  if (parsedReports.isEmpty)
                    _EmptyReportsCard(
                      title: widget.fallbackTitle,
                      body: widget.fallbackBody,
                      onCreate: _createReport,
                      creating: _creating,
                    )
                  else
                    for (final report in parsedReports)
                      _ReportHistoryCard(report: report, onOpen: _openReport),
                  _ReportInsightCard(
                    title: 'Report data used',
                    lines: [
                      if (widget.dashboardNotes.isNotEmpty)
                        'Dashboard notes: ${widget.dashboardNotes.length}',
                      if (widget.reminders.isNotEmpty)
                        'AI reminders: ${widget.reminders.length}',
                      'Health logs: ${widget.healthLogCount}',
                      'Meal photo analyses: ${widget.mealAnalysisCount}',
                      if (widget.mealAnalysisCount > 0)
                        'Average meal score: ${widget.averageMealScore}/100',
                      if (widget.highRiskMealCount > 0)
                        'Food risk flags: ${widget.highRiskMealCount}',
                      'Care tasks: ${widget.careTaskCount}',
                      'Problem focus: ${widget.problemName}',
                    ],
                  ),
                  const _ReportInsightCard(
                    title: 'Doctor-ready format',
                    lines: [
                      'User snapshot and risk flags',
                      'Dashboard values and trends',
                      'Meal, routine, reminder, and care task plan',
                      'AI summary with safety note',
                    ],
                  ),
                ].separatedBy(const SizedBox(height: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createReport() async {
    final creator = widget.onCreateReport;
    if (creator == null || _creating) {
      return;
    }
    setState(() => _creating = true);
    final result = await creator();
    if (!mounted) {
      return;
    }
    setState(() => _creating = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openReport(_ReportEntry report) async {
    final resolvedPdfUrl = report.pdfUrl.trim().isEmpty
        ? ''
        : await _resolveOpenUrl(
            title: report.title,
            url: report.pdfUrl,
            apiUrl: report.pdfApiUrl,
            isPdf: true,
          );
    final resolvedHtmlUrl = report.htmlUrl.trim().isEmpty
        ? ''
        : await _resolveOpenUrl(
            title: report.title,
            url: report.htmlUrl,
            apiUrl: report.htmlApiUrl,
            isPdf: false,
          );
    final url = resolvedPdfUrl.isNotEmpty
        ? resolvedPdfUrl
        : resolvedHtmlUrl.isNotEmpty
        ? resolvedHtmlUrl
        : report.pdfUrl.trim().isNotEmpty
        ? report.pdfUrl
        : report.htmlUrl;
    await _openUrl(url);
  }

  Future<String> _resolveOpenUrl({
    required String title,
    required String url,
    required String apiUrl,
    required bool isPdf,
  }) async {
    final resolver = widget.onResolveOpenUrl;
    if (resolver == null) {
      return url;
    }
    try {
      final refreshed = await resolver(
        title: title,
        url: url,
        apiUrl: apiUrl,
        isPdf: isPdf,
      );
      return refreshed.trim().isEmpty ? url : refreshed.trim();
    } catch (_) {
      return url;
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      _showMessage('Report link is not valid.');
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        _showMessage('Could not open report link.');
      }
    } catch (_) {
      _showMessage('Could not open report link.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _ReportSummaryPanel extends StatelessWidget {
  const _ReportSummaryPanel({
    required this.firstName,
    required this.problemName,
    required this.reportCount,
    required this.healthLogCount,
    required this.mealAnalysisCount,
    required this.averageMealScore,
    required this.careTaskCount,
    required this.reminderCount,
  });

  final String firstName;
  final String problemName;
  final int reportCount;
  final int healthLogCount;
  final int mealAnalysisCount;
  final int averageMealScore;
  final int careTaskCount;
  final int reminderCount;

  @override
  Widget build(BuildContext context) {
    final displayName = firstName.trim().isEmpty ? 'your' : firstName.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF4FFF7), Color(0xFFE7F7ED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD7ECDD)),
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
            '$displayName $problemName report center',
            style: const TextStyle(
              color: Color(0xFF0B372D),
              fontSize: 18,
              height: 1.15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Reports combine profile, chat intake, logs, meal checks, care tasks, reminders, and dashboard values.',
            style: TextStyle(
              color: Color(0xFF51625C),
              fontSize: 12.8,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (reminderCount > 0) ...[
            const SizedBox(height: 7),
            Text(
              '$reminderCount reminder${reminderCount == 1 ? '' : 's'} included in report context.',
              style: const TextStyle(
                color: Color(0xFF65736F),
                fontSize: 11.8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricPill(label: 'Reports', value: '$reportCount'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricPill(label: 'Logs', value: '$healthLogCount'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricPill(
                  label: 'Meals',
                  value: mealAnalysisCount == 0 ? '0' : '$averageMealScore/100',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricPill(label: 'Tasks', value: '$careTaskCount'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportHistoryCard extends StatelessWidget {
  const _ReportHistoryCard({required this.report, required this.onOpen});

  final _ReportEntry report;
  final ValueChanged<_ReportEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: const Color(0xFFE3EAE6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ReportIconBubble(icon: Icons.picture_as_pdf_outlined),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.title,
                  style: const TextStyle(
                    color: Color(0xFF10231D),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  report.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF51625C),
                    fontSize: 12.8,
                    height: 1.36,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (report.pdfUrl.isNotEmpty)
                      _ReportAction(
                        icon: Icons.picture_as_pdf_outlined,
                        label: 'Open PDF',
                        onTap: () => onOpen(
                          report.copyWith(htmlUrl: '', htmlApiUrl: ''),
                        ),
                      ),
                    if (report.htmlUrl.isNotEmpty)
                      _ReportAction(
                        icon: Icons.language_rounded,
                        label: 'Open HTML',
                        onTap: () =>
                            onOpen(report.copyWith(pdfUrl: '', pdfApiUrl: '')),
                      ),
                    if (report.pdfUrl.isEmpty && report.htmlUrl.isEmpty)
                      const _ReportAction(
                        icon: Icons.lock_clock_rounded,
                        label: 'Pending sync',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyReportsCard extends StatelessWidget {
  const _EmptyReportsCard({
    required this.title,
    required this.body,
    required this.onCreate,
    required this.creating,
  });

  final String title;
  final String body;
  final VoidCallback onCreate;
  final bool creating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: const Color(0xFFE3EAE6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ReportIconBubble(icon: Icons.picture_as_pdf_outlined),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF10231D),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF51625C),
                    fontSize: 13,
                    height: 1.38,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 13),
                _ReportAction(
                  icon: Icons.auto_awesome_rounded,
                  label: creating ? 'Creating...' : 'Create report',
                  onTap: creating ? null : onCreate,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportInsightCard extends StatelessWidget {
  const _ReportInsightCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: const Color(0xFFE3EAE6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF10231D),
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF149447),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: Color(0xFF51625C),
                        fontSize: 12.8,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
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

class _CreateReportButton extends StatelessWidget {
  const _CreateReportButton({required this.creating, required this.onTap});

  final bool creating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF149447),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: creating ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                creating ? Icons.hourglass_top_rounded : Icons.add_rounded,
                color: Colors.white,
                size: 17,
              ),
              const SizedBox(width: 5),
              Text(
                creating ? 'Wait' : 'New',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
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

class _ReportAction extends StatelessWidget {
  const _ReportAction({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEAF7EE),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF0B5B2D), size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF0B5B2D),
                  fontSize: 12,
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

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCECE3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF149447),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF65736F),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportIconBubble extends StatelessWidget {
  const _ReportIconBubble({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 47,
      height: 47,
      decoration: BoxDecoration(
        color: const Color(0xFF149447).withValues(alpha: 0.11),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: const Color(0xFF149447), size: 22),
    );
  }
}

class _ReportEntry {
  const _ReportEntry({
    required this.title,
    required this.summary,
    required this.pdfUrl,
    required this.htmlUrl,
    required this.pdfApiUrl,
    required this.htmlApiUrl,
  });

  final String title;
  final String summary;
  final String pdfUrl;
  final String htmlUrl;
  final String pdfApiUrl;
  final String htmlApiUrl;

  _ReportEntry copyWith({
    String? title,
    String? summary,
    String? pdfUrl,
    String? htmlUrl,
    String? pdfApiUrl,
    String? htmlApiUrl,
  }) {
    return _ReportEntry(
      title: title ?? this.title,
      summary: summary ?? this.summary,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      htmlUrl: htmlUrl ?? this.htmlUrl,
      pdfApiUrl: pdfApiUrl ?? this.pdfApiUrl,
      htmlApiUrl: htmlApiUrl ?? this.htmlApiUrl,
    );
  }

  static _ReportEntry fromRaw(String raw) {
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    var title = lines.isEmpty ? 'Flicko AI Health Report' : lines.first;
    var pdfUrl = '';
    var htmlUrl = '';
    var pdfApiUrl = '';
    var htmlApiUrl = '';
    final summaryLines = <String>[];

    for (final line in lines.skip(1)) {
      final lower = line.toLowerCase();
      if (lower.startsWith('pdf:')) {
        pdfUrl = line.substring(line.indexOf(':') + 1).trim();
      } else if (lower.startsWith('html:')) {
        htmlUrl = line.substring(line.indexOf(':') + 1).trim();
      } else if (lower.startsWith('pdf api:')) {
        pdfApiUrl = line.substring(line.indexOf(':') + 1).trim();
      } else if (lower.startsWith('html api:')) {
        htmlApiUrl = line.substring(line.indexOf(':') + 1).trim();
      } else {
        summaryLines.add(line);
      }
    }

    if (title.toLowerCase().startsWith('pdf:')) {
      pdfUrl = title.substring(title.indexOf(':') + 1).trim();
      title = 'Flicko AI Health Report';
    }
    if (title.toLowerCase().startsWith('html:')) {
      htmlUrl = title.substring(title.indexOf(':') + 1).trim();
      title = 'Flicko AI Health Report';
    }

    return _ReportEntry(
      title: title,
      summary: summaryLines.isEmpty
          ? 'Doctor-ready report generated from your Flicko profile and health data.'
          : summaryLines.join('\n'),
      pdfUrl: pdfUrl,
      htmlUrl: htmlUrl,
      pdfApiUrl: pdfApiUrl,
      htmlApiUrl: htmlApiUrl,
    );
  }
}

extension _SeparatedWidgets on List<Widget> {
  List<Widget> separatedBy(Widget separator) {
    final result = <Widget>[];
    for (var i = 0; i < length; i++) {
      if (i > 0) {
        result.add(separator);
      }
      result.add(this[i]);
    }
    return result;
  }
}
