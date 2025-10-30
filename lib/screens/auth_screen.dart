import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:camera/camera.dart';
import 'camera_screen.dart'; // 🔹 lägg till denna import

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _auth = FirebaseAuth.instance;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  String _errorMessage = '';
  bool _isLoading = false; // 🔹 Ny: visar när appen jobbar

  Future<void> _submit() async {
    setState(() {
      _errorMessage = '';
      _isLoading = true;
    });

    try {
      if (_isLogin) {
        await _auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        print('✅ Login success');
      } else {
        await _auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        print('✅ Account created');
      }

      // 🔹 Navigera till kamera-skärmen direkt efter login/signup
      final cameras = await availableCameras();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => CameraScreen(cameras: cameras),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      print('🔥 FirebaseAuth error: ${e.code} - ${e.message}');
      setState(() => _errorMessage = e.message ?? 'Auth error');
    } catch (e) {
      print('❌ Unknown error: $e');
      setState(() => _errorMessage = 'Unexpected error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'KnB Capture Login',
                  style: TextStyle(fontSize: 26, color: Colors.white),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    hintText: 'Email',
                    filled: true,
                    fillColor: Colors.white10,
                    hintStyle: TextStyle(color: Colors.white54),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'Password',
                    filled: true,
                    fillColor: Colors.white10,
                    hintStyle: TextStyle(color: Colors.white54),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 20),
                if (_errorMessage.isNotEmpty)
                  Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 20),

                // 🔹 Laddningsindikator eller knapp
                _isLoading
                    ? const CircularProgressIndicator(color: Colors.blueAccent)
                    : ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                        ),
                        child: Text(_isLogin ? 'Logga in' : 'Skapa konto'),
                      ),

                TextButton(
                  onPressed: () =>
                      setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin
                        ? 'Har du inget konto? Skapa ett'
                        : 'Redan registrerad? Logga in',
                    style: const TextStyle(color: Colors.white70),
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
