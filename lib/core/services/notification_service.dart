import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import '../navigation/notification_router.dart';

/// Callback ejecutado por Android cuando la notificación se toca
/// en un contexto background.
///
/// No se debe navegar aquí porque el Navigator de Flutter puede no estar listo.
/// La navegación real se maneja desde el callback normal o desde main.dart
/// usando initialNotificationResponse.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  /// Intencionalmente vacío.
}

/// Servicio centralizado para manejar notificaciones locales.
///
/// Responsabilidades:
/// - Inicializar flutter_local_notifications.
/// - Crear canales de notificación en Android.
/// - Solicitar permisos de notificación.
/// - Programar recordatorios diarios.
/// - Cancelar notificaciones.
/// - Guardar temporalmente la notificación que abrió la app desde estado cerrado.
class NotificationService {
  /// Instancia singleton del servicio.
  static final NotificationService _instance = NotificationService._internal();

  /// Constructor factory que retorna siempre la misma instancia.
  factory NotificationService() => _instance;

  /// Constructor privado usado por el singleton.
  NotificationService._internal();

  /// Plugin principal de notificaciones locales.
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// ID único del recordatorio diario.
  static const int _dailyNotificationId = 0;

  /// ID del canal Android para recordatorios diarios.
  static const String _dailyChannelId = 'daily_reminder_channel';

  /// Nombre visible del canal Android.
  static const String _dailyChannelName = 'Recordatorios Diarios';

  /// Descripción visible del canal Android.
  static const String _dailyChannelDescription =
      'Notificaciones para recordatorios diarios';

  /// Guarda la respuesta de la notificación cuando la app fue abierta
  /// desde estado cerrado o terminado.
  ///
  /// Esta variable se consume en main.dart después de que MaterialApp
  /// y navigatorKey ya están disponibles.
  static NotificationResponse? initialNotificationResponse;

  /// Inicializa el servicio de notificaciones.
  ///
  /// Acciones:
  /// - Verifica zona horaria local.
  /// - Configura icono Android.
  /// - Crea canales de notificación.
  /// - Detecta si la app fue abierta desde una notificación.
  /// - Registra callbacks para taps de notificación.
  Future<void> initialize() async {
    try {
      tz.TZDateTime.now(tz.local);
    } catch (_) {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('America/Lima'));
    }

    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_stat_notification',
    );

    const settings = InitializationSettings(
      android: androidSettings,
    );

    await _createNotificationChannels();

    final launchDetails = await _notifications.getNotificationAppLaunchDetails();

    if (launchDetails?.didNotificationLaunchApp ?? false) {
      initialNotificationResponse = launchDetails?.notificationResponse;
    }

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  }

  /// Maneja el toque de una notificación cuando la app está abierta,
  /// en segundo plano o aún vive en memoria.
  ///
  /// Aquí sí se puede solicitar navegación porque normalmente el contexto
  /// principal de Flutter ya existe.
  @pragma('vm:entry-point')
  static void _onNotificationTap(NotificationResponse response) {
    NotificationRouter.openTodayFromNotification();
  }

  /// Crea el canal de notificaciones requerido por Android.
  ///
  /// Android 8 o superior necesita canales para mostrar notificaciones.
  Future<void> _createNotificationChannels() async {
    const dailyChannel = AndroidNotificationChannel(
      _dailyChannelId,
      _dailyChannelName,
      description: _dailyChannelDescription,
      importance: Importance.high,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(dailyChannel);
  }

  /// Solicita permiso de notificaciones al usuario.
  ///
  /// Retorna true si el permiso fue concedido.
  Future<bool> requestPermissions() async {
    try {
      final status = await Permission.notification.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Verifica si el permiso de notificaciones está concedido.
  Future<bool> get arePermissionsGranted async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  /// Programa el recordatorio diario en la hora indicada.
  ///
  /// Antes de programar, cancela el recordatorio anterior para evitar duplicados.
  Future<void> scheduleDailyNotification({
    required int hour,
    required int minute,
  }) async {
    try {
      await cancelDailyNotification();

const title = '👷‍♂️ ¿Registraste tus trabajos de hoy?';
const body = '🗓️ No olvides guardar las actividades de tu jornada.';

      const androidDetails = AndroidNotificationDetails(
        _dailyChannelId,
        _dailyChannelName,
        channelDescription: _dailyChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_stat_notification',
      );

      const details = NotificationDetails(
        android: androidDetails,
      );

      await _notifications.zonedSchedule(
        _dailyNotificationId,
        title,
        body,
        _nextInstanceOfTime(hour, minute),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {}
  }

  /// Calcula la próxima fecha válida para ejecutar el recordatorio diario.
  ///
  /// Si la hora indicada ya pasó hoy, programa para mañana.
  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);

    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    return scheduledDate;
  }

  /// Cancela todas las notificaciones locales programadas.
  Future<void> cancelAllNotifications() async {
    try {
      await _notifications.cancelAll();
    } catch (_) {}
  }

  /// Cancela únicamente el recordatorio diario.
  Future<void> cancelDailyNotification() async {
    try {
      await _notifications.cancel(_dailyNotificationId);
    } catch (_) {}
  }
}