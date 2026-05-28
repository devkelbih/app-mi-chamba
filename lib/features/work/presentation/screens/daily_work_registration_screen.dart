import 'package:flutter/material.dart';
import 'package:mi_semana/core/state/flag_listenable.dart';
import 'package:mi_semana/core/ui/toast/app_toast.dart';
import 'package:mi_semana/core/ui/widgets/blocking_loading_overlay.dart';
import 'package:mi_semana/core/ui/widgets/confirm_delete_dialog.dart';
import 'package:mi_semana/features/work/domain/entities/constants/months_constants.dart';
import 'package:mi_semana/features/work/domain/entities/constants/work_constants.dart';
import 'package:mi_semana/features/work/domain/entities/trabajo_catalogo.dart';
import 'package:mi_semana/features/work/domain/entities/trabajo_dia_detalle.dart';
import 'package:mi_semana/features/work/presentation/screens/catalog_form_work_screen.dart';
import 'package:mi_semana/features/work/presentation/viewmodels/catalog_work_viewmodel.dart';
import 'package:mi_semana/features/work/presentation/viewmodels/daily_work_registration_viewmodel.dart';
import 'package:mi_semana/features/work/presentation/widgets/select_work_modal_widget.dart';
import 'package:provider/provider.dart';

class DailyWorkRegistrationScreen extends StatefulWidget {
  final DateTime selectedDay;

  const DailyWorkRegistrationScreen({super.key, required this.selectedDay});

  @override
  State<DailyWorkRegistrationScreen> createState() =>
      _DailyWorkRegistrationScreenState();
}

class _DailyWorkRegistrationScreenState
    extends State<DailyWorkRegistrationScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final catalogVM = context.read<CatalogWorkViewmodel>();
      if (catalogVM.trabajos.isEmpty) {
        catalogVM.cargarTrabajos();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final dailyVM = context.watch<DailyWorkRegistrationViewmodel>();
    final uiMessage = dailyVM.uiMessage;

    if (uiMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        AppToast.show(
          context,
          message: uiMessage.text,
          isSuccess: uiMessage.success,
        );

        dailyVM.clearUiMessage();
      });
    }
  }

  void _mostrarModalAgregarTrabajo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SelectWorkModalWidget(
        onWorkSelected: _agregarTrabajoAlDia,
        onAddNewWork: _navegarAAgregarTrabajo,
      ),
    );
  }

  Future<void> _navegarAAgregarTrabajo() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const CatalogFormWorkScreen(), // Sin trabajo = modo creación
      ),
    );

    if (result == true && mounted) {
      final catalogVM = context.read<CatalogWorkViewmodel>();
      await catalogVM.cargarTrabajos();
      _mostrarModalAgregarTrabajo();
    }
  }

  void _agregarTrabajoAlDia(Trabajo trabajo) {
    final dailyVM = context.read<DailyWorkRegistrationViewmodel>();

    final existing = dailyVM.detalles
        .where((d) => d.trabajoId == trabajo.id)
        .firstOrNull;

    if (existing != null) {
      dailyVM.actualizarDetalle(
        trabajo.id!,
        existing.copyWith(cantidad: existing.cantidad + 1),
      );
    } else {
      dailyVM.agregarDetalle(
        TrabajoDiaDetalle(
          trabajoId: trabajo.id!,
          cantidad: 1,
          pago: trabajo.pagoPredeterminado,
        ),
        widget.selectedDay,
      );
    }
  }

  Future<void> _guardarDia() async {
    final dailyVM = context.read<DailyWorkRegistrationViewmodel>();
    final saved = await dailyVM.guardarTrabajoDia();

    if (!mounted) return;
    if (saved) Navigator.pop(context, true);
  }

  void _confirmarEliminarDia() {
    final viewModel = context.read<DailyWorkRegistrationViewmodel>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return FlagListenableBuilder(
          notifier: viewModel,
          selector: (vm) => vm.isDeleting,
          builder: (isDeleting) {
            return ConfirmDeleteDialog(
              itemName: "todo el registro del día",
              isLoading: isDeleting,
              onConfirm: () async {
                final eliminado = await viewModel.eliminarTodosLosTrabajos();

                if (!dialogContext.mounted) return;

                Navigator.pop(dialogContext); // cerrar dialog

                if (eliminado && mounted) {
                  Navigator.pop(context, true); // cerrar screen
                }
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dailyVM = context.watch<DailyWorkRegistrationViewmodel>();
    final detalles = dailyVM.detalles;

    final total = detalles.fold(0.0, (t, d) => t + (d.cantidad * d.pago));
    final existeRegistroDia = dailyVM.trabajoDiaActual?.id != null;
    final hayCambiosPuedeGuardar = dailyVM.puedeGuardar;
    //loading
    if (dailyVM.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    /// loading crítico (guardar / eliminar)
    final isBlocking = dailyVM.isSaving || dailyVM.isDeleting;
    return BlockingLoadingOverlay(
      isBlocking: isBlocking,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Registro - ${MonthsConstants.formatFullDateWithDay(widget.selectedDay)}',
          ),
          centerTitle: true,
          actions: [
            if (existeRegistroDia)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _confirmarEliminarDia,
              ),
          ],
        ),
        body: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Trabajos que realizaste hoy',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Expanded(
              child: detalles.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.work_outline, size: 48, color: Colors.red),
                          SizedBox(height: 16),
                          Text('Aún no registraste ninguna actividad.'),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: detalles.length,
                      itemBuilder: (_, i) => _buildTrabajoItem(detalles[i]),
                    ),
            ),
            _buildResumen(total, hayCambiosPuedeGuardar),
          ],
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 120),
          child: FloatingActionButton.extended(
            onPressed: _mostrarModalAgregarTrabajo,
            icon: const Icon(Icons.add),
            label: const Text("Agregar"),
          ),
        ),
      ),
    );
  }

  Widget _buildTrabajoItem(TrabajoDiaDetalle detalle) {
    final catalogVM = context.read<CatalogWorkViewmodel>();

    final trabajo = catalogVM.trabajos.firstWhere(
      (t) => t.id == detalle.trabajoId,
      orElse: () => Trabajo(
        id: detalle.trabajoId,
        nombre: 'Trabajo',
        pagoPredeterminado: detalle.pago,
        color: 1,
        icono: 1,
      ),
    );

    final subtotal = detalle.cantidad * detalle.pago;

    final color =
        WorkConstants.coloresMap[trabajo.color]?['color'] as Color? ??
        Colors.grey;
    final icon =
        WorkConstants.iconosMap[trabajo.icono]?['icono'] as IconData? ??
        Icons.work;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha(50),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withAlpha(100),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trabajo.nombre,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'x${detalle.cantidad} - S/. ${detalle.pago.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            ),
          ),
          Text(
            'S/. ${subtotal.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.green,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () {
              context.read<DailyWorkRegistrationViewmodel>().eliminarDetalle(
                detalle.trabajoId,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildResumen(double total, bool enabled) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Monto a cobrar hoy:',
                  style: TextStyle(fontSize: 18),
                ),
                Text(
                  'S/. ${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: enabled ? _guardarDia : null,
                child: const Text(
                  'GUARDAR DÍA',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
