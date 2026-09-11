import 'package:cloud_firestore/cloud_firestore.dart';

class AdminDashboardPreferences {
  const AdminDashboardPreferences({
    required this.showStudentOverview,
    required this.showAttendanceOverview,
    required this.showPendingFees,
    required this.showConsecutiveAbsenceAlert,
    required this.showTeacherOverview,
    required this.showQrAndAppLink,
    required this.showQuickActions,
    required this.showUpdates,
  });

  static const defaults = AdminDashboardPreferences(
    showStudentOverview: true,
    showAttendanceOverview: true,
    showPendingFees: true,
    showConsecutiveAbsenceAlert: true,
    showTeacherOverview: true,
    showQrAndAppLink: true,
    showQuickActions: true,
    showUpdates: true,
  );

  final bool showStudentOverview;
  final bool showAttendanceOverview;
  final bool showPendingFees;
  final bool showConsecutiveAbsenceAlert;
  final bool showTeacherOverview;
  final bool showQrAndAppLink;
  final bool showQuickActions;
  final bool showUpdates;

  static DocumentReference<Map<String, dynamic>> get document {
    return FirebaseFirestore.instance
        .collection('settings')
        .doc('admin_dashboard');
  }

  static Stream<AdminDashboardPreferences> stream() {
    return document.snapshots().map((snapshot) {
      return AdminDashboardPreferences.fromMap(snapshot.data());
    });
  }

  factory AdminDashboardPreferences.fromMap(Map<String, dynamic>? data) {
    bool value(String key, bool fallback) {
      final raw = data?[key];
      return raw is bool ? raw : fallback;
    }

    const fallback = AdminDashboardPreferences.defaults;
    return AdminDashboardPreferences(
      showStudentOverview: value(
        'showStudentOverview',
        fallback.showStudentOverview,
      ),
      showAttendanceOverview: value(
        'showAttendanceOverview',
        fallback.showAttendanceOverview,
      ),
      showPendingFees: value('showPendingFees', fallback.showPendingFees),
      showConsecutiveAbsenceAlert: value(
        'showConsecutiveAbsenceAlert',
        fallback.showConsecutiveAbsenceAlert,
      ),
      showTeacherOverview: value(
        'showTeacherOverview',
        fallback.showTeacherOverview,
      ),
      showQrAndAppLink: value('showQrAndAppLink', fallback.showQrAndAppLink),
      showQuickActions: value('showQuickActions', fallback.showQuickActions),
      showUpdates: value('showUpdates', fallback.showUpdates),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'showStudentOverview': showStudentOverview,
      'showAttendanceOverview': showAttendanceOverview,
      'showPendingFees': showPendingFees,
      'showConsecutiveAbsenceAlert': showConsecutiveAbsenceAlert,
      'showTeacherOverview': showTeacherOverview,
      'showQrAndAppLink': showQrAndAppLink,
      'showQuickActions': showQuickActions,
      'showUpdates': showUpdates,
    };
  }

  AdminDashboardPreferences copyWith({
    bool? showStudentOverview,
    bool? showAttendanceOverview,
    bool? showPendingFees,
    bool? showConsecutiveAbsenceAlert,
    bool? showTeacherOverview,
    bool? showQrAndAppLink,
    bool? showQuickActions,
    bool? showUpdates,
  }) {
    return AdminDashboardPreferences(
      showStudentOverview: showStudentOverview ?? this.showStudentOverview,
      showAttendanceOverview:
          showAttendanceOverview ?? this.showAttendanceOverview,
      showPendingFees: showPendingFees ?? this.showPendingFees,
      showConsecutiveAbsenceAlert:
          showConsecutiveAbsenceAlert ?? this.showConsecutiveAbsenceAlert,
      showTeacherOverview: showTeacherOverview ?? this.showTeacherOverview,
      showQrAndAppLink: showQrAndAppLink ?? this.showQrAndAppLink,
      showQuickActions: showQuickActions ?? this.showQuickActions,
      showUpdates: showUpdates ?? this.showUpdates,
    );
  }

  Future<void> save() async {
    await document.set({
      ...toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> reset() async {
    await defaults.save();
  }
}
