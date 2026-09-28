import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/audit_repository.dart';
import 'data/repositories/dispatch_repository.dart';
import 'data/repositories/fleet_repository.dart';
import 'data/repositories/policy_repository.dart';
import 'data/repositories/revenue_repository.dart';
import 'data/repositories/tracking_repository.dart';
import 'data/repositories/schedule_repository.dart';
import 'core/layout/operator_shell.dart';
import 'modules/auth/screens/login_screen.dart';
import 'viewmodels/auth_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SabayGoOperatorConsole());
}

class SabayGoOperatorConsole extends StatefulWidget {
  const SabayGoOperatorConsole({super.key});

  @override
  State<SabayGoOperatorConsole> createState() => _SabayGoOperatorConsoleState();
}

class _SabayGoOperatorConsoleState extends State<SabayGoOperatorConsole> {
  late final TokenStorage _tokens;
  late final ApiClient _api;
  late final AuthProvider _auth;

  @override
  void initState() {
    super.initState();
    _tokens = TokenStorage();
    _api = ApiClient(tokenStorage: _tokens);
    _auth = AuthProvider(repository: AuthRepository(_api), tokens: _tokens);

    // Any 401, from any repository, drops the console back to sign-in.
    _api.onUnauthorized = _auth.handleExpiredSession;

    _auth.restore();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: _api),
        Provider<FleetRepository>(create: (_) => FleetRepository(_api)),
        Provider<DispatchRepository>(create: (_) => DispatchRepository(_api)),
        Provider<AuditRepository>(create: (_) => AuditRepository(_api)),
        Provider<ScheduleRepository>(create: (_) => ScheduleRepository(_api)),
        Provider<PolicyRepository>(create: (_) => PolicyRepository(_api)),
        Provider<RevenueRepository>(create: (_) => RevenueRepository(_api)),
        Provider<TrackingRepository>(create: (_) => TrackingRepository(_api)),
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
      ],
      child: MaterialApp(
        title: 'SabayGo Operator Console',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFF151923),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF8FBCBB),
            surface: Color(0xFF222736),
            error: Color(0xFFBF616A),
          ),
          useMaterial3: true,
        ),
        home: const _RootRouter(),
      ),
    );
  }
}

class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    switch (auth.status) {
      case AuthStatus.unknown:
        return const _SplashScreen();
      case AuthStatus.signedOut:
        return const LoginScreen();
      case AuthStatus.signedIn:
        return const OperatorShell();
    }
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF151923),
      body: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF8FBCBB)),
        ),
      ),
    );
  }
}
