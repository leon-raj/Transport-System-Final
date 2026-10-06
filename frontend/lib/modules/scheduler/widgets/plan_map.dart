import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config.dart';
import '../../../design/design.dart';
import '../data/scheduler_api.dart';

// Distinct palette for up to ~300 bus routes (cycles if more).
const _routePalette = <Color>[
  Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFFC62828), Color(0xFFE65100),
  Color(0xFF6A1B9A), Color(0xFF00695C), Color(0xFF4527A0), Color(0xFF558B2F),
  Color(0xFFAD1457), Color(0xFF0277BD), Color(0xFF37474F), Color(0xFF4E342E),
  Color(0xFF283593), Color(0xFF1B5E20), Color(0xFF78350F),
];

Color _routeColor(int index) => _routePalette[index % _routePalette.length];

/// OSM map of an [ActivePlan]: one coloured polyline per bus route, clustered
/// stop markers that expand on zoom-in, and a square marker for the college.
///
/// Handles hundreds of stops gracefully by aggregating into grid clusters below
/// zoom 12, each showing a count badge.
class PlanMap extends StatefulWidget {
  const PlanMap({
    super.key,
    required this.plan,
    required this.stops,
    this.height,
  });

  final ActivePlan plan;
  final List<PlannerStop> stops;

  /// Height in pixels. Null = expand to fill available space.
  final double? height;

  @visibleForTesting
  static TileProvider? tileProviderOverride;

  @override
  State<PlanMap> createState() => _PlanMapState();
}

class _PlanMapState extends State<PlanMap> {
  final _map = MapController();
  var _zoom = 10.0;
  var _ready = false;

  late final Map<String, PlannerStop> _stopIndex = {
    for (final s in widget.stops) s.stopId: s,
  };

  @override
  void initState() {
    super.initState();
    // Listen to map camera changes to rebuild clusters.
    _map.mapEventStream.listen((event) {
      if (!mounted) return;
      final z = _map.camera.zoom;
      if ((z - _zoom).abs() >= 0.4) setState(() => _zoom = z);
    });
  }

  void _fitAll([int attempt = 0]) {
    if (!mounted) return;
    final pts = _allPoints;
    if (_map.camera.nonRotatedSize.width <= 0 && attempt < 10) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll(attempt + 1));
      return;
    }
    if (pts.length > 1) {
      _map.fitCamera(CameraFit.coordinates(
        coordinates: pts,
        padding: const EdgeInsets.all(40),
        maxZoom: 14,
      ));
    }
  }

  List<LatLng> get _allPoints => [
    for (final s in widget.stops)
      LatLng(s.latitude, s.longitude),
  ];

  @override
  Widget build(BuildContext context) {
    final allPts = _allPoints;
    if (allPts.isEmpty) {
      return SizedBox(
        height: widget.height ?? 300,
        child: const SignNotice(
          title: 'No stops on the map yet',
          body: 'Add stops with their coordinates in the Stops tab.',
        ),
      );
    }

    final mapWidget = FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: allPts.first,
        initialZoom: 10,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () {
          _ready = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
        },
      ),
      children: [
        TileLayer(
          urlTemplate: AppConfig.tileUrl,
          userAgentPackageName: 'edu.college.transit',
          tileProvider: PlanMap.tileProviderOverride,
        ),
        PolylineLayer(polylines: _buildRouteLines()),
        MarkerLayer(markers: _buildMarkers()),
        Align(
          alignment: Alignment.bottomRight,
          child: Container(
            color: TransitColors.white.withValues(alpha: 0.85),
            padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 1),
            child: Text(
              AppConfig.tileAttribution,
              style: TransitType.small.copyWith(fontSize: 11),
            ),
          ),
        ),
      ],
    );

    return ClipRRect(
      borderRadius: Radii.signAll,
      child: widget.height != null
          ? SizedBox(height: widget.height, child: mapWidget)
          : mapWidget,
    );
  }

  // ── Route polylines ──────────────────────────────────────────────────────

  List<Polyline> _buildRouteLines() {
    final lines = <Polyline>[];
    for (var i = 0; i < widget.plan.buses.length; i++) {
      final route = widget.plan.buses[i];
      final pts = <LatLng>[];
      for (final rs in route.stops) {
        final stop = _stopIndex[rs.stopId];
        if (stop != null) pts.add(LatLng(stop.latitude, stop.longitude));
      }
      // Add college terminus
      final college = _stopIndex[widget.plan.collegeStopId];
      if (college != null) pts.add(LatLng(college.latitude, college.longitude));

      if (pts.length > 1) {
        lines.add(Polyline(
          points: pts,
          strokeWidth: 3,
          color: _routeColor(i).withValues(alpha: 0.85),
        ));
      }
    }
    return lines;
  }

  // ── Clustered stop markers ───────────────────────────────────────────────

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // College stop — always shown as a distinct square.
    final college = _stopIndex[widget.plan.collegeStopId];
    if (college != null) {
      markers.add(_collegeMarker(college));
    }

    // Pickup stops — clustered or individual depending on zoom.
    final pickupStops = widget.stops
        .where((s) => s.stopId != widget.plan.collegeStopId)
        .toList();
    markers.addAll(_buildClusteredMarkers(pickupStops, _zoom));

    return markers;
  }

  Marker _collegeMarker(PlannerStop stop) => Marker(
    point: LatLng(stop.latitude, stop.longitude),
    width: 56,
    height: 44,
    child: Tooltip(
      message: '${stop.name} (college)',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: TransitColors.signBlue,
              borderRadius: Radii.signAll,
            ),
            child: Text(
              'College',
              style: TransitType.small.copyWith(
                color: TransitColors.white,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: TransitColors.signBlue,
              borderRadius: Radii.signAll,
              border: Border.all(color: TransitColors.white, width: 2),
            ),
          ),
        ],
      ),
    ),
  );

  List<Marker> _buildClusteredMarkers(List<PlannerStop> stops, double zoom) {
    if (zoom >= 12 || stops.length <= 1) {
      return stops.map(_stopMarker).toList();
    }

    // Determine grid cell size in degrees based on zoom.
    final gridDeg = zoom < 9 ? 1.0 : zoom < 11 ? 0.25 : 0.06;

    final cells = <String, List<PlannerStop>>{};
    for (final s in stops) {
      final key =
          '${(s.latitude / gridDeg).truncate()},${(s.longitude / gridDeg).truncate()}';
      (cells[key] ??= []).add(s);
    }

    final markers = <Marker>[];
    for (final entry in cells.entries) {
      final list = entry.value;
      if (list.length == 1) {
        markers.add(_stopMarker(list.first));
      } else {
        final avgLat =
            list.map((s) => s.latitude).reduce((a, b) => a + b) / list.length;
        final avgLon =
            list.map((s) => s.longitude).reduce((a, b) => a + b) / list.length;
        markers.add(_clusterMarker(LatLng(avgLat, avgLon), list.length));
      }
    }
    return markers;
  }

  Marker _stopMarker(PlannerStop stop) => Marker(
    point: LatLng(stop.latitude, stop.longitude),
    width: 14,
    height: 14,
    child: Tooltip(
      message: stop.name,
      child: Container(
        decoration: BoxDecoration(
          color: TransitColors.white,
          shape: BoxShape.circle,
          border: Border.all(color: TransitColors.ink, width: 2),
        ),
      ),
    ),
  );

  Marker _clusterMarker(LatLng point, int count) => Marker(
    point: point,
    width: 36,
    height: 36,
    child: Container(
      decoration: BoxDecoration(
        color: TransitColors.signBlue,
        shape: BoxShape.circle,
        border: Border.all(color: TransitColors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TransitType.small.copyWith(
          color: TransitColors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    ),
  );
}
