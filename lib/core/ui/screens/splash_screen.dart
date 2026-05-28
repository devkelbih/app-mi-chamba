import 'package:flutter/material.dart';
import 'package:mi_semana/core/navigation/notification_router.dart';
import 'package:mi_semana/core/services/notification_service.dart';
import 'package:mi_semana/core/startup/app_initializer.dart';

import 'package:mi_semana/core/startup/app_startup_manager.dart';
import 'package:mi_semana/core/startup/startup_result.dart';
import 'package:mi_semana/core/ui/screens/notification_intro_screen.dart';

import 'package:mi_semana/features/work/presentation/screens/calendar_screen.dart';
import 'package:mi_semana/features/work/presentation/viewmodels/calendar_viewmodel.dart';
import 'package:mi_semana/features/work/presentation/viewmodels/catalog_work_viewmodel.dart';
import 'package:mi_semana/features/work/presentation/viewmodels/weekly_summary_viewmodel.dart';
import 'package:provider/provider.dart';

// -----------------------------------------------------------------------------
// SPLASH SCREEN
// -----------------------------------------------------------------------------
// Esta pantalla se encarga de:
// 1. Inicializar el estado global de la app
// 2. Decidir a dónde navegar (intro o home)
// 3. Evitar bloqueos si algo falla
// -----------------------------------------------------------------------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _startupManager = AppStartupManager();

  // Evita ejecuciones múltiples accidentales
  bool _initialized = false;

  @override
  void initState() {
    super.initState();

    // Ejecutar después del primer frame (context ya disponible)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startApp();
    });
  }

  Future<void> _startApp() async {
    // Protección contra múltiples llamadas
    if (_initialized) return;
    _initialized = true;

    // Obtener dependencias ANTES de cualquier await
    final catalogVM = context.read<CatalogWorkViewmodel>();
    final calendarVM = context.read<CalendarViewModel>();
    final summaryVM = context.read<WeeklySummaryViewmodel>();

    final initializer = AppInitializer(
      catalogVM: catalogVM,
      calendarVM: calendarVM,
      summaryVM: summaryVM,
    );

    try {
      // Inicialización principal de la app
      await initializer.initialize();
      final notificationResponse =
          NotificationService.initialNotificationResponse;

      if (notificationResponse != null) {
        NotificationService.initialNotificationResponse = null;

        if (!mounted) return;

        NotificationRouter.openTodayFromNotification();
        return;
      }
      // Determinar flujo de navegación (intro o home)
      final result = await _startupManager.determineStartupRoute();

      // Pequeño delay para UX (suavidad visual)
      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;

      // Navegación final
      switch (result) {
        case StartupResult.showNotificationIntro:
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const NotificationIntroScreen()),
          );
          break;

        case StartupResult.goToHome:
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const CalendarScreen()),
          );
          break;
      }
    } catch (e) {
      // Manejo de error global
      debugPrint("Error en inicialización: $e");

      // IMPORTANTE:
      // Evitamos que la app se quede bloqueada en Splash
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CalendarScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: primaryColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // -----------------------------------------------------------------
            // LOGO + TÍTULO
            // -----------------------------------------------------------------
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/app_icon.png',
                  width: 100,
                  height: 100,
                ),
                const SizedBox(width: 20),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mi Chamba',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Registro y Recordatorios',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 80),

            // -----------------------------------------------------------------
            // LOADING INDICATOR
            // -----------------------------------------------------------------
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
