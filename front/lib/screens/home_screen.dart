import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _serverController = TextEditingController();
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
    _setupDragDrop();
  }

  void _setupDragDrop() {
    html.document.onDragOver.listen((e) {
      e.preventDefault();
      if (!_isDragging && mounted) setState(() => _isDragging = true);
    });
    html.document.onDragLeave.listen((e) {
      if (_isDragging && mounted) setState(() => _isDragging = false);
    });
    html.document.onDrop.listen((e) {
      e.preventDefault();
      if (mounted) setState(() => _isDragging = false);
      final files = e.dataTransfer.files;
      if (files != null && files.isNotEmpty) {
        final reader = html.FileReader();
        reader.onLoadEnd.listen((_) {
          try {
            final json = jsonDecode(reader.result as String);
            final playerId = json['id'];
            if (playerId != null && playerId is int) {
              _loginWithJson(playerId);
            } else {
              _showError('Invalid JSON: missing player id');
            }
          } catch (_) {
            _showError('Failed to parse JSON file');
          }
        });
        reader.readAsText(files[0]);
      }
    });
  }

  Future<void> _loginWithJson(int playerId) async {
    await _saveServerUrl();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('playerId', playerId);
    if (mounted) Navigator.pushReplacementNamed(context, '/player');
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('serverUrl') ?? 'http://localhost:5000';
    _serverController.text = savedUrl;
    ApiService.setBaseUrl(savedUrl);
  }

  Future<void> _saveServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverUrl', _serverController.text);
    ApiService.setBaseUrl(_serverController.text);
  }

  Future<void> _continuer() async {
    await _saveServerUrl();
    final prefs = await SharedPreferences.getInstance();
    final playerId = prefs.getInt('playerId');
    if (playerId != null && mounted) {
      Navigator.pushReplacementNamed(context, '/player');
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (_isDragging)
            Container(
              color: Colors.red.withValues(alpha: 0.15),
              child: const Center(
                child: Text(
                  'Drop player JSON here',
                  style: TextStyle(fontSize: 24, color: Colors.red),
                ),
              ),
            ),
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
                      'v0.0.2',
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _serverController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Server URL',
                        labelStyle: const TextStyle(color: Colors.red),
                        hintText: 'http://192.168.1.14:5000',
                        hintStyle: const TextStyle(color: Colors.white24),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        filled: true,
                        fillColor: const Color(0xFF1A1A1A),
                        border: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.red),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.red),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      onChanged: (_) => _saveServerUrl(),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _continuer,
                      child: const Text('Continuer'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        await _saveServerUrl();
                        if (mounted) Navigator.pushNamed(context, '/player/create');
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
              onTap: () async {
                await _saveServerUrl();
                if (mounted) Navigator.pushNamed(context, '/host');
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
