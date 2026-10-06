import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/session.dart';
import '../../../core/config.dart';

// ─── HTTP client ─────────────────────────────────────────────────────────────

/// Thin wrapper over Dio for the Go bus-scheduler service.
/// Mirrors [ApiClient] but targets [AppConfig.schedulerBase] and uses a longer
/// receive timeout (planning can run for several minutes).
class SchedulerApiClient {
  SchedulerApiClient(this._ref) {
    dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _ref.read(sessionProvider)?.accessToken;
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (e, handler) async {
          final retried = e.requestOptions.extra['retried'] == true;
          if (e.response?.statusCode == 401 && !retried) {
            final fresh = await _ref.read(sessionProvider.notifier).refresh();
            if (fresh != null) {
              final opts = e.requestOptions
                ..headers['Authorization'] = 'Bearer $fresh'
                ..extra['retried'] = true;
              try {
                return handler.resolve(await dio.fetch(opts));
              } on DioException catch (again) {
                return handler.next(again);
              }
            }
          }
          handler.next(e);
        },
      ),
    );
  }

  final Ref _ref;
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.schedulerBase,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 16),
    ),
  );

  Future<T> _wrap<T>(Future<Response> Function() call) async {
    try {
      return (await call()).data as T;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => dio.get(path, queryParameters: _clean(query)));

  Future<T> post<T>(String path, [Object? body]) =>
      _wrap(() => dio.post(path, data: body));

  /// PUT — used for the Go service's CSV import endpoints (registered as PUT /v1/*-from-csv).
  Future<T> put<T>(String path, [Object? body]) =>
      _wrap(() => dio.put(path, data: body));

  Future<void> delete(String path) => _wrap<dynamic>(() => dio.delete(path));

  static Map<String, dynamic>? _clean(Map<String, dynamic>? q) =>
      q == null ? null : (Map.of(q)..removeWhere((_, v) => v == null));
}

final schedulerClientProvider =
    Provider<SchedulerApiClient>(SchedulerApiClient.new);

// ─── Models ──────────────────────────────────────────────────────────────────

class PlannerBus {
  const PlannerBus({required this.id, required this.capacity});

  final String id;
  final int capacity;

  factory PlannerBus.fromJson(Json j) =>
      PlannerBus(id: j['id'] as String, capacity: j['capacity'] as int);
}

class PlannerStop {
  const PlannerStop({
    required this.stopId,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String stopId;
  final String name;
  final double latitude;
  final double longitude;

  factory PlannerStop.fromJson(Json j) => PlannerStop(
    stopId: j['stop_id'] as String,
    name: j['name'] as String,
    latitude: (j['latitude'] as num).toDouble(),
    longitude: (j['longitude'] as num).toDouble(),
  );
}

class PlannerStudent {
  const PlannerStudent({required this.id, required this.stopId});

  final String id;
  final String stopId;

  factory PlannerStudent.fromJson(Json j) =>
      PlannerStudent(id: j['id'] as String, stopId: j['stop_id'] as String);
}

class PlanRouteStop {
  const PlanRouteStop({
    required this.order,
    required this.stopId,
    required this.pickupTime,
    required this.studentIds,
  });

  final int order;
  final String stopId;
  final DateTime pickupTime;
  final List<String> studentIds;

  factory PlanRouteStop.fromJson(Json j) => PlanRouteStop(
    order: j['order'] as int,
    stopId: j['stop_id'] as String,
    pickupTime: DateTime.parse(j['pickup_time'] as String),
    studentIds: (j['student_ids'] as List? ?? []).cast<String>(),
  );
}

class PlanBusRoute {
  const PlanBusRoute({
    required this.busId,
    required this.capacity,
    required this.studentCount,
    required this.emptySeats,
    required this.startStopId,
    required this.dropStopId,
    required this.totalTravelSeconds,
    required this.stops,
    this.startTime,
    this.collegeArrivalTime,
  });

  final String busId;
  final int capacity;
  final int studentCount;
  final int emptySeats;
  final String startStopId;
  final String dropStopId;
  final int totalTravelSeconds;
  final List<PlanRouteStop> stops;
  final DateTime? startTime;
  final DateTime? collegeArrivalTime;

  factory PlanBusRoute.fromJson(Json j) => PlanBusRoute(
    busId: j['bus_id'] as String,
    capacity: j['capacity'] as int,
    studentCount: j['student_count'] as int,
    emptySeats: j['empty_seats'] as int,
    startStopId: j['start_stop_id'] as String,
    dropStopId: j['drop_stop_id'] as String,
    totalTravelSeconds: j['total_travel_time_seconds'] as int,
    stops: (j['stops'] as List? ?? [])
        .cast<Json>()
        .map(PlanRouteStop.fromJson)
        .toList(),
    startTime: j['start_time'] == null
        ? null
        : DateTime.parse(j['start_time'] as String),
    collegeArrivalTime: j['college_arrival_time'] == null
        ? null
        : DateTime.parse(j['college_arrival_time'] as String),
  );
}

class PlanSummary {
  const PlanSummary({
    required this.busesUsed,
    required this.totalStudentRideSeconds,
    required this.emptySeatBufferEnforced,
  });

  final int busesUsed;
  final int totalStudentRideSeconds;
  final int emptySeatBufferEnforced;

  factory PlanSummary.fromJson(Json j) => PlanSummary(
    busesUsed: j['buses_used'] as int,
    totalStudentRideSeconds: j['total_student_ride_seconds'] as int,
    emptySeatBufferEnforced: j['empty_seat_buffer_enforced'] as int,
  );
}

class ActivePlan {
  const ActivePlan({
    required this.resultId,
    required this.planId,
    required this.createdAt,
    required this.collegeStopId,
    required this.buses,
    required this.summary,
  });

  final String resultId;
  final String planId;
  final DateTime createdAt;
  final String collegeStopId;
  final List<PlanBusRoute> buses;
  final PlanSummary summary;

  int get totalStudents => buses.fold(0, (n, b) => n + b.studentCount);

  factory ActivePlan.fromJson(Json j) => ActivePlan(
    resultId: j['result_id'] as String,
    planId: j['plan_id'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    collegeStopId: j['college_stop_id'] as String,
    buses: (j['buses'] as List? ?? [])
        .cast<Json>()
        .map(PlanBusRoute.fromJson)
        .toList(),
    summary: PlanSummary.fromJson(j['summary'] as Json),
  );
}

// ─── Providers ───────────────────────────────────────────────────────────────

final schedulerBusesProvider =
    FutureProvider.autoDispose<List<PlannerBus>>((ref) async {
  final list = await ref.read(schedulerClientProvider).get<List<dynamic>>('/v1/buses');
  return list.cast<Json>().map(PlannerBus.fromJson).toList();
});

final schedulerStopsProvider =
    FutureProvider.autoDispose<List<PlannerStop>>((ref) async {
  final list = await ref.read(schedulerClientProvider).get<List<dynamic>>('/v1/stops');
  return list.cast<Json>().map(PlannerStop.fromJson).toList();
});

final schedulerStudentsProvider =
    FutureProvider.autoDispose<List<PlannerStudent>>((ref) async {
  final list = await ref.read(schedulerClientProvider).get<List<dynamic>>('/v1/students');
  return list.cast<Json>().map(PlannerStudent.fromJson).toList();
});

/// Returns null when no plan exists yet (404 from the service).
final activePlanProvider = FutureProvider.autoDispose<ActivePlan?>((ref) async {
  try {
    final j = await ref.read(schedulerClientProvider).get<Json>('/v1/plans');
    return ActivePlan.fromJson(j);
  } on ApiException catch (e) {
    if (e.status == 404) return null;
    rethrow;
  }
});

// ─── Actions ─────────────────────────────────────────────────────────────────

class SchedulerActions {
  SchedulerActions(this._api);

  final SchedulerApiClient _api;

  // Buses
  Future<void> addBus(String busId, int capacity) =>
      _api.put('/v1/buses', {'bus_id': busId, 'capacity': capacity});

  Future<void> addBusesFromCsv(String csvContent) =>
      _api.put('/v1/buses-from-csv', csvContent);

  Future<void> deleteBus(String busId) => _api.delete('/v1/bus/$busId');

  // Stops
  Future<void> addStop({
    required String stopId,
    required String name,
    required double latitude,
    required double longitude,
  }) => _api.put('/v1/stops', {
    'stop_id': stopId,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
  });

  Future<void> addStopsFromCsv(String csvContent) =>
      _api.put('/v1/stops-from-csv', csvContent);

  Future<void> deleteStop(String stopId) => _api.delete('/v1/stop/$stopId');

  // Students
  Future<void> addStudent(String studentId, String stopId) =>
      _api.put('/v1/students', {'student_id': studentId, 'stop_id': stopId});

  Future<void> addStudentsFromCsv(String csvContent) =>
      _api.put('/v1/students-from-csv', csvContent);

  Future<void> deleteStudent(String studentId) =>
      _api.delete('/v1/student/$studentId');

  // Planning
  Future<String> startPlanFromDb({
    String? collegeStopId,
    DateTime? earliestDeparture,
    DateTime? arrivalDeadline,
    int desiredEmptySeats = 0,
  }) async {
    final body = <String, dynamic>{
      'desired_empty_seats': desiredEmptySeats,
      if (collegeStopId != null)
        'college': {'stop_id': collegeStopId, 'college_id': 'college-1'},
      if (earliestDeparture != null || arrivalDeadline != null)
        'time_window': {
          if (earliestDeparture != null)
            'earliest_departure': earliestDeparture.toIso8601String(),
          if (arrivalDeadline != null)
            'arrival_deadline': arrivalDeadline.toIso8601String(),
        },
    };
    final resp =
        await _api.post<Json>('/v1/plan-from-db?async=true', body);
    return resp['result_id'] as String;
  }

  Future<Json> checkPlan(String resultId) =>
      _api.get<Json>('/v1/plans/$resultId');
}

final schedulerActionsProvider =
    Provider((ref) => SchedulerActions(ref.read(schedulerClientProvider)));
