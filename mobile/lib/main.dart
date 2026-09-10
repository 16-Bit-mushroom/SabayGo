import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'data/repositories/auth_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _tokens = TokenStorage();
    _api = ApiClient(tokenStorage: _tokens);
    _auth = AuthProvider(
      repository: AuthRepository(_api),
      tokens: _tokens,
    );

    // Any 401, from any repository, drops to sign-in. Wiring it once here
    // means no screen has to remember to handle an expired token.
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
        Provider<TokenStorage>.value(value: _tokens),
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
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
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'SabayGo',
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
