import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';

////////////////////////////////////////////////////////////
/// PROVIDERS
////////////////////////////////////////////////////////////

final authRepoProvider = Provider<AuthRepository>((ref) => AuthRepository());

final authControllerProvider = StateNotifierProvider<AuthController, bool>((
  ref,
) {
  return AuthController(ref.read(authRepoProvider));
});

final userTypeProvider = StateProvider<String>((ref) => "teacher");

////////////////////////////////////////////////////////////
/// CONTROLLER
////////////////////////////////////////////////////////////

class AuthController extends StateNotifier<bool> {
  final AuthRepository repo;

  AuthController(this.repo) : super(false);

  //////////////////////////////////////////////////////////
  /// LOGIN
  //////////////////////////////////////////////////////////

  Future<bool> login(String mobile, String password, String role) async {
    state = true;

    try {
      final result = await repo.login(mobile, password, role);
      return result;
    } catch (e) {
      debugPrint("LOGIN ERROR: $e");
      return false;
    } finally {
      state = false;
    }
  }

  //////////////////////////////////////////////////////////
  /// SIGNUP
  //////////////////////////////////////////////////////////

  Future<bool> signup({
    required String mobile,
    required String name,
    required String role,
    required String password,
    String school = "",
    String userClass = "",
    String userBatch = "regular",
  }) async {
    state = true;

    try {
      final result = await repo.registerUser(
        mobile: mobile,
        name: name,
        role: role,
        password: password,
        school: school,
        userClass: userClass,
        userBatch: userBatch,
      );
      return result;
    } catch (e) {
      debugPrint("SIGNUP ERROR: $e");
      return false;
    } finally {
      state = false;
    }
  }

  //////////////////////////////////////////////////////////
  /// GENERATE PASSWORD (FIXED)
  //////////////////////////////////////////////////////////
  Future<(String?, bool)> generatePassword(
    String mobile, {
    String name = "",
    String userClass = "",
    String userBatch = "regular",
    String role = "student",
    required String password, // ✅ ADD THIS
  }) async {
    state = true;

    try {
      final (_, success) = await repo.generatePasswordForUser(
        mobile,
        name: name,
        userClass: userClass,
        userBatch: userBatch,
        role: role,
        password: password, // ✅ SAME PASSWORD PASSING
      );

      return success ? (password, true) : (null, false);
    } catch (e) {
      debugPrint("GENERATE PASSWORD ERROR: $e");
      return (null, false);
    } finally {
      state = false;
    }
  }
}
