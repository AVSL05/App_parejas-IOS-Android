import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const AmorApp());
}

class AmorApp extends StatelessWidget {
  const AmorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
  List<Message> messageHistory = [];
  List<Widget> _floatingHearts = [];

  @override
  void initState() {
    super.initState();
    _userId = const Uuid().v4();
    _loadMessages();
  }

  @override
  void dispose() {
    _partnerIdController.dispose();
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

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'messageHistory',
      messageHistory.map((m) => m.toJson()).toList(),
    );
  }

  Future<void> sendMessage(MessageType type) async {
    // Cuando Firebase esté configurado, descomenta e implementa:
    // await FirebaseFirestore.instance.collection('mensajes').add({
    //   'sender': widget.userName,
    //   'type': type,
    //   'timestamp': FieldValue.serverTimestamp(),
    // });

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
                        labelText: 'ID de tu pareja (pídela o compártela)',
                      ),
                    ),
                    const SizedBox(height: 20),
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
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: messageHistory.length,
                  itemBuilder: (context, index) {
                    final msg = messageHistory[index];
                    return ListTile(
                      leading: Icon(
                        msg.type == MessageType.abrazo ? Icons.favorite : Icons.favorite_border,
                        color: msg.type == MessageType.abrazo ? Colors.pink : Colors.red,
                      ),
                      title: Text('${msg.type == MessageType.abrazo ? 'Abrazo' : 'Beso'} enviado'),
                      subtitle: Text('Fecha: ${msg.timestamp.toLocal().toString().substring(0, 19)}'),
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
                      onPressed: () => sendMessage(MessageType.abrazo),
                      child: const Text('Enviar Abrazo'),
                    ),
                    ElevatedButton(
                      onPressed: () => sendMessage(MessageType.beso),
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
