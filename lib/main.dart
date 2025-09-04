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
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre o Email',
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                final name = _nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Por favor, ingresa tu nombre.')),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MainScreen(userName: name),
                  ),
                );
              },
              child: const Text('Entrar'),
            ),
          ],
        ),
      ),
    );
  }
}


class MainScreen extends StatefulWidget {
  final String userName;
  const MainScreen({Key? key, required this.userName}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _partnerIdController = TextEditingController();
  String? _userId;
  String? _pairId;
  List<Message> messageHistory = [];
  List<Widget> _floatingHearts = [];

  @override
  void initState() {
    super.initState();
    _userId = FirebaseAuth.instance.currentUser?.uid;
    _restorePartnerId();
    _loadMessages();
  }

  @override
  void dispose() {
    _partnerIdController.dispose();
    super.dispose();
  }

  Future<void> _restorePartnerId() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPartner = prefs.getString('partnerId');
    if (savedPartner != null && savedPartner.isNotEmpty && _userId != null) {
      setState(() {
        _partnerIdController.text = savedPartner;
        _pairId = _computePairId(_userId!, savedPartner);
      });
    }
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

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'messageHistory',
      messageHistory.map((m) => m.toJson()).toList(),
    );
  }

  Future<void> sendMessage(MessageType type) async {
    // Si hay emparejamiento, envía a Firestore; si no, usa historial local
    if (_pairId != null) {
      await FirebaseFirestore.instance
          .collection('pairs')
          .doc(_pairId)
          .collection('messages')
          .add({
        'type': type.name,
        'senderId': _userId,
        'senderName': widget.userName,
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      // Envía notificación push a la pareja
      await _sendPushNotificationToPartner(type);
    } else {
      setState(() {
        messageHistory.insert(
          0,
          Message(
            type: type,
            sender: widget.userName,
            timestamp: DateTime.now(),
          ),
        );
      });
      await _saveMessages();
    }

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
  }

  Future<void> _sendPushNotificationToPartner(MessageType type) async {
    if (_partnerIdController.text.trim().isEmpty) return;
    
    try {
      // Obtén el token FCM de tu pareja desde Firestore
      final partnerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_partnerIdController.text.trim())
          .get();
      
      if (!partnerDoc.exists) return;
      
      final partnerToken = partnerDoc.data()?['fcmToken'] as String?;
      if (partnerToken == null) return;

      // Crea la notificación personalizada
      final messageTitle = type == MessageType.abrazo 
          ? '🤗 ¡Recibiste un abrazo!' 
          : '💋 ¡Recibiste un beso!';
      final messageBody = '${widget.userName} te envió ${type == MessageType.abrazo ? 'un abrazo' : 'un beso'} 💕';

      // Guarda la notificación para enviarla (esto normalmente se haría desde un backend)
      await FirebaseFirestore.instance.collection('notifications').add({
        'token': partnerToken,
        'title': messageTitle,
        'body': messageBody,
        'data': {
          'type': type.name,
          'senderName': widget.userName,
          'senderId': _userId,
        },
        'timestamp': FieldValue.serverTimestamp(),
        'sent': false,
      });
      
    } catch (e) {
      print('Error enviando notificación: $e');
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

  String _computePairId(String a, String b) {
    final list = [a, b]..sort();
    return '${list[0]}_${list[1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Bienvenido, ${widget.userName}')),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _partnerIdController,
                      decoration: const InputDecoration(
                        labelText: 'ID de tu pareja (UID de Firebase)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Tu ID única: ${_userId ?? ""}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copiar ID',
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: (_userId == null || _userId!.isEmpty)
                              ? null
                              : () async {
                                  await Clipboard.setData(ClipboardData(text: _userId!));
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('ID copiada al portapapeles')),
                                    );
                                  }
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            final partner = _partnerIdController.text.trim();
                            if (partner.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Ingresa el ID de tu pareja')),
                              );
                              return;
                            }
                            if (_userId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Usuario no autenticado')),
                              );
                              return;
                            }
                            final pid = _computePairId(_userId!, partner);
                            setState(() => _pairId = pid);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('partnerId', partner);
                            // Crea/actualiza documento del par con miembros
                            await FirebaseFirestore.instance
                                .collection('pairs')
                                .doc(pid)
                                .set({
                              'members': [_userId, partner],
                              'updatedAt': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Pareja conectada')),
                              );
                            }
                          },
                          icon: const Icon(Icons.link),
                          label: const Text('Conectar'),
                        ),
                        const SizedBox(width: 12),
                        if (_pairId != null)
                          Text('Pair ID listo', style: TextStyle(color: Colors.green[700], fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _pairId == null
                    ? ListView.builder(
                        itemCount: messageHistory.length,
                        itemBuilder: (context, index) {
                          final msg = messageHistory[index];
                          return ListTile(
                            leading: Icon(
                              msg.type == MessageType.abrazo ? Icons.favorite : Icons.favorite_border,
                              color: msg.type == MessageType.abrazo ? Colors.pink : Colors.red,
                            ),
                            title: Text('${msg.type == MessageType.abrazo ? 'Abrazo' : 'Beso'} (local) enviado'),
                            subtitle: Text('Fecha: ${msg.timestamp.toLocal().toString().substring(0, 19)}'),
                          );
                        },
                      )
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('pairs')
                            .doc(_pairId)
                            .collection('messages')
                            .orderBy('timestamp', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError) {
                            return Center(child: Text('Error: ${snapshot.error}'));
                          }
                          final docs = snapshot.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return const Center(child: Text('Aún no hay mensajes'));
                          }
                          return ListView.builder(
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final d = docs[index].data();
                              final typeStr = d['type'] as String? ?? 'abrazo';
                              final senderName = d['senderName'] as String? ?? 'Anónimo';
                              final ts = (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
                              final type = MessageType.values.firstWhere(
                                (e) => e.name == typeStr,
                                orElse: () => MessageType.abrazo,
                              );
                              return ListTile(
                                leading: Icon(
                                  type == MessageType.abrazo ? Icons.favorite : Icons.favorite_border,
                                  color: type == MessageType.abrazo ? Colors.pink : Colors.red,
                                ),
                                title: Text('${type == MessageType.abrazo ? 'Abrazo' : 'Beso'} de $senderName'),
                                subtitle: Text('Fecha: ${ts.toLocal().toString().substring(0, 19)}'),
                              );
                            },
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        if (_pairId == null) {
                          // Permite uso local si no hay pareja, para probar
                          await sendMessage(MessageType.abrazo);
                        } else {
                          await sendMessage(MessageType.abrazo);
                        }
                      },
                      child: const Text('Enviar Abrazo'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (_pairId == null) {
                          await sendMessage(MessageType.beso);
                        } else {
                          await sendMessage(MessageType.beso);
                        }
                      },
                      child: const Text('Enviar Beso'),
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
