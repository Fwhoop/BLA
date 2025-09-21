import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/screens/signup_page.dart';
import 'package:barangay_legal_aid/screens/login_page.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';
import 'chat_screen.dart';
import 'chat_history.dart';
import 'chat_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final authService = AuthService();
  final isLoggedIn = await authService.isLoggedIn();
  
  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;

  MyApp({required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Barangay Legal Aid Chatbot',
      theme: ThemeData(
        primaryColor: Color(0xFF99272D),
        scaffoldBackgroundColor: Color(0xFFFFFFFF),
        colorScheme: ColorScheme.light(
          primary: Color(0xFF99272D),
          secondary: Color(0xFF36454F),
          background: Color(0xFFFFFFFF),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF99272D),
          foregroundColor: Color(0xFFFFFFFF),
          elevation: 3,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFFFFFFFF),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFF99272D),
            foregroundColor: Color(0xFFFFFFFF),
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Color(0xFF99272D),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFFFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFF36454F).withOpacity(0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFF36454F).withOpacity(0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFF99272D), width: 2),
          ),
        ),
      ),
      home: isLoggedIn ? HomeScreen() : LoginPage(),
      routes: {
        '/login': (context) => LoginPage(),
        '/signup': (context) => SignupPage(),
        '/home': (context) => HomeScreen(),
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ChatProvider _chatProvider = ChatProvider();
  final AuthService _authService = AuthService();
  bool _isSidebarVisible = true;

  @override
  void initState() {
    super.initState();
    _chatProvider.addListener(_refresh);
  }

  @override
  void dispose() {
    _chatProvider.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    setState(() {});
  }

  void _logout() async {
    await _authService.logout();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginPage()),
    );
  }

  void _toggleSidebar() {
    setState(() {
      _isSidebarVisible = !_isSidebarVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Barangay Legal Aid Chatbot'),
        backgroundColor: Color(0xFF99272D),
        actions: [
          // Toggle sidebar button
          IconButton(
            onPressed: _toggleSidebar,
            tooltip: _isSidebarVisible ? 'Hide sidebar' : 'Show sidebar',
            icon: Text(
              _isSidebarVisible ? '◀' : '▶',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: _logout,
            child: Text('LOGOUT', style: TextStyle(
              color: Color(0xFFFFFFFF),
              fontWeight: FontWeight.w500,
            )),
          ),
        ],
      ),
      body: Container(
        color: Color(0xFFFFFFFF),
        child: Row(
          children: [
            // Sidebar with animation
            AnimatedContainer(
              duration: Duration(milliseconds: 300),
              width: _isSidebarVisible ? 300 : 0,
              curve: Curves.easeInOut,
              child: _isSidebarVisible
                  ? Container(
                      decoration: BoxDecoration(
                        color: Color(0xFF36454F),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: Offset(2, 0),
                          ),
                        ],
                      ),
                      child: ChatHistorySidebar(chatProvider: _chatProvider),
                    )
                  : SizedBox.shrink(),
            ),
            
            // Resize handle for drag to toggle
            if (_isSidebarVisible)
              GestureDetector(
                onPanUpdate: (details) {
                  if (details.delta.dx < -5) {
                    _toggleSidebar();
                  }
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Container(
                    width: 4,
                    color: Color(0xFF36454F).withOpacity(0.3),
                    child: GestureDetector(
                      onTap: _toggleSidebar,
                      child: Center(
                        child: Container(
                          width: 2,
                          height: 40,
                          color: Color(0xFFFFFFFF).withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            
            // Main chat area
            Expanded(
              child: Stack(
                children: [
                  ChatScreen(chatProvider: _chatProvider),
                  
                  // Show sidebar button when hidden
                  if (!_isSidebarVisible)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: FloatingActionButton.small(
                        onPressed: _toggleSidebar,
                        backgroundColor: Color(0xFF99272D),
                        child: Text(
                          '▶',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        tooltip: 'Show sidebar',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      
      // Add drawer for mobile view
      drawer: Drawer(
        width: 300,
        backgroundColor: Color(0xFF36454F),
        child: ChatHistorySidebar(chatProvider: _chatProvider),
      ),
    );
  }
}