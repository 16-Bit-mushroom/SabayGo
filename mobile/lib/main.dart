import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/design/components/brand_logo.dart';
import 'core/design/tokens.dart';
import 'core/design/theme.dart';
import 'core/network/api_client.dart';
import 'core/offline/walk_in_sync_service.dart';
import 'core/storage/token_storage.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/operations_repository.dart';
import 'viewmodels/auth_provider.dart';
import 'views/auth/welcome_screen.dart';
import 'views/conductor/conductor_main_screen.dart';
import 'views/passenger_main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SabayGoApp());
}

class SabayGoApp extends StatefulWidget {
  const SabayGoApp({super.key});

  @override
  State<SabayGoApp> createState() => _SabayGoAppState();
}

class _SabayGoAppState extends State<SabayGoApp> {
  late final TokenStorage _tokens;
  late final ApiClient _api;
  late final AuthProvider _auth;
  late final WalkInSyncService _walkInSync;

  @override
  void initState() {
    super.initState();
    _tokens = TokenStorage();
    _api = ApiClient(tokenStorage: _tokens);
    _auth = AuthProvider(
      repository: AuthRepository(_api),
      tokens: _tokens,
    );
    // One queue for the whole app session: a conductor may back out of
    // the manifest screen and return to it without losing what's
    // pending, and a reconnect anywhere should flush it.
    _walkInSync = WalkInSyncService(OperationsRepository(_api))
      ..loadPendingCounts();

    // Any 401, from any repository, drops to sign-in. Wiring it once here
    // means no screen has to remember to handle an expired token.
    _api.onUnauthorized = _auth.handleExpiredSession;

    _auth.restore();
  }

  @override
  void dispose() {
    _api.dispose();
    _walkInSync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: _api),
        Provider<TokenStorage>.value(value: _tokens),
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
        ChangeNotifierProvider<WalkInSyncService>.value(value: _walkInSync),
      ],
      child: MaterialApp(
        title: 'SabayGo',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const _RootRouter(),
      ),
    );
  }
}

/// Chooses the entry screen from session state.
///
/// Routing on role rather than on the email address is the point: the
/// previous build inferred the portal from an "admin@" or "dispatcher@"
/// prefix, which any passenger could have claimed at registration.
class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    switch (auth.status) {
      case AuthStatus.unknown:
        return const _SplashScreen();
      case AuthStatus.signedOut:
        return const WelcomeScreen();
      case AuthStatus.signedIn:
        final role = auth.role;
        if (role != null && role.isCrew) {
          return const ConductorMainScreen();
        }
        // Cooperative administrators use the web console, not this app.
        // Signing in here lands them on the passenger view rather than
        // failing, which is the least surprising outcome.
        return const PassengerMainScreen();
    }
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    // Same white surface and mark as the welcome screen that usually
    // follows it, so the hand-off between the two does not flash.
    return const Scaffold(
      backgroundColor: AppColors.surfaceRaised,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BrandLogo(),
            SizedBox(height: 24),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
