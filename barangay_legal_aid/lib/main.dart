import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';

import 'package:barangay_legal_aid/screens/signup_page.dart';
import 'package:barangay_legal_aid/screens/login_page.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';
import 'package:barangay_legal_aid/services/secure_storage_service.dart';
import 'package:barangay_legal_aid/models/user_model.dart';
import 'package:barangay_legal_aid/chat_provider.dart';
import 'package:barangay_legal_aid/chat_history.dart';
import 'package:barangay_legal_aid/screens/categorized_questions_screen.dart';
import 'package:barangay_legal_aid/screens/admin_dashboard.dart';
import 'package:barangay_legal_aid/screens/superadmin_dashboard.dart';
import 'package:barangay_legal_aid/screens/user_profile_page.dart';
import 'package:barangay_legal_aid/screens/forms_hub_page.dart';
import 'package:barangay_legal_aid/screens/forgot_password_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final secure = SecureStorageService();
  final authService = AuthService(
    secureStorage: secure,
    apiService: ApiService(secure),
  );
  final isLoggedIn = await authService.isLoggedIn();

  final apiService = ApiService(secure);
  runApp(
    MyApp(
      isLoggedIn: isLoggedIn,
      authService: authService,
      apiService: apiService,
    ),
  );
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  final AuthService authService;
  final ApiService apiService;

  const MyApp({
    super.key,
    required this.isLoggedIn,
    required this.authService,
    required this.apiService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: authService),
        Provider<ApiService>.value(value: apiService),
      ],
      child: MaterialApp(
        title: 'Barangay Legal Aid Chatbot',
        theme: ThemeData(
          useMaterial3: true,
          primaryColor: Color(0xFF99272D),
          scaffoldBackgroundColor: Color(0xFFFFFFFF),
          colorScheme: ColorScheme.light(
            primary: Color(0xFF99272D),
            secondary: Color(0xFF36454F),
            surface: Color(0xFFFFFFFF),
            error: Color(0xFFB3261E),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide(color: Color(0xFFCDD5DF)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide(color: Color(0xFF99272D), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide(color: Color(0xFFB3261E)),
            ),
            filled: true,
            fillColor: Color(0xFFFFFFFF),
            labelStyle: TextStyle(color: Color(0xFF36454F)),
            contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF99272D),
              foregroundColor: Color(0xFFFFFFFF),
              textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        home: isLoggedIn ? HomeScreen() : LoginPage(),
        routes: {
          '/login': (context) => LoginPage(),
          '/signup': (context) => SignupPage(),
          '/home': (context) => HomeScreen(),
          '/admin': (context) => AdminDashboard(),
          '/superadmin': (context) => SuperAdminDashboard(),
          '/profile': (context) => UserProfilePage(),
          '/forms': (context) => FormsHubPage(),
          '/forgot-password': (context) => ForgotPasswordScreen(),
        },
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  late final ChatProvider _chatProvider;
  User? _currentUser;
  bool _showHistory = false;
  bool _isLoading = true;
  bool _guardRedirect = false;

  @override
  void initState() {
    super.initState();
    final api = Provider.of<ApiService>(context, listen: false);
    _chatProvider = ChatProvider(apiService: api);
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final user = await auth.getCurrentUser();
    if (!mounted) return;
    setState(() {
      _currentUser = user;
      _isLoading = false;
      _guardRedirect = user == null;
    });
  }

  Future<void> _logout() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    await auth.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    if (_guardRedirect && !_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/login');
      });
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_currentUser == null) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_currentUser!.isSuperAdmin) {
      return SuperAdminDashboard();
    }
    if (_currentUser!.isAdmin) {
      return AdminDashboard();
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(_showHistory ? Icons.chevron_left : Icons.chevron_right),
          tooltip: _showHistory ? 'Hide history' : 'Show history',
          onPressed: () {
            setState(() => _showHistory = !_showHistory);
          },
        ),
        title: Text('Barangay Legal Aid Chatbot'),
        backgroundColor: Color(0xFF99272D),
        actions: [
          IconButton(
            icon: Icon(Icons.dashboard),
            tooltip: 'Forms Hub',
            onPressed: () => Navigator.pushNamed(context, '/forms'),
          ),
          IconButton(
            icon: Icon(Icons.person),
            tooltip: 'My Profile',
            onPressed: () => Navigator.pushNamed(context, '/profile'),
          ),
          TextButton(
            onPressed: _logout,
            child: Text(
              'LOGOUT',
              style: TextStyle(
                color: Color(0xFFFFFFFF),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          if (_showHistory)
            Container(
              width: 300,
              color: Color(0xFF36454F),
              child: ChatHistorySidebar(
                chatProvider: _chatProvider,
                onToggle: () => setState(() => _showHistory = false),
              ),
            ),
          Expanded(
            child: CategorizedQuestionsScreen(
              chatProvider: _chatProvider,
              currentUser: _currentUser!,
            ),
          ),
        ],
      ),
    );
  }
}
