import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class PlayerCreateScreen extends StatefulWidget {
  const PlayerCreateScreen({super.key});

  @override
  State<PlayerCreateScreen> createState() => _PlayerCreateScreenState();
}

class _PlayerCreateScreenState extends State<PlayerCreateScreen> {
  final _nameController = TextEditingController();
  final _powerController = TextEditingController();
  final _powerDescController = TextEditingController();
  final _physicalDescController = TextEditingController();
  String? _sex;
  String? _education;
  bool _isCreating = false;

  final List<String> _sexOptions = ['Male', 'Female', 'Other'];
  final List<String> _educationOptions = ['Power Oriented', 'Hand to Hand', 'Weapon'];

  bool get _isFormValid =>
      _nameController.text.isNotEmpty &&
      _powerController.text.isNotEmpty &&
      _powerDescController.text.isNotEmpty &&
      _physicalDescController.text.isNotEmpty &&
      _sex != null &&
      _education != null;

  Future<void> _createPlayer() async {
    if (!_isFormValid) return;

    setState(() => _isCreating = true);

    try {
      final playerId = await ApiService.createPlayer(
        playerName: _nameController.text.trim(),
        power: _powerController.text.trim(),
        powerDescription: _powerDescController.text.trim(),
        sex: _sex!,
        physicalDescription: _physicalDescController.text.trim(),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('playerId', playerId);

      if (mounted) Navigator.pushReplacementNamed(context, '/player');
    } catch (e) {
      setState(() => _isCreating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating player: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _powerController.dispose();
    _powerDescController.dispose();
    _physicalDescController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CREATE PLAYER'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTextField('Name', _nameController),
            const SizedBox(height: 16),
            _buildTextField('Power', _powerController),
            const SizedBox(height: 16),
            _buildTextField('Power Description', _powerDescController),
            const SizedBox(height: 16),
            _buildDropdown('Sex', _sex, _sexOptions, (v) => setState(() => _sex = v)),
            const SizedBox(height: 16),
            _buildDropdown('Education', _education, _educationOptions, (v) => setState(() => _education = v)),
            const SizedBox(height: 16),
            _buildTextField('Physical Description', _physicalDescController, maxLines: 4),
            const SizedBox(height: 32),
            AnimatedOpacity(
              opacity: _isFormValid ? 1.0 : 0.3,
              duration: const Duration(milliseconds: 200),
              child: ElevatedButton(
                onPressed: _isFormValid && !_isCreating ? _createPlayer : null,
                child: _isCreating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('CREATE'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            color: Colors.red,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String? value, List<String> options, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            color: Colors.red,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              hint: const Text('Select...', style: TextStyle(color: Colors.grey)),
              dropdownColor: const Color(0xFF1A1A1A),
              items: options
                  .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
