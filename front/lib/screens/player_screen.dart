import 'dart:convert';
import 'dart:math';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
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
            _player = _player!.copyWith(currHp: data['value']);
          } else if (data['stat_type'] == 'stam') {
            _player = _player!.copyWith(currStam: data['value']);
          }
        });
      }
    });

    _socket.on('player_updated', (data) {
      if (mounted && data['player_id'] == _player!.id) {
        final field = data['field'];
        final value = data['value'];
        setState(() {
          if (field == 'last_dice_roll') _lastRoll = value;
          _player = _player!.copyWith(
            playerName: field == 'player_name' ? value : null,
            power: field == 'power' ? value : null,
            powerDescription: field == 'power_description' ? value : null,
            sex: field == 'sex' ? value : null,
            physicalDescription: field == 'physical_description' ? value : null,
            currHp: field == 'curr_hp' ? value : null,
            maxHp: field == 'max_hp' ? value : null,
            currStam: field == 'curr_stam' ? value : null,
            maxStam: field == 'max_stam' ? value : null,
            lastDiceRoll: field == 'last_dice_roll' ? value : null,
            copper: field == 'copper' ? value : null,
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

  void _downloadPlayerJson() {
    if (_player == null) return;

    final playerData = {
      'id': _player!.id,
      'player_name': _player!.playerName,
      'power': _player!.power,
      'power_description': _player!.powerDescription,
      'sex': _player!.sex,
      'physical_description': _player!.physicalDescription,
      'curr_hp': _player!.currHp,
      'max_hp': _player!.maxHp,
      'curr_stam': _player!.currStam,
      'max_stam': _player!.maxStam,
      'last_dice_roll': _player!.lastDiceRoll,
      'copper': _player!.copper,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(playerData);
    final bytes = utf8.encode(jsonString);
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', '${_player!.playerName.replaceAll(' ', '_')}.json')
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  @override
  void dispose() {
    _socket.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatCopper(int copper) {
    final plat = copper ~/ 1000000;
    final gold = (copper % 1000000) ~/ 10000;
    final silver = (copper % 10000) ~/ 100;
    final cop = copper % 100;
    final parts = <String>[];
    if (plat > 0) parts.add('${plat}p');
    if (gold > 0) parts.add('${gold}g');
    if (silver > 0) parts.add('${silver}s');
    parts.add('${cop}c');
    return parts.join(' ');
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
          GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => SendMoneyDialog(
                  playerId: _player!.id,
                  playerCopper: _player!.copper,
                  socket: _socket,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                border: Border.all(color: Colors.red, width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatCopper(_player?.copper ?? 0),
                style: const TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _downloadPlayerJson,
          ),
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
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.assignment, color: Colors.white70, size: 48),
                  iconSize: 48,
                  tooltip: 'Notes',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => PlayerNoteDialog(playerId: _player!.id),
                    );
                  },
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
                  Container(
                    width: 1,
                    color: Colors.red.withOpacity(0.3),
                  ),
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

class PlayerNoteDialog extends StatefulWidget {
  final int playerId;
  const PlayerNoteDialog({super.key, required this.playerId});

  @override
  State<PlayerNoteDialog> createState() => _PlayerNoteDialogState();
}

class _PlayerNoteDialogState extends State<PlayerNoteDialog> {
  final TextEditingController _noteController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    try {
      final content = await ApiService.getNotes(widget.playerId);
      _noteController.text = content;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveNotes() async {
    try {
      await ApiService.saveNotes(widget.playerId, _noteController.text);
    } catch (_) {}
  }

  @override
  void dispose() {
    _saveNotes();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.red),
      ),
      child: SizedBox(
        width: 500,
        height: 500,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'NOTES',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                      letterSpacing: 2,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.red))
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: TextField(
                        controller: _noteController,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Write your notes here...',
                          hintStyle: const TextStyle(color: Colors.white24),
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
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.red, width: 2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class SendMoneyDialog extends StatefulWidget {
  final int playerId;
  final int playerCopper;
  final dynamic socket;
  const SendMoneyDialog({super.key, required this.playerId, required this.playerCopper, required this.socket});

  @override
  State<SendMoneyDialog> createState() => _SendMoneyDialogState();
}

class _SendMoneyDialogState extends State<SendMoneyDialog> {
  final TextEditingController _amountController = TextEditingController();
  List<Map<String, dynamic>> _players = [];
  int? _selectedReceiverId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPlayers();
  }

  Future<void> _loadPlayers() async {
    try {
      final players = await ApiService.getPlayersList();
      if (mounted) {
        setState(() {
          _players = players.where((p) => p['id'] != widget.playerId).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _send() {
    if (_selectedReceiverId == null) return;
    final amount = int.tryParse(_amountController.text) ?? 0;
    if (amount <= 0 || amount > widget.playerCopper) return;

    widget.socket.emit('transfer_money', {
      'sender_id': widget.playerId,
      'receiver_id': _selectedReceiverId,
      'amount': amount,
    });

    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.red),
      ),
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ENVOYER ARGENT',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red, letterSpacing: 2),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const CircularProgressIndicator(color: Colors.red)
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _players.map((player) {
                    final isSelected = _selectedReceiverId == player['id'];
                    return GestureDetector(
                      onTap: () => setState(() => _selectedReceiverId = player['id']),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.red.withValues(alpha: 0.2) : Colors.black,
                          border: Border.all(color: isSelected ? Colors.red : Colors.white24),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          player['player_name'],
                          style: TextStyle(color: isSelected ? Colors.red : Colors.white70),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Montant (cuivre)',
                          hintStyle: const TextStyle(color: Colors.white24),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.black),
                      onPressed: _send,
                      child: const Text('Envoyer'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
