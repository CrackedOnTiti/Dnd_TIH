import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/player.dart';
import '../services/api_service.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  Player? _player;
  bool _loading = true;
  int _selectedDice = 20;
  int _lastRoll = 0;
  final List<int> _diceOptions = [5, 10, 20, 100];

  late io.Socket _socket;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  String _messageMode = 'RP';
  int _hostLastRoll = 0;

  @override
  void initState() {
    super.initState();
    _initSocket();
    _loadPlayer();
  }

  void _initSocket() {
    _socket = io.io(ApiService.baseUrl, <String, dynamic>{
      'transports': ['polling', 'websocket'],
      'autoConnect': true,
    });

    _socket.on('host_rolled', (data) {
      if (mounted) {
        setState(() {
          _hostLastRoll = data['roll'];
        });
      }
    });
  }

  void _setupMessageListener() {
    if (_player == null) return;
    _socket.on('new_message_${_player!.id}', (data) {
      if (mounted && data['sender'] == 'host') {
        setState(() {
          _messages.add(data);
        });
        _scrollToBottom();
      }
    });

    _socket.on('stat_updated', (data) {
      if (mounted && data['player_id'] == _player!.id) {
        setState(() {
          if (data['stat_type'] == 'hp') {
            _player = Player(
              id: _player!.id,
              playerName: _player!.playerName,
              power: _player!.power,
              powerDescription: _player!.powerDescription,
              sex: _player!.sex,
              physicalDescription: _player!.physicalDescription,
              currHp: data['value'],
              maxHp: _player!.maxHp,
              currStam: _player!.currStam,
              maxStam: _player!.maxStam,
              lastDiceRoll: _player!.lastDiceRoll,
            );
          } else if (data['stat_type'] == 'stam') {
            _player = Player(
              id: _player!.id,
              playerName: _player!.playerName,
              power: _player!.power,
              powerDescription: _player!.powerDescription,
              sex: _player!.sex,
              physicalDescription: _player!.physicalDescription,
              currHp: _player!.currHp,
              maxHp: _player!.maxHp,
              currStam: data['value'],
              maxStam: _player!.maxStam,
              lastDiceRoll: _player!.lastDiceRoll,
            );
          }
        });
      }
    });

    _socket.on('player_updated', (data) {
      if (mounted && data['player_id'] == _player!.id) {
        final field = data['field'];
        final value = data['value'];
        setState(() {
          if (field == 'last_dice_roll') {
            _lastRoll = value;
          }
          _player = Player(
            id: _player!.id,
            playerName: field == 'player_name' ? value : _player!.playerName,
            power: field == 'power' ? value : _player!.power,
            powerDescription: field == 'power_description' ? value : _player!.powerDescription,
            sex: field == 'sex' ? value : _player!.sex,
            physicalDescription: field == 'physical_description' ? value : _player!.physicalDescription,
            currHp: field == 'curr_hp' ? value : _player!.currHp,
            maxHp: field == 'max_hp' ? value : _player!.maxHp,
            currStam: field == 'curr_stam' ? value : _player!.currStam,
            maxStam: field == 'max_stam' ? value : _player!.maxStam,
            lastDiceRoll: field == 'last_dice_roll' ? value : _player!.lastDiceRoll,
          );
        });
      }
    });
  }

  Future<void> _loadMessages() async {
    if (_player == null) return;
    try {
      final messages = await ApiService.getMessages(_player!.id);
      if (mounted) {
        setState(() {
          _messages = messages;
        });
        _scrollToBottom();
      }
    } catch (e) {
      // Failed to load messages
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty || _player == null) return;

    final message = {
      'player_id': _player!.id,
      'sender': 'player',
      'content': text,
      'mode': _messageMode,
    };

    _socket.emit('player_message', message);

    setState(() {
      _messages.add(message);
    });

    _messageController.clear();
    _scrollToBottom();
  }

  Future<void> _loadPlayer() async {
    final prefs = await SharedPreferences.getInstance();
    final playerId = prefs.getInt('playerId');

    if (playerId == null) {
      if (mounted) Navigator.pushReplacementNamed(context, '/');
      return;
    }

    try {
      final player = await ApiService.getPlayer(playerId);
      setState(() {
        _player = player;
        _lastRoll = player.lastDiceRoll;
        _loading = false;
      });
      _setupMessageListener();
      _loadMessages();
    } catch (e) {
      if (mounted) Navigator.pushReplacementNamed(context, '/');
    }
  }

  Future<void> _rollDice() async {
    final roll = Random().nextInt(_selectedDice) + 1;
    setState(() => _lastRoll = roll);

    try {
      await ApiService.rollDice(_player!.id, roll);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error saving roll')),
        );
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('playerId');
    if (mounted) Navigator.pushReplacementNamed(context, '/');
  }

  @override
  void dispose() {
    _socket.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.red)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_player?.playerName ?? 'Player'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('Power', _player!.power),
                    const SizedBox(height: 8),
                    _buildInfoRow('Description', _player!.powerDescription),
                    const Divider(),
                    _buildInfoRow('Sex', _player!.sex),
                    const SizedBox(height: 8),
                    _buildInfoRow('Physical', _player!.physicalDescription),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Host Roll Box
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'HOST',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.red,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_hostLastRoll',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // HP and Stamina Bars
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // HP Bar
                          Row(
                      children: [
                        const Icon(Icons.favorite, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        const Text('HP', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Stack(
                            children: [
                              Container(
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.green.withOpacity(0.5)),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: _player!.maxHp > 0 ? _player!.currHp / _player!.maxHp : 0,
                                child: Container(
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                              Container(
                                height: 24,
                                alignment: Alignment.center,
                                child: Text(
                                  '${_player!.currHp} / ${_player!.maxHp}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Stamina Bar
                    Row(
                      children: [
                        const Icon(Icons.bolt, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        const Text('EN', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Stack(
                            children: [
                              Container(
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.blue.withOpacity(0.5)),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: _player!.maxStam > 0 ? _player!.currStam / _player!.maxStam : 0,
                                child: Container(
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                              Container(
                                height: 24,
                                alignment: Alignment.center,
                                child: Text(
                                  '${_player!.currStam} / ${_player!.maxStam}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              height: 400,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  // Left side - Dice roll
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'DICE ROLL',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '$_lastRoll',
                            style: const TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: _diceOptions.map((dice) {
                              final isSelected = _selectedDice == dice;
                              return ChoiceChip(
                                label: Text('d$dice'),
                                selected: isSelected,
                                onSelected: (_) => setState(() => _selectedDice = dice),
                                selectedColor: Colors.red,
                                backgroundColor: const Color(0xFF2A2A2A),
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white70,
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _rollDice,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 48,
                                vertical: 16,
                              ),
                            ),
                            child: const Text(
                              'ROLL',
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Divider
                  Container(
                    width: 1,
                    color: Colors.red.withOpacity(0.3),
                  ),
                  // Right side - Messages
                  Expanded(
                    child: Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'MESSAGES',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              final isHost = msg['sender'] == 'host';

                              return Align(
                                alignment: isHost ? Alignment.centerLeft : Alignment.centerRight,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  constraints: const BoxConstraints(maxWidth: 250),
                                  decoration: BoxDecoration(
                                    color: isHost ? Colors.red.withOpacity(0.2) : Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isHost ? Colors.red : Colors.white24,
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    msg['content'] ?? '',
                                    style: TextStyle(
                                      color: msg['mode'] == '???' ? Colors.red : Colors.white,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: 'Message...',
                                    hintStyle: const TextStyle(color: Colors.white38),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    filled: true,
                                    fillColor: Colors.black,
                                    border: OutlineInputBorder(
                                      borderSide: const BorderSide(color: Colors.red),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: const BorderSide(color: Colors.red),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  border: Border.all(color: Colors.red),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _messageMode,
                                    dropdownColor: Colors.black,
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                    items: const [
                                      DropdownMenuItem(value: 'RP', child: Text('RP/HRP')),
                                      DropdownMenuItem(value: '???', child: Text('???')),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() => _messageMode = value);
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.send, color: Colors.red),
                                onPressed: _sendMessage,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            color: Colors.red,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }
}
