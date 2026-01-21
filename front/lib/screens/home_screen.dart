import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _continuer() async {
    final prefs = await SharedPreferences.getInstance();
    final playerId = prefs.getInt('playerId');
    if (playerId != null && mounted) {
      Navigator.pushReplacementNamed(context, '/player');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.network(
                      'icons/Logo-redTeeth.png',
                      height: 180,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'v0.0.1',
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 64),
                    ElevatedButton(
                      onPressed: _continuer,
                      child: const Text('Continuer'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pushNamed(context, '/player/create');
                      },
                      child: const Text('Nouveau Joueur'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: GestureDetector(
              onTap: () {
                Navigator.pushNamed(context, '/host');
              },
              child: const Text(
                'Cracked',
                style: TextStyle(
                  fontSize: 6,
                  color: Colors.white24,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
