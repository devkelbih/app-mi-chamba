import 'package:flutter/material.dart';
import 'package:mi_semana/core/services/notification_service.dart';
import 'package:mi_semana/core/state/base_vm_state_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';

class SettingsViewModel extends BaseVmStateManager {
  /// STORAGE KEYS
  static const String _notificationsEnabledKey = 'notifications_enabled';
  static const String _dailyRemindersKey = 'daily_reminders';
  static const String _dailyHourKey = 'daily_hour';
  static const String _dailyMinuteKey = 'daily_minute';

  /// DEFAULT VALUES
  static const int _defaultDailyHour = 20;
  static const int _defaultDailyMinute = 0;

  /// INTERNAL STATE
  bool _notificationsEnabled = false;
  bool _dailyReminders = true;

  int _dailyHour = _defaultDailyHour;
  int _dailyMinute = _defaultDailyMinute;

  bool _notificationServiceInitialized = false;

  final NotificationService _notificationService;

  /// GETTERS

  bool get notificationsEnabled => _notificationsEnabled;

  bool get dailyReminders => _dailyReminders;

  TimeOfDay get dailyReminderTime =>
      TimeOfDay(hour: _dailyHour, minute: _dailyMinute);

  String get dailyReminderFormatted {
    final h = _dailyHour.toString().padLeft(2, '0');
    final m = _dailyMinute.toString().padLeft(2, '0');
    return "$h:$m";
  }

  /// CONSTRUCTOR

  SettingsViewModel(this._notificationService) {
    _initialize();
  }

  /// INITIALIZATION

  Future<void> _initialize() async {
    await _initializeNotificationServiceIfNeeded();
    await _loadPreferences();
    await syncWithSystemPermissions();

    /// Si todo está activo restauramos la notificación
    if (_notificationsEnabled && _dailyReminders) {
      await _notificationService.scheduleDailyNotification(
        hour: _dailyHour,
        minute: _dailyMinute,
      );
    }

    notifyListeners();
  }

  Future<void> _initializeNotificationServiceIfNeeded() async {
    if (_notificationServiceInitialized) return;
    _notificationServiceInitialized = true;
  }

  /// PREFERENCES

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    _notificationsEnabled = prefs.getBool(_notificationsEnabledKey) ?? false;

    _dailyReminders = prefs.getBool(_dailyRemindersKey) ?? true;

    _dailyHour = prefs.getInt(_dailyHourKey) ?? _defaultDailyHour;

    _dailyMinute = prefs.getInt(_dailyMinuteKey) ?? _defaultDailyMinute;

    /// guardamos defaults si no existen
    if (!prefs.containsKey(_dailyHourKey)) {
      await prefs.setInt(_dailyHourKey, _dailyHour);
    }

    if (!prefs.containsKey(_dailyMinuteKey)) {
      await prefs.setInt(_dailyMinuteKey, _dailyMinute);
    }
  }

  Future<void> _savePreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  /// PERMISSIONS

  Future<bool> requestNotificationPermission() async {
    try {
      await _initializeNotificationServiceIfNeeded();
      return await _notificationService.requestPermissions();
    } catch (_) {
      return false;
    }
  }

  /// ENABLE / DISABLE NOTIFICATIONS

  Future<void> setNotificationsEnabled(bool value) async {
    await _initializeNotificationServiceIfNeeded();

    try {
      if (value) {
        await _enableNotifications();
      } else {
        await _disableNotifications();
      }

      notifyListeners();
    } catch (_) {
      emitMessage(
        "Error al cambiar configuración de notificaciones",
        success: false,
      );
      notifyListeners();
    }
  }

  Future<void> _enableNotifications() async {
    final status = await Permission.notification.status;

    if (status.isGranted) {
      _notificationsEnabled = true;

      await _savePreference(_notificationsEnabledKey, true);

      /// restauramos recordatorio si estaba activo
      if (_dailyReminders) {
        await _notificationService.scheduleDailyNotification(
          hour: _dailyHour,
          minute: _dailyMinute,
        );
      }

      emitMessage("Notificaciones activadas correctamente", success: true);
      return;
    }

    if (status.isPermanentlyDenied) {
      emitMessage("Redirigiendo a configuración del sistema", success: true);
      await _openNotificationSettings();
      return;
    }

    final granted = await _notificationService.requestPermissions();

    if (granted) {
      _notificationsEnabled = true;

      await _savePreference(_notificationsEnabledKey, true);

      if (_dailyReminders) {
        await _notificationService.scheduleDailyNotification(
          hour: _dailyHour,
          minute: _dailyMinute,
        );
      }

      emitMessage("Notificaciones activadas correctamente", success: true);
    } else {
      emitMessage("Permisos de notificación denegados", success: false);
    }
  }

  Future<void> _disableNotifications() async {
    _notificationsEnabled = false;

    await _savePreference(_notificationsEnabledKey, false);

    await _notificationService.cancelDailyNotification();

    emitMessage("Notificaciones desactivadas", success: true);
  }

  /// SYSTEM SYNC

  Future<void> syncWithSystemPermissions() async {
    try {
      final status = await Permission.notification.status;

      if (!status.isGranted && _notificationsEnabled) {
        _notificationsEnabled = false;

        await _savePreference(_notificationsEnabledKey, false);

        await _notificationService.cancelDailyNotification();

        emitMessage(
          "Notificaciones desactivadas desde ajustes del sistema",
          success: true,
        );

        notifyListeners();
      }
    } catch (_) {}
  }

  /// DAILY REMINDERS

  Future<void> setDailyReminders(bool value) async {
    if (!_notificationsEnabled) return;

    try {
      _dailyReminders = value;

      await _savePreference(_dailyRemindersKey, value);

      if (value) {
        await _notificationService.scheduleDailyNotification(
          hour: _dailyHour,
          minute: _dailyMinute,
        );
      } else {
        await _notificationService.cancelDailyNotification();
      }

      emitMessage(
        value
            ? "Recordatorios diarios activados"
            : "Recordatorios diarios desactivados",
        success: true,
      );

      notifyListeners();
    } catch (_) {
      emitMessage("Error al configurar recordatorios diarios", success: false);
      notifyListeners();
    }
  }

  /// CHANGE TIME

  Future<void> setDailyReminderTime(TimeOfDay time) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _dailyHour = time.hour;
      _dailyMinute = time.minute;

      await prefs.setInt(_dailyHourKey, _dailyHour);
      await prefs.setInt(_dailyMinuteKey, _dailyMinute);

      /// reprogramamos si está activo
      if (_notificationsEnabled && _dailyReminders) {
        await _notificationService.scheduleDailyNotification(
          hour: _dailyHour,
          minute: _dailyMinute,
        );
      }

      emitMessage("Hora del recordatorio actualizada", success: true);

      notifyListeners();
    } catch (_) {
      emitMessage("Error al actualizar la hora", success: false);
    }
  }

  /// OPEN SYSTEM SETTINGS

  Future<void> _openNotificationSettings() async {
    try {
      emitMessage(
        "Activa 'Permitir notificaciones' y regresa a la aplicación",
        success: false,
      );

      await AppSettings.openAppSettings();
    } catch (_) {
      emitMessage(
        "Error al abrir configuración. Activa manualmente en Ajustes > Apps > Mi Semana > Notificaciones",
        success: false,
      );
    }
  }
}
