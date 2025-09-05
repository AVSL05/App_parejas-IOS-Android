import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

// Clave global para navegar y mostrar diálogos desde cualquier parte
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Multiplataforma: inicializa con las opciones generadas por FlutterFire
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Inicializa Firebase Messaging y solicita permisos
  await _initFirebaseMessaging();
  // Intenta iniciar sesión anónima si está habilitada
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (e) {
    print('Error con autenticación anónima (necesitas habilitarla en Firebase Console): $e');
  }
  runApp(const AmorApp());
}

Future<void> _initFirebaseMessaging() async {
  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    
    // Intenta obtener el token, pero maneja el error en simulador
    String? token;
    try {
      token = await messaging.getToken();
      print('FCM Token: $token');
    } catch (e) {
      print('Error obteniendo FCM token (normal en simulador): $e');
      token = null;
    }
    
    // Guarda el token en Firestore solo si existe
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && token != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Notificación recibida en foreground: ${message.notification?.title}');
      // Muestra una notificación personalizada cuando la app está abierta
      _showInAppNotification(message);
    });
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notificación abierta desde background/terminated: ${message.notification?.title}');
      // Navega o muestra información relevante
    });
  } catch (e) {
    print('Error inicializando Firebase Messaging: $e');
  }
}

void _showInAppNotification(RemoteMessage message) {
  final title = message.notification?.title ?? 'Nuevo mensaje';
  final body = message.notification?.body ?? 'Tienes un mensaje nuevo';
  final type = message.data['type'] as String?;
  
  // Usa un contexto global para mostrar la notificación
  final context = navigatorKey.currentContext;
  if (context != null) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                type == 'abrazo' ? Icons.favorite : Icons.favorite_border,
                color: type == 'abrazo' ? Colors.pink : Colors.red,
                size: 30,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title)),
            ],
          ),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

class AmorApp extends StatelessWidget {
  const AmorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Amor App',
      theme: ThemeData(
        primarySwatch: Colors.pink,
        primaryColor: Color(0xFFE91E63),
        scaffoldBackgroundColor: Color(0xFFFFF8F8),
        fontFamily: 'SF Pro Display',
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFFFFE4E8),
          foregroundColor: Color(0xFFE91E63),
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFFE91E63),
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            elevation: 2,
          ),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFE4E8),
              Color(0xFFFFF8F8),
              Color(0xFFFFE4E8),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo/Icon area
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.pink.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.favorite,
                    size: 80,
                    color: Color(0xFFE91E63),
                  ),
                ),
                SizedBox(height: 40),
                
                // Welcome text
                Text(
                  '💕 Bienvenido a Amor App 💕',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE91E63),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                Text(
                  'Conecta con tu pareja y envía\nabrazos y besos virtuales',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF8E8E93),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 40),
                
                // Input field
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.pink.withOpacity(0.1),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: '👤 Tu nombre o email',
                      labelStyle: TextStyle(color: Color(0xFF8E8E93)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.person_outline, color: Color(0xFFE91E63)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                  ),
                ),
                SizedBox(height: 30),
                
                // Login button
                Container(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      final name = _nameController.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Por favor, ingresa tu nombre.'),
                            backgroundColor: Color(0xFFE91E63),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ConnectionScreen(userName: name),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFE91E63),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      elevation: 3,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.favorite, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Entrar al Amor',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 40),
                
                // Decorative hearts
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.favorite, color: Color(0xFFE91E63).withOpacity(0.3), size: 16),
                    SizedBox(width: 8),
                    Icon(Icons.favorite, color: Color(0xFFE91E63).withOpacity(0.5), size: 20),
                    SizedBox(width: 8),
                    Icon(Icons.favorite, color: Color(0xFFE91E63), size: 24),
                    SizedBox(width: 8),
                    Icon(Icons.favorite, color: Color(0xFFE91E63).withOpacity(0.5), size: 20),
                    SizedBox(width: 8),
                    Icon(Icons.favorite, color: Color(0xFFE91E63).withOpacity(0.3), size: 16),
                  ],
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
  const ConnectionScreen({Key? key, required this.userName}) : super(key: key);

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final TextEditingController _partnerIdController = TextEditingController();
  String? _userId;
  bool _isLoading = false;
  List<Map<String, dynamic>> _pendingInvitations = [];

  @override
  void initState() {
    super.initState();
    _userId = FirebaseAuth.instance.currentUser?.uid;
    _checkExistingConnection();
    _loadPendingInvitations();
  }

  Future<void> _checkExistingConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPartnerId = prefs.getString('partnerId');
    final savedPairId = prefs.getString('pairId');
    
    if (savedPartnerId != null && savedPairId != null) {
      print('🔄 Verificando conexión existente...');
      
      try {
        final pairDoc = await FirebaseFirestore.instance
            .collection('pairs')
            .doc(savedPairId)
            .get();
            
        if (pairDoc.exists) {
          print('✅ Conexión válida encontrada, navegando a MainScreen...');
          if (mounted) {
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
          return;
        } else {
          print('❌ Conexión guardada no válida, limpiando...');
          await prefs.remove('partnerId');
          await prefs.remove('pairId');
        }
      } catch (e) {
        print('Error verificando conexión guardada: $e');
        await prefs.remove('partnerId');
        await prefs.remove('pairId');
      }
    }
  }

  Future<void> _loadPendingInvitations() async {
    if (_userId == null) return;
    
    try {
      final invitationsSnapshot = await FirebaseFirestore.instance
          .collection('invitations')
          .where('receiverId', isEqualTo: _userId)
          .where('status', isEqualTo: 'pending')
          .get();

      final invitations = <Map<String, dynamic>>[];
      for (var doc in invitationsSnapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        
        // Obtener el nombre del remitente
        final senderDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(data['senderId'])
            .get();
        
        if (senderDoc.exists) {
          data['senderName'] = senderDoc.data()?['name'] ?? 'Usuario desconocido';
        }
        
        invitations.add(data);
      }

      setState(() {
        _pendingInvitations = invitations;
      });
    } catch (e) {
      print('Error cargando invitaciones: $e');
    }
  }

  @override
  void dispose() {
    _partnerIdController.dispose();
    super.dispose();
  }

  Future<void> _restorePartnerId() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPartner = prefs.getString('partnerId');
    if (savedPartner != null && savedPartner.isNotEmpty) {
      setState(() {
        _partnerIdController.text = savedPartner;
      });
    }
  }

  String _computePairId(String a, String b) {
    final list = [a, b]..sort();
    return '${list[0]}_${list[1]}';
  }

  Future<void> _connectWithPartner() async {
    final partner = _partnerIdController.text.trim();
    if (partner.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ingresa el ID de tu pareja'),
          backgroundColor: Color(0xFFE91E63),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }
    
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Usuario no autenticado'),
          backgroundColor: Color(0xFFE91E63),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      print('=== CREANDO CONEXIÓN ===');
      print('UserID: $_userId');
      print('PartnerID: $partner');
      
      // Usar un pairId consistente: ordenar alfabéticamente los IDs
      final sortedIds = [_userId!, partner]..sort();
      final pairId = '${sortedIds[0]}_${sortedIds[1]}';
      print('PairID generado (ordenado): $pairId');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('partnerId', partner);
      await prefs.setString('pairId', pairId);
      
      // Crea/actualiza documento del par con miembros
      await FirebaseFirestore.instance
          .collection('pairs')
          .doc(pairId)
          .set({
        'members': [_userId, partner],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ Documento de pareja creado/actualizado exitosamente');
      print('🔗 PairID final usado: $pairId');

      if (mounted) {
        print('📱 Navegando a MainScreen...');
        // Navegar a la pantalla principal después de conexión exitosa
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MainScreen(
              userName: widget.userName,
              partnerId: partner,
              pairId: pairId,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al conectar: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _sendInvitation() async {
    final partnerId = _partnerIdController.text.trim();
    
    if (partnerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Por favor ingresa el ID de tu pareja'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (partnerId == _userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No puedes enviarte una invitación a ti mismo'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Verificar que el usuario existe
      final partnerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(partnerId)
          .get();

      if (!partnerDoc.exists) {
        throw Exception('Usuario no encontrado');
      }

      // Verificar si ya existe una invitación pendiente
      final existingInvitation = await FirebaseFirestore.instance
          .collection('invitations')
          .where('senderId', isEqualTo: _userId)
          .where('receiverId', isEqualTo: partnerId)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existingInvitation.docs.isNotEmpty) {
        throw Exception('Ya enviaste una invitación a este usuario');
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
        SnackBar(
          content: Text('Invitación enviada exitosamente! 💕'),
          backgroundColor: Colors.green,
        ),
      );

      _partnerIdController.clear();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _acceptInvitation(String invitationId, String senderId, String senderName) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Crear el pairId ordenado alfabéticamente
      final sortedIds = [_userId!, senderId]..sort();
      final pairId = '${sortedIds[0]}_${sortedIds[1]}';

      // Actualizar la invitación como aceptada
      await FirebaseFirestore.instance
          .collection('invitations')
          .doc(invitationId)
          .update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
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
        SnackBar(
          content: Text('Error aceptando invitación: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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

      _loadPendingInvitations(); // Recargar las invitaciones

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invitación rechazada'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error rechazando invitación: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
            colors: [
              Color(0xFFFFE4E8),
              Color(0xFFFFF8F8),
              Color(0xFFFFE4E8),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo/Icon area
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.pink.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.link,
                    size: 80,
                    color: Color(0xFFE91E63),
                  ),
                ),
                SizedBox(height: 40),
                
                // Welcome text
                Text(
                  '💕 Conecta con tu Pareja 💕',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE91E63),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                Text(
                  '¡Hola, ${widget.userName}!\nIngresa el ID de tu pareja para\ncomenzar a enviar amor',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF8E8E93),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 40),
                
                // Your ID display
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.pink.withOpacity(0.1),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.badge, color: Color(0xFFE91E63)),
                          SizedBox(width: 8),
                          Text(
                            'Tu ID única',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFE91E63),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Color(0xFFFFE4E8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _userId ?? "Cargando...",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF8E8E93),
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copiar ID',
                              icon: Icon(Icons.copy, color: Color(0xFFE91E63)),
                              onPressed: (_userId == null || _userId!.isEmpty)
                                  ? null
                                  : () async {
                                      await Clipboard.setData(ClipboardData(text: _userId!));
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('ID copiada al portapapeles'),
                                            backgroundColor: Color(0xFFE91E63),
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Comparte este ID con tu pareja',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 30),
                
                // Partner ID input
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.pink.withOpacity(0.1),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _partnerIdController,
                    decoration: InputDecoration(
                      labelText: '💖 ID de tu pareja',
                      labelStyle: TextStyle(color: Color(0xFF8E8E93)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.person_pin, color: Color(0xFFE91E63)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                  ),
                ),
                
                SizedBox(height: 30),
                
                // Connect button
                Container(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isConnecting ? null : _connectWithPartner,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFE91E63),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      elevation: 3,
                    ),
                    child: _isConnecting
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Conectando...',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.favorite_border, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Conectar con mi Pareja',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                
                SizedBox(height: 40),
                
                // Decorative hearts
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.favorite, color: Color(0xFFE91E63).withOpacity(0.3), size: 16),
                    SizedBox(width: 8),
                    Icon(Icons.favorite, color: Color(0xFFE91E63).withOpacity(0.5), size: 20),
                    SizedBox(width: 8),
                    Icon(Icons.favorite, color: Color(0xFFE91E63), size: 24),
                    SizedBox(width: 8),
                    Icon(Icons.favorite, color: Color(0xFFE91E63).withOpacity(0.5), size: 20),
                    SizedBox(width: 8),
                    Icon(Icons.favorite, color: Color(0xFFE91E63).withOpacity(0.3), size: 16),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final String userName;
  final String partnerId;
  final String pairId;
  
  const MainScreen({
    Key? key, 
    required this.userName,
    required this.partnerId,
    required this.pairId,
  }) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String? _userId;
  List<Message> messageHistory = [];
  List<Widget> _floatingHearts = [];

  @override
  void initState() {
    super.initState();
    print('=== MAIN SCREEN INIT ===');
    print('UserName: ${widget.userName}');
    print('PartnerID: ${widget.partnerId}');
    print('PairID: ${widget.pairId}');
    
    _userId = FirebaseAuth.instance.currentUser?.uid;
    print('Current UserID: $_userId');
    
    _loadMessages();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('messageHistory');
    if (raw != null) {
      setState(() {
        messageHistory = raw.map((e) => Message.fromJson(e)).toList();
      });
    }
  }

  Future<void> sendMessage(MessageType type) async {
    print('=== ENVIANDO MENSAJE ===');
    print('Tipo: ${type.name}');
    print('PairID: ${widget.pairId}');
    print('UserID: $_userId');
    print('UserName: ${widget.userName}');
    
    try {
      // Envía directamente a Firestore usando el pairId proporcionado
      await FirebaseFirestore.instance
          .collection('pairs')
          .doc(widget.pairId)
          .collection('messages')
          .add({
        'type': type.name,
        'senderId': _userId,
        'senderName': widget.userName,
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      print('✅ Mensaje enviado exitosamente a Firestore');
      
      // Envía notificación push a la pareja
      await _sendPushNotificationToPartner(type);

      if (type == MessageType.abrazo) {
        _showFloatingHeart();
      }
      if (type == MessageType.beso) {
        HapticFeedback.heavyImpact();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('¡${type == MessageType.abrazo ? 'Abrazo' : 'Beso'} enviado!'),
          backgroundColor: Colors.pink,
        ),
      );
    } catch (e) {
      print('❌ Error enviando mensaje: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error enviando mensaje: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _sendPushNotificationToPartner(MessageType type) async {
    // Nota: Las notificaciones push requieren un backend seguro
    // Por ahora solo registramos que se envió un mensaje
    print('📲 Notificación local: ${type == MessageType.abrazo ? 'Abrazo' : 'Beso'} enviado');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFE4E8),
              Color(0xFFFFF8F8),
            ],
          ),
        ),
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.8),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.pink.withOpacity(0.2),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.favorite,
                                color: Color(0xFFE91E63),
                                size: 24,
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '¡Hola, ${widget.userName}! 💕',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE91E63),
                                    ),
                                  ),
                                  Text(
                                    'Conectado con tu pareja',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.green,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Disconnect button
                            IconButton(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text('Desconectar'),
                                    content: Text('¿Estás seguro de que quieres desconectarte de tu pareja?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text('Cancelar'),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          final prefs = await SharedPreferences.getInstance();
                                          await prefs.remove('partnerId');
                                          await prefs.remove('pairId');
                                          Navigator.pushAndRemoveUntil(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => ConnectionScreen(userName: widget.userName),
                                            ),
                                            (route) => false,
                                          );
                                        },
                                        child: Text('Desconectar', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              icon: Icon(Icons.logout, color: Color(0xFFE91E63)),
                              tooltip: 'Desconectar',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Action buttons section
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        // Abrazo button
                        Expanded(
                          child: Container(
                            height: 120,
                            child: ElevatedButton(
                              onPressed: () async {
                                await sendMessage(MessageType.abrazo);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFFFF6B9D),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 5,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.favorite, size: 40),
                                  SizedBox(height: 8),
                                  Text(
                                    '🤗 Enviar\nAbrazo',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        // Beso button
                        Expanded(
                          child: Container(
                            height: 120,
                            child: ElevatedButton(
                              onPressed: () async {
                                await sendMessage(MessageType.beso);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFFE91E63),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 5,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.favorite_border, size: 40),
                                  SizedBox(height: 8),
                                  Text(
                                    '💋 Enviar\nBeso',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Messages section
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: 20),
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(25),
                          topRight: Radius.circular(25),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.pink.withOpacity(0.1),
                            blurRadius: 15,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.chat_bubble_outline, color: Color(0xFFE91E63)),
                              SizedBox(width: 8),
                              Text(
                                'Historial de Amor',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFE91E63),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          Expanded(
                            child: _buildFirebaseMessages(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ..._floatingHearts,
          ],
        ),
      ),
    );
  }

  Widget _buildFirebaseMessages() {
    print('=== CONSTRUYENDO STREAM DE MENSAJES ===');
    print('PairID para stream: ${widget.pairId}');
    
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('pairs')
          .doc(widget.pairId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        print('=== STREAM BUILDER CALLBACK ===');
        print('ConnectionState: ${snapshot.connectionState}');
        print('HasError: ${snapshot.hasError}');
        if (snapshot.hasError) {
          print('Error: ${snapshot.error}');
        }
        print('HasData: ${snapshot.hasData}');
        if (snapshot.hasData) {
          final docs = snapshot.data?.docs ?? [];
          print('Docs count: ${docs.length}');
          for (int i = 0; i < docs.length; i++) {
            final doc = docs[i];
            print('Mensaje $i: ${doc.data()}');
          }
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE91E63)),
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 60),
                SizedBox(height: 16),
                Text(
                  'Error: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red),
                ),
              ],
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.favorite_border,
                  size: 60,
                  color: Colors.pink.withOpacity(0.3),
                ),
                SizedBox(height: 16),
                Text(
                  '💕 ¡Conectados!\nAún no hay mensajes de amor\n¡Envía tu primer abrazo o beso!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final d = docs[index].data();
            final typeStr = d['type'] as String? ?? 'abrazo';
            final senderName = d['senderName'] as String? ?? 'Anónimo';
            final senderId = d['senderId'] as String? ?? '';
            final ts = (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
            final type = MessageType.values.firstWhere(
              (e) => e.name == typeStr,
              orElse: () => MessageType.abrazo,
            );
            final isFromMe = senderId == _userId;
            
            return Container(
              margin: EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isFromMe 
                    ? (type == MessageType.abrazo ? Color(0xFFFFE4E8) : Color(0xFFF8E8FF))
                    : (type == MessageType.abrazo ? Color(0xFFE8F5E8) : Color(0xFFE8F0FF)),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: isFromMe 
                      ? (type == MessageType.abrazo ? Colors.pink.withOpacity(0.3) : Colors.purple.withOpacity(0.3))
                      : (type == MessageType.abrazo ? Colors.green.withOpacity(0.3) : Colors.blue.withOpacity(0.3)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isFromMe 
                          ? (type == MessageType.abrazo ? Color(0xFFFF6B9D) : Color(0xFFE91E63))
                          : (type == MessageType.abrazo ? Colors.green : Colors.blue),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      type == MessageType.abrazo ? Icons.favorite : Icons.favorite_border,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${type == MessageType.abrazo ? '🤗 Abrazo' : '💋 Beso'} ${isFromMe ? 'enviado' : 'de $senderName'}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isFromMe ? Color(0xFFE91E63) : Colors.green,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          ts.toLocal().toString().substring(0, 19),
                          style: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 12,
                          ),
                        ),
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
}

class _AnimatedHeart extends StatefulWidget {
  final VoidCallback onEnd;
  const _AnimatedHeart({required this.onEnd});

  @override
  State<_AnimatedHeart> createState() => _AnimatedHeartState();
}

class _AnimatedHeartState extends State<_AnimatedHeart> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 200).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onEnd();
        }
      });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -_animation.value),
          child: Icon(
            Icons.favorite,
            color: Colors.pink,
            size: 40,
          ),
        );
      },
    );
  }
}

enum MessageType { abrazo, beso }

class Message {
  final MessageType type;
  final String sender;
  final DateTime timestamp;

  Message({required this.type, required this.sender, required this.timestamp});

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'sender': sender,
        'timestamp': timestamp.toIso8601String(),
      };

  factory Message.fromMap(Map<String, dynamic> map) => Message(
        type: MessageType.values.firstWhere(
          (e) => e.name == map['type'],
          orElse: () => MessageType.abrazo,
        ),
        sender: map['sender'] as String,
        timestamp: DateTime.parse(map['timestamp'] as String),
      );

  String toJson() => jsonEncode(toMap());
  factory Message.fromJson(String source) => Message.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
