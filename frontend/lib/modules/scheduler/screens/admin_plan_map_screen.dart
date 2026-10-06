import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../data/scheduler_api.dart';
import '../widgets/plan_map.dart';

/// Full-screen view of the active route plan on an OSM map.
/// Opened from the dashboard tab's "Full-screen map" link.
class AdminPlanMapScreen extends ConsumerWidget {
  const AdminPlanMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(activePlanProvider);
    final stopsAsync = ref.watch(schedulerStopsProvider);

    return Column(
      children: [
        SignHeader(
          title: 'Plan map',
          subtitle: 'All bus routes and pickup stops',
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back, color: TransitColors.white),
            onPressed: () => context.go('/admin/scheduler'),
          ),
        ),
        Expanded(
          child: AsyncBody<ActivePlan?>(
            value: planAsync,
            onRetry: () {
              ref.invalidate(activePlanProvider);
              ref.invalidate(schedulerStopsProvider);
            },
            builder: (plan) {
              if (plan == null) {
                return const SignNotice(
                  title: 'No active plan',
                  body: 'Run the planner from the dashboard to generate a schedule.',
                );
              }
              return AsyncBody<List<PlannerStop>>(
                value: stopsAsync,
                onRetry: () => ref.invalidate(schedulerStopsProvider),
                builder: (stops) {
                  if (stops.isEmpty) {
                    return const SignNotice(
                      title: 'No stop coordinates',
                      body: 'Add stops with latitude and longitude to display the map.',
                    );
                  }
                  return Stack(
                    children: [
                      PlanMap(plan: plan, stops: stops),
                      _Legend(plan: plan),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

const _routePalette = <Color>[
  Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFFC62828), Color(0xFFE65100),
  Color(0xFF6A1B9A), Color(0xFF00695C), Color(0xFF4527A0), Color(0xFF558B2F),
  Color(0xFFAD1457), Color(0xFF0277BD), Color(0xFF37474F), Color(0xFF4E342E),
  Color(0xFF283593), Color(0xFF1B5E20), Color(0xFF78350F),
];

Color _routeColor(int index) => _routePalette[index % _routePalette.length];

/// Collapsible legend listing bus routes with their colour, student count and
/// travel time — shown in the bottom-left corner of the full-screen map.
class _Legend extends StatefulWidget {
  const _Legend({required this.plan});

  final ActivePlan plan;

  @override
  State<_Legend> createState() => _LegendState();
}

class _LegendState extends State<_Legend> {
  var _expanded = false;

  String _duration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 8,
      bottom: 8,
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220, maxHeight: 300),
          decoration: BoxDecoration(
            color: TransitColors.white.withValues(alpha: 0.92),
            borderRadius: Radii.signAll,
            border: Border.all(color: TransitColors.rule),
          ),
          child: _expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LegendHeader(
                      title: '${widget.plan.summary.busesUsed} bus routes',
                      onCollapse: () => setState(() => _expanded = false),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (var i = 0; i < widget.plan.buses.length; i++)
                              _LegendRow(
                                color: _routeColor(i),
                                busId: widget.plan.buses[i].busId,
                                studentCount: widget.plan.buses[i].studentCount,
                                duration: _duration(widget.plan.buses[i].totalTravelSeconds),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.legend_toggle, size: 16, color: TransitColors.inkSoft),
                      const SizedBox(width: Space.xs),
                      Text(
                        '${widget.plan.summary.busesUsed} routes',
                        style: TransitType.small.copyWith(color: TransitColors.inkSoft),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _LegendHeader extends StatelessWidget {
  const _LegendHeader({required this.title, required this.onCollapse});

  final String title;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.s, Space.s),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: TransitColors.rule)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: TransitType.small.copyWith(fontWeight: FontWeight.w800)),
        ),
        GestureDetector(
          onTap: onCollapse,
          child: const Icon(Icons.expand_more, size: 18, color: TransitColors.inkSoft),
        ),
      ],
    ),
  );
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.busId,
    required this.studentCount,
    required this.duration,
  });

  final Color color;
  final String busId;
  final int studentCount;
  final String duration;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
    child: Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: Space.s),
        Expanded(
          child: Text(
            busId,
            style: TransitType.small.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '$studentCount · $duration',
          style: TransitType.small.copyWith(color: TransitColors.inkSoft),
        ),
      ],
    ),
  );
}
