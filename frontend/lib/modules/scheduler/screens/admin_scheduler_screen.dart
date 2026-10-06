import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/format.dart';
import '../../../design/design.dart';
import '../data/scheduler_api.dart';
import '../widgets/plan_map.dart';

const _routePalette = <Color>[
  Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFFC62828), Color(0xFFE65100),
  Color(0xFF6A1B9A), Color(0xFF00695C), Color(0xFF4527A0), Color(0xFF558B2F),
  Color(0xFFAD1457), Color(0xFF0277BD), Color(0xFF37474F), Color(0xFF4E342E),
  Color(0xFF283593), Color(0xFF1B5E20), Color(0xFF78350F),
];

Color _routeColor(int index) => _routePalette[index % _routePalette.length];

/// Transport-office screen for the Go bus-scheduler service.
/// Four tabs: Dashboard (active plan + map), Buses, Stops, Students.
class AdminSchedulerScreen extends ConsumerWidget {
  const AdminSchedulerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          SignHeader(
            title: 'Route planner',
            subtitle: 'Bus scheduler service',
            bottom: TabBar(
              labelColor: TransitColors.white,
              unselectedLabelColor: TransitColors.white.withValues(alpha: 0.62),
              indicatorColor: TransitColors.led,
              dividerColor: Colors.transparent,
              labelStyle: TransitType.subheading.copyWith(fontWeight: FontWeight.w800),
              unselectedLabelStyle: TransitType.subheading,
              tabs: const [
                Tab(text: 'Dashboard'),
                Tab(text: 'Buses'),
                Tab(text: 'Stops'),
                Tab(text: 'Students'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _DashboardTab(),
                _BusesTab(),
                _StopsTab(),
                _StudentsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dashboard tab ────────────────────────────────────────────────────────────

enum _RunPhase { idle, planning, done, error }

class _DashboardTab extends ConsumerStatefulWidget {
  const _DashboardTab();

  @override
  ConsumerState<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends ConsumerState<_DashboardTab> {
  _RunPhase _phase = _RunPhase.idle;
  String? _error;

  Future<void> _runPlanner() async {
    final actions = ref.read(schedulerActionsProvider);
    final stops = ref.read(schedulerStopsProvider).asData?.value ?? [];
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RunPlannerSheet(
        stops: stops,
        onRun: (collegeStopId, departure, deadline, emptySeats) async {
          Navigator.pop(context);
          setState(() {
            _phase = _RunPhase.planning;
            _error = null;
          });
          try {
            final resultId = await actions.startPlanFromDb(
              collegeStopId: collegeStopId,
              earliestDeparture: departure,
              arrivalDeadline: deadline,
              desiredEmptySeats: emptySeats,
            );
            await _pollUntilDone(actions, resultId);
            ref.invalidate(activePlanProvider);
            if (mounted) setState(() => _phase = _RunPhase.done);
          } on ApiException catch (e) {
            if (mounted) setState(() {
              _phase = _RunPhase.error;
              _error = e.message;
            });
          }
        },
      ),
    );
  }

  Future<void> _pollUntilDone(SchedulerActions actions, String resultId) async {
    for (var i = 0; i < 300; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final check = await actions.checkPlan(resultId);
      // 200 response with data means completed; 202 with status=pending means still running.
      final status = check['status'] as String?;
      if (status != 'pending') return;
    }
    throw ApiException('Planning timed out after 15 minutes.');
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(activePlanProvider);
    final stopsAsync = ref.watch(schedulerStopsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(activePlanProvider);
        ref.invalidate(schedulerStopsProvider);
      },
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(Space.gutter),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Planning action + status
                Row(
                  children: [
                    Expanded(
                      child: _phase == _RunPhase.planning
                          ? Container(
                              padding: const EdgeInsets.all(Space.m),
                              decoration: BoxDecoration(
                                color: TransitColors.white,
                                borderRadius: Radii.signAll,
                                border: Border(
                                  left: BorderSide(
                                    color: TransitColors.led,
                                    width: 5,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: TransitColors.signBlue,
                                    ),
                                  ),
                                  const SizedBox(width: Space.m),
                                  Expanded(
                                    child: Text(
                                      'Planning in progress. Large datasets may take several minutes.',
                                      style: TransitType.body,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : SignButton(
                              label: 'Run planner',
                              icon: Icons.route,
                              kind: SignButtonKind.primary,
                              expand: true,
                              onPressed: _phase != _RunPhase.planning
                                  ? _runPlanner
                                  : null,
                            ),
                    ),
                  ],
                ),

                if (_error != null) ...[
                  const SizedBox(height: Space.m),
                  Container(
                    padding: const EdgeInsets.all(Space.m),
                    decoration: BoxDecoration(
                      color: TransitColors.white,
                      borderRadius: Radii.signAll,
                      border: const Border(
                        left: BorderSide(color: TransitColors.late, width: 5),
                      ),
                    ),
                    child: Text(_error!, style: TransitType.body.copyWith(color: TransitColors.late)),
                  ),
                ],

                const SizedBox(height: Space.xl),

                // Active plan content
                AsyncBody<ActivePlan?>(
                  value: planAsync,
                  onRetry: () => ref.invalidate(activePlanProvider),
                  builder: (plan) {
                    if (plan == null) {
                      return const SignNotice(
                        title: 'No active plan',
                        body: 'Run the planner to assign students to buses and generate a schedule.',
                      );
                    }
                    return _PlanContent(
                      plan: plan,
                      stopsAsync: stopsAsync,
                      onOpenMap: () => context.go('/admin/scheduler/map'),
                    );
                  },
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanContent extends StatelessWidget {
  const _PlanContent({
    required this.plan,
    required this.stopsAsync,
    required this.onOpenMap,
  });

  final ActivePlan plan;
  final AsyncValue<List<PlannerStop>> stopsAsync;
  final VoidCallback onOpenMap;

  String _rideTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final avgRide = plan.totalStudents > 0
        ? plan.summary.totalStudentRideSeconds ~/ plan.totalStudents
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary stats
        Container(
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(
            color: TransitColors.white,
            borderRadius: Radii.signAll,
            border: const Border(
              left: BorderSide(color: TransitColors.signBlue, width: 5),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final stats = [
                ('Buses used', '${plan.summary.busesUsed}'),
                ('Students', '${plan.totalStudents}'),
                ('Avg ride', _rideTime(avgRide)),
                ('Created', hm(plan.createdAt)),
              ];
              return c.maxWidth < 400
                  ? Column(
                      children: [
                        for (final s in stats)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: Space.xs),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(s.$1, style: TransitType.small.copyWith(color: TransitColors.inkSoft)),
                                Text(s.$2, style: TransitType.figure.copyWith(color: TransitColors.ink)),
                              ],
                            ),
                          ),
                      ],
                    )
                  : Row(
                      children: [
                        for (var i = 0; i < stats.length; i++) ...[
                          if (i > 0) ...[
                            const SizedBox(width: Space.m),
                            Container(width: 1, height: 32, color: TransitColors.rule),
                            const SizedBox(width: Space.m),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stats[i].$1,
                                  style: TransitType.small.copyWith(color: TransitColors.inkSoft),
                                ),
                                Text(stats[i].$2, style: TransitType.figure),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
            },
          ),
        ),

        const SizedBox(height: Space.m),

        // Map preview
        stopsAsync.when(
          data: (stops) => stops.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    PlanMap(plan: plan, stops: stops, height: 260),
                    const SizedBox(height: Space.s),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: onOpenMap,
                        icon: const Icon(Icons.open_in_full, size: 16),
                        label: const Text('Full-screen map'),
                        style: TextButton.styleFrom(
                          foregroundColor: TransitColors.signBlue,
                        ),
                      ),
                    ),
                  ],
                ),
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const SizedBox.shrink(),
        ),

        const SizedBox(height: Space.xl),

        Text('Bus routes', style: TransitType.heading),
        const SizedBox(height: Space.m),

        // Bus route list
        for (var i = 0; i < plan.buses.length; i++) ...[
          if (i > 0) const Divider(),
          _BusRouteRow(route: plan.buses[i], colorIndex: i),
        ],
      ],
    );
  }
}

class _BusRouteRow extends StatelessWidget {
  const _BusRouteRow({required this.route, required this.colorIndex});

  final PlanBusRoute route;
  final int colorIndex;

  String _duration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final color = _routeColor(colorIndex);
    final fillPct = route.capacity > 0
        ? route.studentCount / route.capacity
        : 0.0;
    final tone = fillPct >= 1.0
        ? Tone.late
        : fillPct >= 0.9
            ? Tone.caution
            : Tone.go;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: Radii.signAll,
            ),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  route.busId,
                  style: TransitType.subheading.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${route.stops.length} stops · ${_duration(route.totalTravelSeconds)}',
                  style: TransitType.small.copyWith(color: TransitColors.inkSoft),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${route.studentCount}/${route.capacity}',
                style: TransitType.figure.copyWith(color: TransitColors.ink),
              ),
              const SizedBox(height: 2),
              StatusPlate(
                '${route.studentCount}/${route.capacity} seats',
                tone: tone,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Run planner sheet ────────────────────────────────────────────────────────

class _RunPlannerSheet extends StatefulWidget {
  const _RunPlannerSheet({required this.stops, required this.onRun});

  final List<PlannerStop> stops;
  final Future<void> Function(
    String? collegeStopId,
    DateTime? departure,
    DateTime? deadline,
    int emptySeats,
  ) onRun;

  @override
  State<_RunPlannerSheet> createState() => _RunPlannerSheetState();
}

class _RunPlannerSheetState extends State<_RunPlannerSheet> {
  String? _collegeStopId;
  final _depCtrl = TextEditingController(text: '06:30');
  final _arrCtrl = TextEditingController(text: '08:45');
  int _emptySeats = 0;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _depCtrl.dispose();
    _arrCtrl.dispose();
    super.dispose();
  }

  DateTime? _parseTime(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, h, m);
  }

  Future<void> _submit() async {
    final departure = _parseTime(_depCtrl.text);
    final deadline = _parseTime(_arrCtrl.text);
    if (departure == null || deadline == null) {
      setState(() => _error = 'Enter times as HH:MM, e.g. 06:30.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await widget.onRun(_collegeStopId, departure, deadline, _emptySeats);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.gutter,
        Space.xl,
        Space.gutter,
        MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Run planner', style: TransitType.title),
          const SizedBox(height: 4),
          Text(
            'Uses all buses and students already in the database.',
            style: TransitType.body.copyWith(color: TransitColors.inkSoft),
          ),
          const SizedBox(height: Space.xl),

          if (widget.stops.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              value: _collegeStopId,
              decoration: const InputDecoration(labelText: 'College stop (optional — auto-detected if blank)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Auto-detect')),
                for (final s in widget.stops)
                  DropdownMenuItem(value: s.stopId, child: Text('${s.name} (${s.stopId})')),
              ],
              onChanged: (v) => setState(() => _collegeStopId = v),
            ),
            const SizedBox(height: Space.m),
          ],

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _depCtrl,
                  decoration: const InputDecoration(labelText: 'Earliest departure (HH:MM)'),
                  keyboardType: TextInputType.datetime,
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: TextField(
                  controller: _arrCtrl,
                  decoration: const InputDecoration(labelText: 'Arrival deadline (HH:MM)'),
                  keyboardType: TextInputType.datetime,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.m),

          Row(
            children: [
              Text('Empty seats buffer: $_emptySeats', style: TransitType.body),
              Expanded(
                child: Slider(
                  value: _emptySeats.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  activeColor: TransitColors.signBlue,
                  label: '$_emptySeats',
                  onChanged: (v) => setState(() => _emptySeats = v.round()),
                ),
              ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: Space.s),
            Text(_error!, style: TransitType.body.copyWith(color: TransitColors.late)),
          ],

          const SizedBox(height: Space.l),
          SignButton(
            label: 'Run planner',
            icon: Icons.route,
            expand: true,
            busy: _busy,
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}

// ─── Buses tab ────────────────────────────────────────────────────────────────

class _BusesTab extends ConsumerWidget {
  const _BusesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buses = ref.watch(schedulerBusesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.gutter, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  buses.asData?.value.isEmpty == true
                      ? 'No buses'
                      : buses.asData == null
                          ? ''
                          : '${buses.asData!.value.length} buses',
                  style: TransitType.subheading.copyWith(color: TransitColors.inkSoft),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Import CSV'),
                onPressed: () => _showCsvSheet(
                  context,
                  ref,
                  label: 'Paste buses CSV',
                  hint: 'bus_id,capacity\nBUS-1,24\nBUS-2,12',
                  onImport: (csv) async {
                    await ref.read(schedulerActionsProvider).addBusesFromCsv(csv);
                    ref.invalidate(schedulerBusesProvider);
                  },
                ),
              ),
              SignButton(
                label: 'Add bus',
                icon: Icons.add,
                kind: SignButtonKind.onDark,
                height: 40,
                onPressed: () async {
                  if (await showDialog<bool>(
                        context: context,
                        builder: (_) => const _AddBusDialog(),
                      ) ==
                      true) {
                    ref.invalidate(schedulerBusesProvider);
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncBody(
            value: buses,
            onRetry: () => ref.invalidate(schedulerBusesProvider),
            builder: (list) => list.isEmpty
                ? const SignNotice(
                    title: 'No buses yet',
                    body: 'Add buses with their ID and seat capacity, or import from CSV.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(Space.gutter),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) => _BusRow(bus: list[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _BusRow extends ConsumerWidget {
  const _BusRow({required this.bus});

  final PlannerBus bus;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.s),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(bus.id, style: TransitType.subheading.copyWith(fontWeight: FontWeight.w800)),
              Text('${bus.capacity} seats', style: TransitType.small.copyWith(color: TransitColors.inkSoft)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Remove bus',
          icon: const Icon(Icons.delete_outline, color: TransitColors.late),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: Text('Remove ${bus.id}?', style: TransitType.heading),
                content: const Text('This bus will be removed from the scheduler database.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  SignButton(
                    label: 'Remove',
                    kind: SignButtonKind.danger,
                    height: 44,
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            );
            if (ok == true) {
              try {
                await ref.read(schedulerActionsProvider).deleteBus(bus.id);
                ref.invalidate(schedulerBusesProvider);
              } on ApiException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            }
          },
        ),
      ],
    ),
  );
}

class _AddBusDialog extends ConsumerStatefulWidget {
  const _AddBusDialog();

  @override
  ConsumerState<_AddBusDialog> createState() => _AddBusDialogState();
}

class _AddBusDialogState extends ConsumerState<_AddBusDialog> {
  final _id = TextEditingController();
  final _cap = TextEditingController(text: '40');
  String? _error;
  bool _busy = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add bus', style: TransitType.heading),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _id,
            decoration: const InputDecoration(labelText: 'Bus ID, e.g. BUS-001'),
          ),
          const SizedBox(height: Space.m),
          TextField(
            controller: _cap,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Seats'),
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.m),
            Text(_error!, style: TransitType.body.copyWith(color: TransitColors.late)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      SignButton(
        label: 'Add',
        height: 44,
        busy: _busy,
        onPressed: _busy ? null : () async {
          final id = _id.text.trim();
          final cap = int.tryParse(_cap.text.trim()) ?? 0;
          if (id.isEmpty) {
            setState(() => _error = 'Bus ID is required.');
            return;
          }
          setState(() { _busy = true; _error = null; });
          try {
            await ref.read(schedulerActionsProvider).addBus(id, cap);
            if (mounted) Navigator.pop(context, true);
          } on ApiException catch (e) {
            setState(() { _busy = false; _error = e.message; });
          }
        },
      ),
    ],
  );
}

// ─── Stops tab ────────────────────────────────────────────────────────────────

class _StopsTab extends ConsumerWidget {
  const _StopsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stops = ref.watch(schedulerStopsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.gutter, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  stops.asData?.value.isEmpty == true
                      ? 'No stops'
                      : stops.asData == null
                          ? ''
                          : '${stops.asData!.value.length} stops',
                  style: TransitType.subheading.copyWith(color: TransitColors.inkSoft),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Import CSV'),
                onPressed: () => _showCsvSheet(
                  context,
                  ref,
                  label: 'Paste stops CSV',
                  hint: 'stop_id,name,latitude,longitude\nst1,Central,13.01,80.22',
                  onImport: (csv) async {
                    await ref.read(schedulerActionsProvider).addStopsFromCsv(csv);
                    ref.invalidate(schedulerStopsProvider);
                  },
                ),
              ),
              SignButton(
                label: 'Add stop',
                icon: Icons.add,
                kind: SignButtonKind.onDark,
                height: 40,
                onPressed: () async {
                  if (await showDialog<bool>(
                        context: context,
                        builder: (_) => const _AddStopDialog(),
                      ) ==
                      true) {
                    ref.invalidate(schedulerStopsProvider);
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncBody(
            value: stops,
            onRetry: () => ref.invalidate(schedulerStopsProvider),
            builder: (list) => list.isEmpty
                ? const SignNotice(
                    title: 'No stops yet',
                    body: 'Add stops with coordinates for the planner to use, or import from CSV.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(Space.gutter),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) => _StopRow(stop: list[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _StopRow extends ConsumerWidget {
  const _StopRow({required this.stop});

  final PlannerStop stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.s),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(stop.name, style: TransitType.subheading.copyWith(fontWeight: FontWeight.w800)),
              Text(
                '${stop.stopId} · ${stop.latitude.toStringAsFixed(4)}, ${stop.longitude.toStringAsFixed(4)}',
                style: TransitType.small.copyWith(color: TransitColors.inkSoft),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Remove stop',
          icon: const Icon(Icons.delete_outline, color: TransitColors.late),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: Text('Remove ${stop.name}?', style: TransitType.heading),
                content: const Text('This stop will be removed from the scheduler database.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  SignButton(
                    label: 'Remove',
                    kind: SignButtonKind.danger,
                    height: 44,
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            );
            if (ok == true) {
              try {
                await ref.read(schedulerActionsProvider).deleteStop(stop.stopId);
                ref.invalidate(schedulerStopsProvider);
              } on ApiException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            }
          },
        ),
      ],
    ),
  );
}

class _AddStopDialog extends ConsumerStatefulWidget {
  const _AddStopDialog();

  @override
  ConsumerState<_AddStopDialog> createState() => _AddStopDialogState();
}

class _AddStopDialogState extends ConsumerState<_AddStopDialog> {
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _lat = TextEditingController();
  final _lon = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add stop', style: TransitType.heading),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _id,
            decoration: const InputDecoration(labelText: 'Stop ID, e.g. st42'),
          ),
          const SizedBox(height: Space.m),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: Space.m),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lat,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Latitude'),
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: TextField(
                  controller: _lon,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Longitude'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.m),
            Text(_error!, style: TransitType.body.copyWith(color: TransitColors.late)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      SignButton(
        label: 'Add',
        height: 44,
        busy: _busy,
        onPressed: _busy ? null : () async {
          final id = _id.text.trim();
          final name = _name.text.trim();
          final lat = double.tryParse(_lat.text.trim());
          final lon = double.tryParse(_lon.text.trim());
          if (id.isEmpty || lat == null || lon == null) {
            setState(() => _error = 'Stop ID, latitude and longitude are required.');
            return;
          }
          setState(() { _busy = true; _error = null; });
          try {
            await ref.read(schedulerActionsProvider).addStop(
              stopId: id,
              name: name.isEmpty ? id : name,
              latitude: lat,
              longitude: lon,
            );
            if (mounted) Navigator.pop(context, true);
          } on ApiException catch (e) {
            setState(() { _busy = false; _error = e.message; });
          }
        },
      ),
    ],
  );
}

// ─── Students tab ─────────────────────────────────────────────────────────────

class _StudentsTab extends ConsumerWidget {
  const _StudentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final students = ref.watch(schedulerStudentsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.gutter, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  students.asData?.value.isEmpty == true
                      ? 'No students'
                      : students.asData == null
                          ? ''
                          : '${students.asData!.value.length} students',
                  style: TransitType.subheading.copyWith(color: TransitColors.inkSoft),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Import CSV'),
                onPressed: () => _showCsvSheet(
                  context,
                  ref,
                  label: 'Paste students CSV',
                  hint: 'student_id,stop_id\nS001,st1\nS002,st3',
                  onImport: (csv) async {
                    await ref.read(schedulerActionsProvider).addStudentsFromCsv(csv);
                    ref.invalidate(schedulerStudentsProvider);
                  },
                ),
              ),
              SignButton(
                label: 'Add student',
                icon: Icons.add,
                kind: SignButtonKind.onDark,
                height: 40,
                onPressed: () async {
                  final stops = ref.read(schedulerStopsProvider).asData?.value ?? [];
                  if (await showDialog<bool>(
                        context: context,
                        builder: (_) => _AddStudentDialog(stops: stops),
                      ) ==
                      true) {
                    ref.invalidate(schedulerStudentsProvider);
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncBody(
            value: students,
            onRetry: () => ref.invalidate(schedulerStudentsProvider),
            builder: (list) => list.isEmpty
                ? const SignNotice(
                    title: 'No students yet',
                    body: 'Add students with their assigned pickup stop, or import from CSV.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(Space.gutter),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) => _StudentRow(student: list[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _StudentRow extends ConsumerWidget {
  const _StudentRow({required this.student});

  final PlannerStudent student;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.s),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                student.id,
                style: TransitType.subheading.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                'Stop: ${student.stopId}',
                style: TransitType.small.copyWith(color: TransitColors.inkSoft),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Remove student',
          icon: const Icon(Icons.delete_outline, color: TransitColors.late),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: Text('Remove ${student.id}?', style: TransitType.heading),
                content: const Text('This student will be removed from the scheduler database.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  SignButton(
                    label: 'Remove',
                    kind: SignButtonKind.danger,
                    height: 44,
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            );
            if (ok == true) {
              try {
                await ref.read(schedulerActionsProvider).deleteStudent(student.id);
                ref.invalidate(schedulerStudentsProvider);
              } on ApiException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            }
          },
        ),
      ],
    ),
  );
}

class _AddStudentDialog extends ConsumerStatefulWidget {
  const _AddStudentDialog({required this.stops});

  final List<PlannerStop> stops;

  @override
  ConsumerState<_AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends ConsumerState<_AddStudentDialog> {
  final _id = TextEditingController();
  String? _stopId;
  final _stopIdCtrl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add student', style: TransitType.heading),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _id,
            decoration: const InputDecoration(labelText: 'Student ID, e.g. S001'),
          ),
          const SizedBox(height: Space.m),
          if (widget.stops.isNotEmpty)
            DropdownButtonFormField<String>(
              value: _stopId,
              decoration: const InputDecoration(labelText: 'Pickup stop'),
              items: [
                for (final s in widget.stops)
                  DropdownMenuItem(
                    value: s.stopId,
                    child: Text('${s.name} (${s.stopId})'),
                  ),
              ],
              onChanged: (v) => setState(() => _stopId = v),
            )
          else
            TextField(
              controller: _stopIdCtrl,
              decoration: const InputDecoration(labelText: 'Stop ID'),
            ),
          if (_error != null) ...[
            const SizedBox(height: Space.m),
            Text(_error!, style: TransitType.body.copyWith(color: TransitColors.late)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      SignButton(
        label: 'Add',
        height: 44,
        busy: _busy,
        onPressed: _busy ? null : () async {
          final id = _id.text.trim();
          final stopId = _stopId ?? _stopIdCtrl.text.trim();
          if (id.isEmpty || stopId.isEmpty) {
            setState(() => _error = 'Student ID and stop are required.');
            return;
          }
          setState(() { _busy = true; _error = null; });
          try {
            await ref.read(schedulerActionsProvider).addStudent(id, stopId);
            if (mounted) Navigator.pop(context, true);
          } on ApiException catch (e) {
            setState(() { _busy = false; _error = e.message; });
          }
        },
      ),
    ],
  );
}

// ─── Shared CSV import sheet ──────────────────────────────────────────────────

Future<void> _showCsvSheet(
  BuildContext context,
  WidgetRef ref, {
  required String label,
  required String hint,
  required Future<void> Function(String csv) onImport,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CsvSheet(label: label, hint: hint, onImport: onImport),
  );
}

class _CsvSheet extends StatefulWidget {
  const _CsvSheet({required this.label, required this.hint, required this.onImport});

  final String label;
  final String hint;
  final Future<void> Function(String csv) onImport;

  @override
  State<_CsvSheet> createState() => _CsvSheetState();
}

class _CsvSheetState extends State<_CsvSheet> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _success;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      Space.gutter,
      Space.xl,
      Space.gutter,
      MediaQuery.viewInsetsOf(context).bottom + Space.xl,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: TransitType.title),
        const SizedBox(height: 4),
        Text(
          'Paste CSV content below. The header row is optional.',
          style: TransitType.body.copyWith(color: TransitColors.inkSoft),
        ),
        const SizedBox(height: Space.m),
        Container(
          decoration: BoxDecoration(
            color: TransitColors.enamelDeep,
            borderRadius: Radii.signAll,
          ),
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
          child: Text(widget.hint, style: TransitType.small.copyWith(color: TransitColors.inkSoft)),
        ),
        const SizedBox(height: Space.m),
        TextField(
          controller: _ctrl,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'CSV content',
            alignLabelWithHint: true,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: Space.s),
          Text(_error!, style: TransitType.body.copyWith(color: TransitColors.late)),
        ],
        if (_success != null) ...[
          const SizedBox(height: Space.s),
          Text(_success!, style: TransitType.body.copyWith(color: TransitColors.go)),
        ],
        const SizedBox(height: Space.l),
        SignButton(
          label: 'Import',
          icon: Icons.upload,
          expand: true,
          busy: _busy,
          onPressed: _busy ? null : () async {
            final csv = _ctrl.text.trim();
            if (csv.isEmpty) {
              setState(() => _error = 'Paste some CSV content first.');
              return;
            }
            setState(() { _busy = true; _error = null; _success = null; });
            try {
              await widget.onImport(csv);
              if (mounted) {
                setState(() { _busy = false; _success = 'Imported successfully.'; });
              }
            } on ApiException catch (e) {
              setState(() { _busy = false; _error = e.message; });
            }
          },
        ),
      ],
    ),
  );
}
