import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:math';
import 'dart:async';
import 'firebase_options.dart';

// 🔔 Plugin de notificaciones locales
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = 
    FlutterLocalNotificationsPlugin();

// 🔔 Handler para mensajes en background/terminated
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Inicializar Firebase si es necesario en background
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('🔔 Mensaje FCM en background: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Registrar handler de background para FCM
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Arrancar UI lo antes posible
  runApp(MyApp());

  // Inicializaciones no bloqueantes (tras mostrar UI)
  // Nota: evitar pedir permisos antes de montar la UI para no congelar la pantalla.
  // Ejecutamos en microtask para no bloquear el frame inicial
  // ignore: discarded_futures
  Future.microtask(() async {
    await _safeInitServices();
  });
}

// 🔔 Configurar notificaciones locales
Future<void> _initializeLocalNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
      
  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );
  
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      // Manejar cuando el usuario toca la notificación
      debugPrint('🔔 Notificación tocada: ${response.payload}');
    },
  );
}

// 🔧 Inicialización segura y diferida de servicios (Local Notifications + FCM)
Future<void> _safeInitServices() async {
  try {
    await _initializeLocalNotifications();
  } catch (e, st) {
    debugPrint('❌ Error init LocalNotifications: $e\n$st');
  }
  try {
    await _initializeFirebaseMessaging();
  } catch (e, st) {
    debugPrint('❌ Error init FCM: $e\n$st');
  }
}

// 🔔 Configurar Firebase Cloud Messaging
Future<void> _initializeFirebaseMessaging() async {
  final messaging = FirebaseMessaging.instance;
  // Solicitar permisos en iOS/macOS
  final settings = await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
    sound: true,
  );
  debugPrint('🔔 Permisos FCM: ${settings.authorizationStatus}');

  // Mostrar notificaciones cuando la app está en foreground (iOS)
  // Desactivar por completo la presentación en primer plano
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: false,
    badge: false,
    sound: false,
  );

  // Obtener y registrar token
  final token = await messaging.getToken();
  debugPrint('🔔 FCM Token: $token');
  final user = FirebaseAuth.instance.currentUser;
  if (user != null && token != null) {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({'fcmTokens': FieldValue.arrayUnion([token])}, SetOptions(merge: true));
  }

  // Manejar refresh de token
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'fcmTokens': FieldValue.arrayUnion([newToken])}, SetOptions(merge: true));
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Amor App',
      theme: ThemeData(
        primarySwatch: Colors.pink,
        fontFamily: 'Inter',
      ),
      home: AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 48),
                    SizedBox(height: 12),
                    Text('Error de autenticación', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('${snapshot.error}', textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          );
        }
        
        if (snapshot.hasData) {
          return ConnectionScreen(userName: 'Usuario');
        }
        
        return LoginScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;

  Future<void> _signInAnonymously() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Por favor ingresa tu nombre')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userCredential = await FirebaseAuth.instance.signInAnonymously();
      final user = userCredential.user!;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ConnectionScreen(userName: name),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFE4E8), Color(0xFFFFF8F8), Color(0xFFFFE4E8)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite, size: 80, color: Color(0xFFE91E63)),
                SizedBox(height: 30),
                Text(
                  'Amor App',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD81B60),
                  ),
                ),
                SizedBox(height: 40),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Tu nombre',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
                SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signInAnonymously,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFE91E63),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: _isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text('Continuar', style: TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ConnectionScreen extends StatefulWidget {
  final String userName;
  const ConnectionScreen({super.key, required this.userName});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final TextEditingController _partnerIdController = TextEditingController();
  String? _userId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _userId = FirebaseAuth.instance.currentUser?.uid;
    _checkExistingConnection();
    _listenForAcceptedInvitations();
  }

  void _listenForAcceptedInvitations() {
    if (_userId == null) return;
    
    // Escuchar invitaciones enviadas por este usuario que sean aceptadas
    FirebaseFirestore.instance
        .collection('invitations')
        .where('senderId', isEqualTo: _userId)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty && mounted) {
        // Si hay una invitación aceptada, navegar al MainScreen
        final invitation = snapshot.docs.first.data();
        final receiverId = invitation['receiverId'];
        
        // Crear el pairId ordenado alfabéticamente
        final sortedIds = [_userId!, receiverId]..sort();
        final pairId = '${sortedIds[0]}_${sortedIds[1]}';
        
        // Guardar la información localmente
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString('partnerId', receiverId);
          prefs.setString('pairId', pairId);
        });
        
        // Navegar al MainScreen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MainScreen(
              userName: widget.userName,
              partnerId: receiverId,
              pairId: pairId,
            ),
          ),
        );
      }
    });
  }

  Future<void> _checkExistingConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPartnerId = prefs.getString('partnerId');
    final savedPairId = prefs.getString('pairId');
    
    if (savedPartnerId != null && savedPairId != null) {
      try {
        final pairDoc = await FirebaseFirestore.instance
            .collection('pairs')
            .doc(savedPairId)
            .get();
            
        if (pairDoc.exists && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => MainScreen(
                userName: widget.userName,
                partnerId: savedPartnerId,
                pairId: savedPairId,
              ),
            ),
          );
        }
      } catch (e) {
        // Error verificando conexión: $e
        debugPrint('Error verificando conexión: $e');
      }
    }
  }

  Widget _buildPendingInvitations() {
    if (_userId == null) return SizedBox.shrink();
    
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('invitations')
          .where('receiverId', isEqualTo: _userId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Error en stream de invitaciones: ${snapshot.error}');
          return SizedBox.shrink();
        }
        
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        
        final invitations = snapshot.data?.docs ?? [];
        
        if (invitations.isEmpty) {
          return SizedBox.shrink();
        }
        
        return Column(
          children: [
            Text(
              'Invitaciones Pendientes',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFD81B60)),
            ),
            SizedBox(height: 15),
            
            ...invitations.map((doc) {
              final invitation = doc.data() as Map<String, dynamic>;
              final invitationId = doc.id;
              
              return Container(
                margin: EdgeInsets.only(bottom: 10),
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.1),
                      blurRadius: 5,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invitación de ${invitation['senderName'] ?? 'Usuario'}',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFD81B60)),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'ID: ${invitation['senderId']}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600], fontFamily: 'monospace'),
                    ),
                    SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : () => _acceptInvitation(
                              invitationId,
                              invitation['senderId'],
                              invitation['senderName'] ?? 'Usuario',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text('Aceptar', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : () => _rejectInvitation(invitationId),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text('Rechazar', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Future<void> _rejectInvitation(String invitationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('invitations')
          .doc(invitationId)
          .update({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invitación rechazada'), backgroundColor: Colors.orange),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _shareUserId() async {
    if (_userId == null) return;
    
    final shareText = '''¡Hola! 💕

¿Quieres conectarte conmigo en nuestra app de amor?

Mi ID único es: $_userId

1. Descarga la app "Amor App" 
2. Ingresa mi ID para enviarme una invitación
3. ¡Podremos enviarnos abrazos y besos virtuales! 🤗💋

¡Te espero! ❤️''';

    try {
      await Share.share(
        shareText,
        subject: '💕 Conectémonos en Amor App',
      );
    } catch (e) {
      // Si Share.share falla, copiamos al portapapeles como fallback
      await Clipboard.setData(ClipboardData(text: _userId!));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ID copiado al portapapeles'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _sendInvitation() async {
    final partnerId = _partnerIdController.text.trim();
    
    if (partnerId.isEmpty || partnerId == _userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ID inválido'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Verificar que el usuario existe
      final partnerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(partnerId)
          .get();

      if (!partnerDoc.exists) {
        throw Exception('Usuario no encontrado');
      }

      // Crear la invitación
      await FirebaseFirestore.instance.collection('invitations').add({
        'senderId': _userId,
        'receiverId': partnerId,
        'senderName': widget.userName,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('¡Invitación enviada! 💕'), backgroundColor: Colors.green),
      );

      _partnerIdController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _acceptInvitation(String invitationId, String senderId, String senderName) async {
    setState(() => _isLoading = true);

    try {
      // Crear el pairId ordenado alfabéticamente
      final sortedIds = [_userId!, senderId]..sort();
      final pairId = '${sortedIds[0]}_${sortedIds[1]}';

      // Actualizar la invitación como aceptada e incluir el nombre del receptor
      await FirebaseFirestore.instance
          .collection('invitations')
          .doc(invitationId)
          .update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'receiverName': widget.userName, // Agregar el nombre del que acepta
      });

      // Crear el documento de pareja
      await FirebaseFirestore.instance
          .collection('pairs')
          .doc(pairId)
          .set({
        'members': [_userId, senderId],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Guardar la información localmente
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('partnerId', senderId);
      await prefs.setString('pairId', pairId);

      // Navegar a la pantalla principal
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MainScreen(
            userName: widget.userName,
            partnerId: senderId,
            pairId: pairId,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFE4E8), Color(0xFFFFF8F8), Color(0xFFFFE4E8)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24.0),
            child: Column(
              children: [
                SizedBox(height: 40),
                
                // Logo
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFFE91E63).withOpacity(0.2),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(Icons.favorite_border, size: 60, color: Color(0xFFE91E63)),
                ),
                
                SizedBox(height: 30),
                Text(
                  '¡Conecta con tu pareja!',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFFD81B60)),
                  textAlign: TextAlign.center,
                ),
                
                SizedBox(height: 20),
                Text(
                  'Envía una invitación usando su ID único',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                
                SizedBox(height: 40),
                
                // Sección para enviar invitación
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 10,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enviar Invitación',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFD81B60)),
                      ),
                      SizedBox(height: 15),
                      TextField(
                        controller: _partnerIdController,
                        decoration: InputDecoration(
                          labelText: 'ID de tu pareja',
                          prefixIcon: Icon(Icons.person, color: Color(0xFFE91E63)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                      ),
                      SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _sendInvitation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFE91E63),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.send, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text('Enviar Invitación', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 30),
                
                // Tu ID único
                Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Text('Tu ID único', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.blue[700])),
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _userId ?? 'Cargando...',
                                style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.blue[800], fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _userId ?? ''));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('ID copiado al portapapeles'), backgroundColor: Colors.green),
                                );
                              },
                              icon: Icon(Icons.copy, size: 16),
                              label: Text('Copiar'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[100],
                                foregroundColor: Colors.blue[700],
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _shareUserId,
                              icon: Icon(Icons.share, size: 16),
                              label: Text('Compartir'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[100],
                                foregroundColor: Colors.green[700],
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text('Comparte este ID con tu pareja', style: TextStyle(fontSize: 11, color: Colors.blue[600])),
                    ],
                  ),
                ),
                
                SizedBox(height: 30),
                
                // Invitaciones pendientes (usando StreamBuilder para tiempo real)
                _buildPendingInvitations(),
                
                SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// El resto del código del MainScreen se mantiene igual
enum MessageType { abrazo, beso }

class MainScreen extends StatefulWidget {
  final String userName;
  final String partnerId;
  final String pairId;

  const MainScreen({
    super.key,
    required this.userName,
    required this.partnerId,
    required this.pairId,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> 
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final List<Widget> _floatingHearts = [];
  late AnimationController _pulseController;
  String? _userId;
  bool _isAppInBackground = false;
  int _currentTabIndex = 0; // 💬 Índice de navegación
  final PageController _pageController = PageController(); // 📱 Controlador de páginas

  @override
  void initState() {
    super.initState();
    _userId = FirebaseAuth.instance.currentUser?.uid;
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    
    // 🔔 Observar cambios de estado de la app
    WidgetsBinding.instance.addObserver(this);
    
    _setupInstantMessaging(); // 🚀 Sistema instantáneo
    _listenForNotifications();
  }

  // 🔔 Detectar cuando la app va a background/foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _isAppInBackground = state != AppLifecycleState.resumed;
    debugPrint('🔔 App state: $state, Background: $_isAppInBackground');
  }

  // 🚀 Sistema de mensajes instantáneos (sin Apple)
  void _setupInstantMessaging() {
    // Escuchar mensajes en tiempo real - INSTANTÁNEO
    FirebaseFirestore.instance
        .collection('pairs')
        .doc(widget.pairId)
        .collection('instant_notifications')
        .where('receiverId', isEqualTo: _userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      
      for (var docChange in snapshot.docChanges) {
        if (docChange.type == DocumentChangeType.added) {
          Map<String, dynamic> notification = docChange.doc.data() as Map<String, dynamic>;
          
          // 🎯 Mostrar notificación INSTANTÁNEA
          _showInstantLocalNotification(notification);
          
          // 📱 Vibración y efectos
          HapticFeedback.lightImpact();
          
          // ✅ Marcar como vista
          docChange.doc.reference.update({'status': 'delivered'});
        }
      }
    });
    
    debugPrint('🚀 Sistema de mensajería instantánea activado');
  }
  
  // 📱 Mostrar notificación local instantánea
  void _showInstantLocalNotification(Map<String, dynamic> notification) async {
    String type = notification['type'] ?? 'abrazo';
    String senderName = notification['senderName'] ?? 'Tu pareja';
    
    // 🔔 Si la app está en background, mostrar notificación nativa
    if (_isAppInBackground) {
      await _showNativeNotification(type, senderName);
      return;
    }
    
    // 🎨 Crear notificación visual hermosa (solo si la app está activa)
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.pink[50],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 💕 Icono animado
              TweenAnimationBuilder(
                duration: Duration(milliseconds: 500),
                tween: Tween<double>(begin: 0.5, end: 1.2),
                builder: (context, double scale, child) {
                  return Transform.scale(
                    scale: scale,
                    child: Text(
                      type == 'abrazo' ? '🤗' : '💋',
                      style: TextStyle(fontSize: 60),
                    ),
                  );
                },
              ),
              SizedBox(height: 16),
              Text(
                type == 'abrazo' ? '¡Abrazo recibido!' : '¡Beso recibido!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.pink[800],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                '$senderName te envió mucho amor 💕',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.pink[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('💕 Recibido', style: TextStyle(color: Colors.pink)),
          ),
        ],
      ),
    );
    
    // 📱 SnackBar de respaldo
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Text(type == 'abrazo' ? '🤗' : '💋', style: TextStyle(fontSize: 24)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                type == 'abrazo' ? '¡Abrazo de $senderName!' : '¡Beso de $senderName!',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.pink,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: Duration(seconds: 3),
      ),
    );
  }

  // Escuchar notificaciones push entrantes
  void _listenForNotifications() {
    // No mostrar notificaciones cuando la app está en primer plano
    // (el sistema solo notificará cuando esté en background/terminated).

    // Mensajes tocados al abrir desde notificación
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🔔 Notificación abierta desde background: ${message.messageId}');
      setState(() {
        _currentTabIndex = 1; // Ir al chat
      });
      _pageController.jumpToPage(1);
    });
  }

  // 🔔 Mostrar notificación nativa cuando la app está en background
  Future<void> _showNativeNotification(String type, String senderName) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'amor_app_channel',
      'Amor App Notifications',
      channelDescription: 'Notificaciones de abrazos y besos',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFE91E63),
      enableVibration: true,
      playSound: true,
    );
    
    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      sound: 'default',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );
    
    String title = type == 'abrazo' ? '🤗 ¡Abrazo recibido!' : '💋 ¡Beso recibido!';
    String body = '$senderName te envió mucho amor 💕';
    
    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      platformChannelSpecifics,
      payload: type,
    );
    
    debugPrint('🔔 Notificación nativa mostrada: $title');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(MessageType type) async {
    try {
      // 🚀 Envío INSTANTÁNEO (nueva implementación)
      await _sendInstantMessage(type);
      
      // 📝 Guardar en historial (como siempre)
      await FirebaseFirestore.instance
          .collection('pairs')
          .doc(widget.pairId)
          .collection('messages')
          .add({
        'senderId': _userId,
        'senderName': widget.userName,
        'type': type.name,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 🎯 Efectos visuales
      _showFloatingHeart();
      _pulseController.forward().then((_) => _pulseController.reset());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Text(type == MessageType.abrazo ? '🤗' : '💋', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text(type == MessageType.abrazo ? '¡Abrazo enviado!' : '¡Beso enviado!'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // 🚀 Envío instantáneo (sin Apple, sin esperas)
  Future<void> _sendInstantMessage(MessageType type) async {
    try {
      // 📨 Crear notificación instantánea
      await FirebaseFirestore.instance
          .collection('pairs')
          .doc(widget.pairId)
          .collection('instant_notifications')
          .add({
        'type': type.name,
        'senderId': _userId,
        'receiverId': widget.partnerId,
        'senderName': widget.userName,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
        'method': 'instant_websocket', // 🚀 Método instantáneo
      });
      
      debugPrint('🚀 Mensaje instantáneo enviado: ${type.name}');
      
      // 📱 Feedback inmediato
      HapticFeedback.mediumImpact();
      
    } catch (e) {
      debugPrint('❌ Error enviando mensaje instantáneo: $e');
      // El sistema instantáneo es nuestro único método ahora
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error enviando mensaje'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showFloatingHeart() {
    final key = UniqueKey();
    final heart = Positioned(
      key: key,
      left: Random().nextDouble() * MediaQuery.of(context).size.width * 0.8,
      bottom: 80,
      child: _AnimatedHeart(
        onEnd: () {
          setState(() {
            _floatingHearts.removeWhere((w) => w.key == key);
          });
        },
      ),
    );

    setState(() {
      _floatingHearts.add(heart);
    });
  }

  Widget _buildFirebaseMessages() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('pairs')
          .doc(widget.pairId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        
        if (docs.isEmpty) {
          return Center(
            child: Text(
              '¡Envía tu primer mensaje de amor! 💕',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          );
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final messageData = docs[index].data();
            final isFromCurrentUser = messageData['senderId'] == _userId;
            final messageType = messageData['type'] == 'abrazo' ? MessageType.abrazo : MessageType.beso;
            final senderName = messageData['senderName'] ?? 'Usuario';

            return Container(
              margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Row(
                mainAxisAlignment: isFromCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isFromCurrentUser ? Color(0xFFE91E63) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          blurRadius: 5,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          messageType == MessageType.abrazo ? '🤗 Abrazo' : '💋 Beso',
                          style: TextStyle(
                            color: isFromCurrentUser ? Colors.white : Color(0xFFE91E63),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!isFromCurrentUser) ...[
                          SizedBox(height: 4),
                          Text(
                            'De: $senderName',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTabIndex == 0 ? '💕 ${widget.userName}' : '💬 Chat'),
        backgroundColor: Color(0xFFE91E63),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentTabIndex = index;
          });
        },
        children: [
          // 💕 Página principal (abrazos y besos)
          _buildMainPage(),
          
          // 💬 Página de chat
          _buildChatPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        onTap: (index) {
          setState(() {
            _currentTabIndex = index;
          });
          _pageController.animateToPage(
            index,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
        backgroundColor: Colors.white,
        selectedItemColor: Color(0xFFE91E63),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite),
            label: 'Amor',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
        ],
      ),
    );
  }

  // 💕 Página principal original
  Widget _buildMainPage() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFE4E8), Color(0xFFFFF8F8)],
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(child: _buildFirebaseMessages()),
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        blurRadius: 10,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 1.0, end: 1.1).animate(
                            CurvedAnimation(parent: _pulseController, curve: Curves.elasticOut),
                          ),
                          child: ElevatedButton(
                            onPressed: () => _sendMessage(MessageType.abrazo),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFFFFB74D),
                              padding: EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('🤗', style: TextStyle(fontSize: 24)),
                                Text('Abrazo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 1.0, end: 1.1).animate(
                            CurvedAnimation(parent: _pulseController, curve: Curves.elasticOut),
                          ),
                          child: ElevatedButton(
                            onPressed: () => _sendMessage(MessageType.beso),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFFE91E63),
                              padding: EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('💋', style: TextStyle(fontSize: 24)),
                                Text('Beso', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ..._floatingHearts,
          ],
        ),
      );
  }

  // 💬 Página de chat en tiempo real
  Widget _buildChatPage() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE4E8), Color(0xFFFFF8F8)],
        ),
      ),
      child: Column(
        children: [
          // 💬 Lista de mensajes
          Expanded(
            child: _buildChatMessages(),
          ),
          // ⌨️ Área de input
          _buildMessageInput(),
        ],
      ),
    );
  }

  // 💬 StreamBuilder para mensajes del chat
  Widget _buildChatMessages() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('pairs')
          .doc(widget.pairId)
          .collection('chat_messages')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}', style: TextStyle(color: Colors.red)),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: Color(0xFFE91E63)),
          );
        }

        final messages = snapshot.data?.docs ?? [];
        
        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('💕', style: TextStyle(fontSize: 60)),
                SizedBox(height: 16),
                Text(
                  '¡Envía tu primer mensaje de amor!',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          reverse: true,
          padding: EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index].data();
            final isMe = message['senderId'] == _userId;
            return _buildMessageBubble(message, isMe);
          },
        );
      },
    );
  }

  // 💬 Burbuja de mensaje individual
  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
    final messageText = message['text'] ?? '';
    final timestamp = message['timestamp'] as Timestamp?;
    final timeString = timestamp != null 
        ? '${timestamp.toDate().hour.toString().padLeft(2, '0')}:${timestamp.toDate().minute.toString().padLeft(2, '0')}'
        : '';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFFE91E63),
              child: Text(
                widget.userName[0].toUpperCase(),
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isMe ? Color(0xFFE91E63) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    messageText,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 16,
                    ),
                  ),
                  if (timeString.isNotEmpty) ...[
                    SizedBox(height: 4),
                    Text(
                      timeString,
                      style: TextStyle(
                        color: isMe ? Colors.white70 : Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isMe) SizedBox(width: 40),
        ],
      ),
    );
  }

  // ⌨️ Área de input para escribir mensajes
  Widget _buildMessageInput() {
    final TextEditingController _messageController = TextEditingController();
    
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ⌨️ Campo de texto
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje de amor...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          SizedBox(width: 8),
          // 📤 Botón enviar
          Container(
            decoration: BoxDecoration(
              color: Color(0xFFE91E63),
              borderRadius: BorderRadius.circular(25),
            ),
            child: IconButton(
              onPressed: () => _sendChatMessage(_messageController.text, _messageController),
              icon: Icon(Icons.send, color: Colors.white),
              tooltip: 'Enviar mensaje',
            ),
          ),
        ],
      ),
    );
  }

  // 📤 Enviar mensaje del chat
  Future<void> _sendChatMessage(String text, TextEditingController controller) async {
    if (text.trim().isEmpty) return;
    
    try {
      // 📝 Guardar mensaje en Firestore
      await FirebaseFirestore.instance
          .collection('pairs')
          .doc(widget.pairId)
          .collection('chat_messages')
          .add({
        'text': text.trim(),
        'senderId': _userId,
        'senderName': widget.userName,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'text',
      });

      // 🔔 Crear notificación dirigida a la pareja (para FCM)
      await FirebaseFirestore.instance
          .collection('notifications')
          .add({
        'to': widget.partnerId,
        'title': 'Nuevo mensaje 💬',
        'body': text.trim(),
        'type': 'chat_message',
        'senderId': _userId,
        'senderName': widget.userName,
        'pairId': widget.pairId,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending', // Cloud Function enviará push y cambiará a 'sent'
      });
      
      // 🧹 Limpiar campo de texto
      controller.clear();
      
      // 📱 Feedback haptic
      HapticFeedback.lightImpact();
      
      debugPrint('💬 Mensaje enviado: $text');
      
    } catch (e) {
      debugPrint('❌ Error enviando mensaje: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error enviando mensaje'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _AnimatedHeart extends StatefulWidget {
  final VoidCallback onEnd;

  const _AnimatedHeart({super.key, required this.onEnd});

  @override
  _AnimatedHeartState createState() => _AnimatedHeartState();
}

class _AnimatedHeartState extends State<_AnimatedHeart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(seconds: 3),
      vsync: this,
    );

    _animation = Tween<double>(
      begin: 0,
      end: -300,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Interval(0.7, 1.0),
    ));

    _controller.forward().then((_) => widget.onEnd());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _animation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Text(
              '❤️',
              style: TextStyle(fontSize: 24),
            ),
          ),
        );
      },
    );
  }
}
