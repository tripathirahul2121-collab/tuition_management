import 'package:flutter/material.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';

import '../../features/dashboard/teacher_dashboard.dart';
import '../../features/dashboard/student_dashboard.dart';

import '../../features/dashboard/generate_password_screen.dart'
    as generate_password;

import '../../features/dashboard/members_screen.dart' as members_screen;

import '../../features/dashboard/attendance_screen.dart';
import '../../features/dashboard/progress_report_screen.dart';
import '../../features/dashboard/performance_analysis_screen.dart';
import '../../features/dashboard/stars_of_me_screen.dart';
import '../../features/dashboard/updates_screen.dart';
import '../../features/dashboard/fees_tracking_screen.dart';
import '../../features/dashboard/mcq_test_screen.dart';
import '../../features/dashboard/settings_screen.dart';
import '../../features/dashboard/student_updates_screen.dart';
import '../../features/dashboard/student_attendance_screen.dart';
import '../../features/dashboard/student_fees_status_screen.dart';
import '../../features/dashboard/student_mcq_tests_screen.dart';
import '../../features/dashboard/student_report_card_screen.dart';
import '../../features/dashboard/student_teacher_remarks_screen.dart';
import '../../features/dashboard/current_stars_screen.dart';

import '../../splash/splash_screen.dart';

class AppRouter {
  static final routes = <String, WidgetBuilder>{
    ////////////////////////////////////////////////////////////
    /// CORE
    ////////////////////////////////////////////////////////////
    '/': (context) => const SplashScreen(),

    '/login': (context) => const LoginScreen(),

    '/signup': (context) => const SignupScreen(),

    ////////////////////////////////////////////////////////////
    /// DASHBOARDS
    ////////////////////////////////////////////////////////////
    '/teacher': (context) => const TeacherDashboard(),

    /// ✅ FIXED (NO PARAM REQUIRED NOW)
    '/student': (context) => const StudentDashboard(),

    ////////////////////////////////////////////////////////////
    /// TEACHER FEATURES
    ////////////////////////////////////////////////////////////
    '/generate-password': (context) =>
        const generate_password.GeneratePasswordScreen(),

    '/members': (context) => const members_screen.MembersScreen(),

    '/attendance': (context) => const AttendanceScreen(),

    '/progress': (context) => const ProgressReportScreen(),

    '/performance': (context) => const PerformanceAnalysisScreen(),

    '/feedback': (context) => const StarsOfMEScreen(),

    '/updates': (context) => const UpdatesScreen(),

    '/fees': (context) => const FeesTrackingScreen(),

    '/mcq-tests': (context) => const MCQTestScreen(),

    '/settings': (context) => const SettingsScreen(),

    ////////////////////////////////////////////////////////////
    /// STUDENT FEATURES
    ////////////////////////////////////////////////////////////
    '/student-attendance': (context) => const StudentAttendanceScreen(),

    '/student-updates': (context) => const StudentUpdatesScreen(),

    '/student-fees': (context) => const StudentFeesStatusScreen(),

    '/student-report-card': (context) => const StudentReportCardScreen(),

    '/student-teacher-remarks': (context) =>
        const StudentTeacherRemarksScreen(),

    '/student-stars': (context) => const StarsOfMEScreen(readOnly: true),

    '/student-current-stars': (context) => const CurrentStarsScreen(),

    '/student-mcq-tests': (context) => const StudentMCQTestsScreen(),
  };
}
