import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
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
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
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
  const ConnectionScreen({required this.userName});

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
        print('Error verificando conexión: $e');
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
        invitations.add(data);
      }

      if (mounted) {
        setState(() {
          _pendingInvitations = invitations;
        });
      }
    } catch (e) {
      print('Error cargando invitaciones: $e');
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
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _userId ?? ''));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('ID copiado'), backgroundColor: Colors.green),
                          );
                        },
                        child: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _userId ?? 'Cargando...',
                                  style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.blue[800], fontWeight: FontWeight.bold),
                                ),
                              ),
                              Icon(Icons.copy, size: 16, color: Colors.blue[600]),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text('Comparte este ID con tu pareja', style: TextStyle(fontSize: 11, color: Colors.blue[600])),
                    ],
                  ),
                ),
                
                SizedBox(height: 30),
                
                // Invitaciones pendientes
                if (_pendingInvitations.isNotEmpty) ...[
                  Text(
                    'Invitaciones Pendientes',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFD81B60)),
                  ),
                  SizedBox(height: 15),
                  
                  ..._pendingInvitations.map((invitation) => Container(
                    margin: EdgeInsets.only(bottom: 10),
                    padding: EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 5,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Invitación de ${invitation['senderName']}',
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
                                  invitation['id'],
                                  invitation['senderId'],
                                  invitation['senderName'],
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
                                onPressed: _isLoading ? null : () {
                                  // Rechazar invitación
                                },
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
                  )).toList(),
                ],
                
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
    required this.userName,
    required this.partnerId,
    required this.pairId,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  final List<Widget> _floatingHearts = [];
  late AnimationController _pulseController;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _userId = FirebaseAuth.instance.currentUser?.uid;
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(MessageType type) async {
    try {
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

      _showFloatingHeart();
      _pulseController.forward().then((_) => _pulseController.reset());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(type == MessageType.abrazo ? '🤗 ¡Abrazo enviado!' : '💋 ¡Beso enviado!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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
        title: Text('💕 ${widget.userName}'),
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
      body: Container(
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
      ),
    );
  }
}

class _AnimatedHeart extends StatefulWidget {
  final VoidCallback onEnd;

  const _AnimatedHeart({required this.onEnd});

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
