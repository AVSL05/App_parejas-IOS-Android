import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MainScreen(userName: _nameController.text),
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
  List<Map<String, String>> messageHistory = [];
  List<Widget> _floatingHearts = [];

  @override
  void initState() {
    super.initState();
    _userId = const Uuid().v4();
  }

  Future<void> sendMessage(String type) async {
    // Cuando Firebase esté configurado, descomenta e implementa:
    // await FirebaseFirestore.instance.collection('mensajes').add({
    //   'sender': widget.userName,
    //   'type': type,
    //   'timestamp': FieldValue.serverTimestamp(),
    // });

    setState(() {
      messageHistory.insert(0, {
        'type': type,
        'sender': widget.userName,
        'timestamp': DateTime.now().toIso8601String(),
      });
    });

    if (type == 'abrazo') {
      _showFloatingHeart();
    }
    if (type == 'beso') {
      HapticFeedback.heavyImpact();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('¡${type == 'abrazo' ? 'Abrazo' : 'Beso'} enviado!'),
        backgroundColor: Colors.pink,
      ),
    );
  }

  void _showFloatingHeart() {
    final heart = Positioned(
      left: Random().nextDouble() * MediaQuery.of(context).size.width * 0.8,
      bottom: 80,
      child: _AnimatedHeart(
        onEnd: () {
          setState(() {
            if (_floatingHearts.isNotEmpty) {
              _floatingHearts.removeAt(0);
            }
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
                    Text('Tu ID única: ${_userId ?? ""}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                        msg['type'] == 'abrazo' ? Icons.favorite : Icons.favorite_border,
                        color: msg['type'] == 'abrazo' ? Colors.pink : Colors.red,
                      ),
                      title: Text('${msg['type'] == 'abrazo' ? 'Abrazo' : 'Beso'} enviado'),
                      subtitle: Text('Fecha: ${msg['timestamp']!.substring(0, 19).replaceFirst("T", " ")}'),
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
                      onPressed: () => sendMessage('abrazo'),
                      child: const Text('Enviar Abrazo'),
                    ),
                    ElevatedButton(
                      onPressed: () => sendMessage('beso'),
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
