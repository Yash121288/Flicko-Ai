import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../dashboard/native_call_invite_bridge.dart';
import '../logs/health_log_entry.dart';
import 'flicko_notification_memory_store.dart';
import 'flicko_reminder_schedule.dart';

const flickoCallInvitePayloadPrefix = 'call-invite:';
const flickoCallDeclinedPayloadPrefix = 'call-invite-declined:';
const flickoCallAcceptActionId = 'flicko_call_accept';
const flickoCallDeclineActionId = 'flicko_call_decline';
const _healthReminderChannelId = 'flicko_health_reminders_v4';
const _callInviteChannelId = 'flicko_ai_call_invites_ringtone_v4';
final Int64List _premiumReminderVibrationPattern = Int64List.fromList([
  0,
  28,
  22,
  38,
  30,
  56,
]);
final Int64List _premiumCallInviteVibrationPattern = Int64List.fromList([
  0,
  70,
  42,
  110,
  42,
  160,
]);

@pragma('vm:entry-point')
void flickoNotificationTapBackground(NotificationResponse response) {
  final payload = response.payload?.trim() ?? '';
  final action = response.actionId ?? 'tap';
  if (payload.isNotEmpty) {
    unawaited(
      FlickoNotificationMemoryStore().record(
        eventType: payload.startsWith(flickoCallInvitePayloadPrefix)
            ? 'call_invite_background_$action'
            : 'notification_background_$action',
        title: 'Background notification response',
        body: payload,
        payload: payload,
      ),
    );
  }
  debugPrint(
    'Flicko background notification response: '
    '$action $payload',
  );
}

class FlickoNotificationService {
  FlickoNotificationService._();

  static final FlickoNotificationService instance =
      FlickoNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _callInvitePayloads =
      StreamController<String>.broadcast();
  final FlickoNotificationMemoryStore _memoryStore =
      FlickoNotificationMemoryStore();
  final NativeCallInviteBridge _nativeCallInviteBridge =
      const NativeCallInviteBridge();

  bool _initialized = false;
  String? _pendingInitialCallInvitePayload;

  Stream<String> get callInvitePayloads => _callInvitePayloads.stream;

  Future<bool> initialize() async {
    if (_initialized || kIsWeb) {
      return _initialized;
    }

    try {
      tz_data.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      } catch (_) {
        tz.setLocalLocation(tz.UTC);
      }

      const settings = InitializationSettings(
        android: AndroidInitializationSettings('ic_flicko_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      );

      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
        onDidReceiveBackgroundNotificationResponse:
            flickoNotificationTapBackground,
      );
      await _captureLaunchNotification();
      await requestPermission();
      _initialized = true;
      return true;
    } catch (error) {
      debugPrint('Flicko notification init skipped: $error');
      return false;
    }
  }

  Future<String?> consumeInitialCallInvitePayload() async {
    await initialize();
    final payload = _pendingInitialCallInvitePayload;
    _pendingInitialCallInvitePayload = null;
    return payload;
  }

  Future<void> _captureLaunchNotification() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      final response = details?.notificationResponse;
      if (details?.didNotificationLaunchApp == true && response != null) {
        _handleNotificationResponse(response, cacheOnly: true);
      }
    } catch (error) {
      debugPrint('Flicko launch notification read skipped: $error');
    }
  }

  void _handleNotificationResponse(
    NotificationResponse response, {
    bool cacheOnly = false,
  }) {
    final payload = response.payload?.trim() ?? '';
    if (!payload.startsWith(flickoCallInvitePayloadPrefix)) {
      if (payload.isNotEmpty) {
        unawaited(
          _memoryStore.record(
            eventType: 'notification_tapped',
            title: 'Notification opened',
            body: payload,
            payload: payload,
          ),
        );
      }
      return;
    }
    if (response.actionId == flickoCallDeclineActionId) {
      final declinedPayload =
          '$flickoCallDeclinedPayloadPrefix${payload.substring(flickoCallInvitePayloadPrefix.length)}';
      _pendingInitialCallInvitePayload = declinedPayload;
      unawaited(
        _memoryStore.record(
          eventType: 'call_invite_declined',
          title: 'Flicko call declined',
          body: declinedPayload,
          payload: declinedPayload,
        ),
      );
      if (!cacheOnly && !_callInvitePayloads.isClosed) {
        _callInvitePayloads.add(declinedPayload);
      }
      return;
    }
    _pendingInitialCallInvitePayload = payload;
    unawaited(
      _memoryStore.record(
        eventType: 'call_invite_opened',
        title: 'Flicko call opened',
        body: payload,
        payload: payload,
      ),
    );
    if (!cacheOnly && !_callInvitePayloads.isClosed) {
      _callInvitePayloads.add(payload);
    }
  }

  Future<bool> requestPermission() async {
    if (kIsWeb) {
      return false;
    }
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final androidAllowed = await android?.requestNotificationsPermission();

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final iosAllowed = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      final mac = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      final macAllowed = await mac?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      return androidAllowed ?? iosAllowed ?? macAllowed ?? true;
    } catch (error) {
      debugPrint('Flicko notification permission skipped: $error');
      return false;
    }
  }

  Future<bool> showLogSaved(HealthLogEntry entry) {
    final detail = entry.valueText.trim().isEmpty
        ? entry.note.trim()
        : entry.valueText.trim();
    return showHealthReminder(
      title: 'Flicko saved your ${entry.type.label.toLowerCase()}',
      body: detail.isEmpty
          ? 'This will update your dashboard and next AI report.'
          : '$detail saved for your dashboard and next AI report.',
      payload: 'health-log:${entry.id}',
    );
  }

  Future<bool> showHealthReminder({
    required String title,
    required String body,
    String payload = 'flicko-reminder',
  }) async {
    try {
      await initialize();
      await _plugin.show(
        id: _notificationId(payload),
        title: title,
        body: body,
        notificationDetails: _details(title: title, body: body),
        payload: payload,
      );
      unawaited(
        _memoryStore.record(
          eventType: 'notification_shown',
          title: title,
          body: body,
          payload: payload,
        ),
      );
      return true;
    } catch (error) {
      debugPrint('Flicko notification show skipped: $error');
      return false;
    }
  }

  Future<bool> showIncomingCallInvite({
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      await initialize();
      if (_canUseNativeCallInvites) {
        final nativeSent = await _nativeCallInviteBridge.showCallInvite(
          title: title,
          body: body,
          payload: payload,
        );
        if (nativeSent) {
          unawaited(
            _memoryStore.record(
              eventType: 'call_invite_shown',
              title: title,
              body: body,
              payload: payload,
            ),
          );
          return true;
        }
      }
      await _plugin.show(
        id: _notificationId(payload),
        title: title,
        body: body,
        notificationDetails: _callInviteDetails(title: title, body: body),
        payload: payload,
      );
      unawaited(
        _memoryStore.record(
          eventType: 'call_invite_shown',
          title: title,
          body: body,
          payload: payload,
        ),
      );
      return true;
    } catch (error) {
      debugPrint('Flicko call invite notification skipped: $error');
      return false;
    }
  }

  Future<bool> scheduleIncomingCallInvite({
    required String title,
    required String body,
    required DateTime scheduledAt,
    required String payload,
    bool repeatsDaily = false,
  }) async {
    try {
      await initialize();
      final safeTarget = _safeScheduleTarget(
        scheduledAt,
        repeatsDaily: repeatsDaily,
      );
      if (_canUseNativeCallInvites) {
        final nativeScheduled = await _nativeCallInviteBridge
            .scheduleCallInvite(
              title: title,
              body: body,
              payload: payload,
              scheduledAt: safeTarget,
              repeatsDaily: repeatsDaily,
            );
        if (nativeScheduled) {
          unawaited(
            _memoryStore.record(
              eventType: 'call_invite_scheduled',
              title: title,
              body: body,
              payload: payload,
              createdAt: safeTarget,
            ),
          );
          return true;
        }
      }
      Future<void> schedule(AndroidScheduleMode mode) {
        return _plugin.zonedSchedule(
          id: _notificationId(payload),
          title: title,
          body: body,
          scheduledDate: safeTarget,
          notificationDetails: _callInviteDetails(title: title, body: body),
          androidScheduleMode: mode,
          payload: payload,
          matchDateTimeComponents: repeatsDaily
              ? DateTimeComponents.time
              : null,
        );
      }

      try {
        await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (scheduleError) {
        debugPrint(
          'Flicko call invite allow-while-idle schedule fallback: '
          '$scheduleError',
        );
        await schedule(AndroidScheduleMode.inexact);
      }
      unawaited(
        _memoryStore.record(
          eventType: 'call_invite_scheduled',
          title: title,
          body: body,
          payload: payload,
          createdAt: safeTarget,
        ),
      );
      return true;
    } catch (error) {
      debugPrint('Flicko scheduled call invite skipped: $error');
      return false;
    }
  }

  Future<bool> scheduleHealthReminder({
    required String title,
    required String body,
    required DateTime scheduledAt,
    String payload = 'flicko-scheduled-reminder',
    bool repeatsDaily = true,
  }) async {
    try {
      await initialize();
      final safeTarget = _safeScheduleTarget(
        scheduledAt,
        repeatsDaily: repeatsDaily,
      );
      final scheduleKey = repeatsDaily
          ? payload
          : '$payload-${safeTarget.millisecondsSinceEpoch}';
      Future<void> schedule(AndroidScheduleMode mode) {
        return _plugin.zonedSchedule(
          id: _notificationId(scheduleKey),
          title: title,
          body: body,
          scheduledDate: safeTarget,
          notificationDetails: _details(title: title, body: body),
          androidScheduleMode: mode,
          payload: payload,
          matchDateTimeComponents: repeatsDaily
              ? DateTimeComponents.time
              : null,
        );
      }

      try {
        await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (scheduleError) {
        debugPrint(
          'Flicko reminder allow-while-idle schedule fallback: $scheduleError',
        );
        await schedule(AndroidScheduleMode.inexact);
      }
      unawaited(
        _memoryStore.record(
          eventType: 'reminder_scheduled',
          title: title,
          body: body,
          payload: payload,
          createdAt: safeTarget,
        ),
      );
      return true;
    } catch (error) {
      debugPrint('Flicko notification schedule skipped: $error');
      return false;
    }
  }

  Future<bool> scheduleReminderRequest(FlickoReminderScheduleRequest request) {
    return scheduleHealthReminder(
      title: request.title,
      body: request.body,
      scheduledAt: request.scheduledAt,
      payload: request.payload,
      repeatsDaily: request.repeatsDaily,
    );
  }

  Future<Set<String>> pendingNotificationPayloads({String prefix = ''}) async {
    try {
      await initialize();
      final requests = await _plugin.pendingNotificationRequests();
      return requests
          .map((request) => request.payload?.trim() ?? '')
          .where((payload) => payload.isNotEmpty)
          .where((payload) => prefix.isEmpty || payload.startsWith(prefix))
          .toSet();
    } catch (error) {
      debugPrint('Flicko pending notification read skipped: $error');
      return <String>{};
    }
  }

  Future<bool> cancelReminderPayload(String payload) async {
    try {
      await initialize();
      if (_canUseNativeCallInvites &&
          payload.startsWith(flickoCallInvitePayloadPrefix)) {
        await _nativeCallInviteBridge.cancelCallInvite(payload);
      }
      await _plugin.cancel(id: _notificationId(payload));
      unawaited(
        _memoryStore.record(
          eventType: 'notification_cancelled',
          title: 'Notification cancelled',
          body: payload,
          payload: payload,
        ),
      );
      return true;
    } catch (error) {
      debugPrint('Flicko notification cancel skipped: $error');
      return false;
    }
  }

  bool get _canUseNativeCallInvites {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  NotificationDetails _details({required String title, required String body}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _healthReminderChannelId,
        'Flicko Health Reminders',
        channelDescription:
            'Premium health check-ins, meal prompts, medicine reminders, and daily plan nudges.',
        icon: 'ic_flicko_notification',
        largeIcon: const DrawableResourceAndroidBitmap(
          'ic_flicko_notification_large',
        ),
        color: const Color(0xFF149447),
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        audioAttributesUsage: AudioAttributesUsage.notification,
        enableVibration: true,
        vibrationPattern: _premiumReminderVibrationPattern,
        enableLights: false,
        ticker: 'Flicko health reminder',
        category: AndroidNotificationCategory.reminder,
        subText: 'Flicko AI Health Coach',
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: body,
        ),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        subtitle: 'Flicko AI Health Coach',
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        subtitle: 'Flicko AI Health Coach',
      ),
    );
  }

  tz.TZDateTime _safeScheduleTarget(
    DateTime scheduledAt, {
    required bool repeatsDaily,
  }) {
    final now = tz.TZDateTime.now(tz.local);
    var target = tz.TZDateTime.from(scheduledAt, tz.local);
    if (target.isAfter(now)) {
      return target;
    }
    if (!repeatsDaily) {
      return now.add(const Duration(minutes: 1));
    }
    target = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      target.hour,
      target.minute,
    );
    while (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target;
  }

  NotificationDetails _callInviteDetails({
    required String title,
    required String body,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _callInviteChannelId,
        'Flicko AI Call Invites',
        channelDescription:
            'Call-style Flicko AI health check-ins for missed meals, tasks, and daily routine follow-ups.',
        icon: 'ic_flicko_notification',
        largeIcon: const DrawableResourceAndroidBitmap(
          'ic_flicko_notification_large',
        ),
        color: const Color(0xFF149447),
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
        fullScreenIntent: true,
        autoCancel: false,
        ongoing: true,
        enableVibration: true,
        vibrationPattern: _premiumCallInviteVibrationPattern,
        enableLights: false,
        ticker: 'Incoming Flicko AI health call',
        subText: 'Flicko AI Health Coach',
        timeoutAfter: 90000,
        actions: const [
          AndroidNotificationAction(
            flickoCallAcceptActionId,
            'Pick up',
            showsUserInterface: true,
            cancelNotification: true,
            semanticAction: SemanticAction.call,
          ),
          AndroidNotificationAction(
            flickoCallDeclineActionId,
            'Decline',
            showsUserInterface: true,
            cancelNotification: true,
            semanticAction: SemanticAction.delete,
          ),
        ],
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'Pick up to continue in Flicko',
        ),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        subtitle: 'Incoming Flicko AI health call',
        categoryIdentifier: flickoCallInvitePayloadPrefix,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        subtitle: 'Incoming Flicko AI health call',
        categoryIdentifier: flickoCallInvitePayloadPrefix,
      ),
    );
  }

  int _notificationId(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = 0x1fffffff & (hash + unit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    return hash == 0 ? 1 : hash;
  }
}
