import 'dart:math';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/player.dart';
import '../services/api_service.dart';

class HostScreen extends StatefulWidget {
  const HostScreen({super.key});

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  List<Player> _players = [];
  bool _loading = true;
  bool _authenticated = false;
  Map<int, int> _flashingRolls = {};
  late io.Socket _socket;
  final _passwordController = TextEditingController();
  int _hostLastRoll = 0;
  int _selectedDice = 20;
  Set<int> _selectedPlayerIds = {};
  final _broadcastMessageController = TextEditingController();
  String _broadcastMode = 'RP';
  Set<int> _unreadPlayerIds = {};

  @override
  void initState() {
    super.initState();
    _initSocket();
  }

  void _initSocket() {
    _socket = io.io(ApiService.baseUrl, <String, dynamic>{
      'transports': ['polling', 'websocket'],
      'autoConnect': true,
    });

    _socket.on('player_rolled', (data) {
      final playerId = data['player_id'];
      final roll = data['roll'];
      setState(() {
        _flashingRolls[playerId] = roll;
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _flashingRolls.remove(playerId);
          });
          _loadPlayers();
        }
      });
    });

    _socket.on('player_created', (data) {
      if (mounted) _loadPlayers();
    });

    _socket.on('stat_updated', (data) {
      if (mounted) _loadPlayers();
    });

    _socket.on('player_updated', (data) {
      if (mounted) _loadPlayers();
    });
  }

  void _setupMessageListeners() {
    for (final player in _players) {
      _socket.off('new_message_${player.id}');
      _socket.on('new_message_${player.id}', (data) {
        if (mounted && data['sender'] == 'player') {
          setState(() {
            _unreadPlayerIds.add(player.id);
          });
        }
      });
    }
  }

  Future<void> _authenticate() async {
    final password = _passwordController.text;
    if (password.length < 4) return; // Don't spam API for short input

    final success = await ApiService.authHost(password);
    if (success) {
      setState(() => _authenticated = true);
      _loadPlayers();
    }
  }

  Future<void> _loadPlayers() async {
    try {
      final players = await ApiService.getPlayers();
      players.sort((a, b) => a.id.compareTo(b.id));
      setState(() {
        _players = players;
        _loading = false;
      });
      _setupMessageListeners();
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _rollDice() {
    final roll = Random().nextInt(_selectedDice) + 1;
    setState(() {
      _hostLastRoll = roll;
    });
    _socket.emit('host_rolled', {
      'roll': roll,
      'dice': _selectedDice,
    });
  }

  @override
  void dispose() {
    _socket.dispose();
    _passwordController.dispose();
    _broadcastMessageController.dispose();
    super.dispose();
  }

  void _sendBroadcastMessage() {
    final text = _broadcastMessageController.text.trim();
    if (text.isEmpty || _selectedPlayerIds.isEmpty) return;

    for (final playerId in _selectedPlayerIds) {
      final message = {
        'player_id': playerId,
        'sender': 'host',
        'content': text,
        'mode': _broadcastMode,
      };
      _socket.emit('host_message', message);
    }

    _broadcastMessageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    // Show password overlay if not authenticated
    if (!_authenticated) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: '****',
                    hintStyle: TextStyle(color: Colors.white24),
                    border: InputBorder.none,
                  ),
                  onChanged: (_) => _authenticate(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Show dashboard if authenticated
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('HOST DASHBOARD'),
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.red, height: 1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPlayers,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // Left side - Player list (50%)
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.red))
                : _players.isEmpty
                    ? const Center(
                        child: Text(
                          'No players yet...',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _players.length,
                        itemBuilder: (context, index) {
                          final player = _players[index];
                          final isFlashing = _flashingRolls.containsKey(player.id);
                          final displayRoll = _flashingRolls[player.id] ?? player.lastDiceRoll;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              border: Border.all(color: Colors.red, width: 1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Left side (50% of cell, split into two 25% columns)
                                  Expanded(
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Left-Left (25%) - Descriptive info
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                player.playerName,
                                                style: const TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                player.power,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.white70,
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              AnimatedDefaultTextStyle(
                                                duration: const Duration(milliseconds: 200),
                                                style: TextStyle(
                                                  fontSize: 32,
                                                  fontWeight: FontWeight.bold,
                                                  color: isFlashing ? Colors.green : Colors.red,
                                                ),
                                                child: Text('$displayRoll'),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Left-Right (25%) - Menu icon
                                        Expanded(
                                          child: Center(
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons.menu,
                                                color: Colors.white,
                                                size: 32,
                                              ),
                                              onPressed: () {
                                                _showPlayerEditDialog(player);
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Right column - HP & Stamina controls
                                  Expanded(
                                    child: Column(
                                      children: [
                                        _buildStatRow(
                                          player: player,
                                          label: 'HP',
                                          curr: player.currHp,
                                          max: player.maxHp,
                                          statType: 'hp',
                                          color: Colors.green,
                                        ),
                                        const SizedBox(height: 12),
                                        _buildStatRow(
                                          player: player,
                                          label: 'STAM',
                                          curr: player.currStam,
                                          max: player.maxStam,
                                          statType: 'stam',
                                          color: Colors.blue,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          // Right side - Main panel (50%)
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: Colors.red, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Broadcast message input row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _broadcastMessageController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Broadcast message...',
                            hintStyle: const TextStyle(color: Colors.white38),
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
                          onSubmitted: (_) => _sendBroadcastMessage(),
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
                            value: _broadcastMode,
                            dropdownColor: Colors.black,
                            style: const TextStyle(color: Colors.white),
                            items: const [
                              DropdownMenuItem(value: 'RP', child: Text('RP')),
                              DropdownMenuItem(value: '???', child: Text('???')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _broadcastMode = value);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.red),
                        onPressed: _sendBroadcastMessage,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Player checkboxes row
                  SizedBox(
                    height: 40,
                    child: Center(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: _players.map((player) {
                            final isSelected = _selectedPlayerIds.contains(player.id);
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedPlayerIds.remove(player.id);
                                    } else {
                                      _selectedPlayerIds.add(player.id);
                                    }
                                  });
                                },
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.red : Colors.black,
                                    border: Border.all(color: Colors.red, width: 1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                                      : null,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Player buttons row
                  SizedBox(
                    height: 50,
                    child: Center(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: _players.map((player) {
                          final hasUnread = _unreadPlayerIds.contains(player.id);
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black,
                                border: Border.all(
                                  color: hasUnread ? Colors.green : Colors.red,
                                  width: hasUnread ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: TextButton(
                                onPressed: () {
                                  setState(() {
                                    _unreadPlayerIds.remove(player.id);
                                  });
                                  _showPlayerChatDialog(player);
                                },
                                child: Text(
                                  player.playerName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Host dice roll section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _rollDice,
                        child: const Text('Roll'),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '$_hostLastRoll',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border.all(color: Colors.red),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _selectedDice,
                            dropdownColor: Colors.black,
                            style: const TextStyle(color: Colors.white),
                            items: const [
                              DropdownMenuItem(value: 5, child: Text('d5')),
                              DropdownMenuItem(value: 10, child: Text('d10')),
                              DropdownMenuItem(value: 20, child: Text('d20')),
                              DropdownMenuItem(value: 100, child: Text('d100')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedDice = value);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Player dice roll cubes
                  SizedBox(
                    height: 100,
                    child: Center(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: _players.map((player) {
                            final isFlashing = _flashingRolls.containsKey(player.id);
                            final displayRoll = _flashingRolls[player.id] ?? player.lastDiceRoll;

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Column(
                                children: [
                                  // Cube with dice roll
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      border: Border.all(color: Colors.red, width: 1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: AnimatedDefaultTextStyle(
                                        duration: const Duration(milliseconds: 200),
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: isFlashing ? Colors.green : Colors.white,
                                        ),
                                        child: Text('$displayRoll'),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  // Player name
                                  SizedBox(
                                    width: 60,
                                    child: Text(
                                      player.playerName,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white70,
                                      ),
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPlayerChatDialog(Player player) {
    showDialog(
      context: context,
      builder: (context) => PlayerChatDialog(
        player: player,
        socket: _socket,
      ),
    );
  }

  void _showPlayerEditDialog(Player player) {
    showDialog(
      context: context,
      builder: (context) => PlayerEditDialog(
        player: player,
        onUpdate: (field, value) {
          _socket.emit('update_player_field', {
            'player_id': player.id,
            'field': field,
            'value': value,
          });
          _loadPlayers();
        },
      ),
    );
  }

  Widget _buildStatRow({
    required Player player,
    required String label,
    required int curr,
    required int max,
    required String statType,
    required Color color,
  }) {
    return StatRowWidget(
      curr: curr,
      max: max,
      statType: statType,
      playerId: player.id,
      onUpdate: _updatePlayerStat,
      color: color,
    );
  }

  void _updatePlayerStat(int playerId, String statType, int value) {
    _socket.emit('update_stat', {
      'player_id': playerId,
      'stat_type': statType,
      'value': value,
    });
  }
}

class PlayerEditDialog extends StatefulWidget {
  final Player player;
  final Function(String field, dynamic value) onUpdate;

  const PlayerEditDialog({
    super.key,
    required this.player,
    required this.onUpdate,
  });

  @override
  State<PlayerEditDialog> createState() => _PlayerEditDialogState();
}

class _PlayerEditDialogState extends State<PlayerEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _powerController;
  late TextEditingController _powerDescController;
  late TextEditingController _sexController;
  late TextEditingController _physDescController;
  late TextEditingController _currHpController;
  late TextEditingController _maxHpController;
  late TextEditingController _currStamController;
  late TextEditingController _maxStamController;
  late TextEditingController _lastRollController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.player.playerName);
    _powerController = TextEditingController(text: widget.player.power);
    _powerDescController = TextEditingController(text: widget.player.powerDescription);
    _sexController = TextEditingController(text: widget.player.sex);
    _physDescController = TextEditingController(text: widget.player.physicalDescription);
    _currHpController = TextEditingController(text: '${widget.player.currHp}');
    _maxHpController = TextEditingController(text: '${widget.player.maxHp}');
    _currStamController = TextEditingController(text: '${widget.player.currStam}');
    _maxStamController = TextEditingController(text: '${widget.player.maxStam}');
    _lastRollController = TextEditingController(text: '${widget.player.lastDiceRoll}');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _powerController.dispose();
    _powerDescController.dispose();
    _sexController.dispose();
    _physDescController.dispose();
    _currHpController.dispose();
    _maxHpController.dispose();
    _currStamController.dispose();
    _maxStamController.dispose();
    _lastRollController.dispose();
    super.dispose();
  }

  void _submitField(String field, String value, {bool isInt = false}) {
    final val = isInt ? int.tryParse(value) ?? 0 : value;
    widget.onUpdate(field, val);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.red, width: 1),
      ),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'EDIT PLAYER',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildEditField('Name', _nameController, 'player_name'),
              _buildEditField('Power', _powerController, 'power'),
              _buildEditField('Power Description', _powerDescController, 'power_description'),
              _buildEditField('Sex', _sexController, 'sex'),
              _buildEditField('Physical Description', _physDescController, 'physical_description'),
              const Divider(color: Colors.red),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildEditField('Curr HP', _currHpController, 'curr_hp', isInt: true)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildEditField('Max HP', _maxHpController, 'max_hp', isInt: true)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _buildEditField('Curr Stam', _currStamController, 'curr_stam', isInt: true)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildEditField('Max Stam', _maxStamController, 'max_stam', isInt: true)),
                ],
              ),
              _buildEditField('Last Dice Roll', _lastRollController, 'last_dice_roll', isInt: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditField(String label, TextEditingController controller, String field, {bool isInt = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
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
            keyboardType: isInt ? TextInputType.number : TextInputType.text,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
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
            onSubmitted: (value) => _submitField(field, value, isInt: isInt),
          ),
        ],
      ),
    );
  }
}

class StatRowWidget extends StatefulWidget {
  final int curr;
  final int max;
  final String statType;
  final int playerId;
  final Function(int, String, int) onUpdate;
  final Color color;

  const StatRowWidget({
    super.key,
    required this.curr,
    required this.max,
    required this.statType,
    required this.playerId,
    required this.onUpdate,
    required this.color,
  });

  @override
  State<StatRowWidget> createState() => _StatRowWidgetState();
}

class _StatRowWidgetState extends State<StatRowWidget> {
  late TextEditingController _controller;
  late double _sliderValue;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.curr}');
    _sliderValue = widget.curr.toDouble();
  }

  @override
  void didUpdateWidget(StatRowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.curr != widget.curr) {
      _controller.text = '${widget.curr}';
      _sliderValue = widget.curr.toDouble();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateValue(int value) {
    setState(() {
      _sliderValue = value.toDouble();
      _controller.text = '$value';
    });
    widget.onUpdate(widget.playerId, widget.statType, value);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Display: curr/max
        SizedBox(
          width: 60,
          child: Text(
            '${_sliderValue.toInt()}/${widget.max}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        // Input box
        SizedBox(
          width: 50,
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              isDense: true,
              filled: true,
              fillColor: Colors.black,
              border: OutlineInputBorder(
                borderSide: BorderSide(color: widget.color),
                borderRadius: BorderRadius.circular(4),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: widget.color),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onSubmitted: (value) {
              final newValue = int.tryParse(value);
              if (newValue != null && newValue >= 0 && newValue <= widget.max) {
                _updateValue(newValue);
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        // Slider
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: widget.color,
              inactiveTrackColor: widget.color.withOpacity(0.3),
              thumbColor: widget.color,
              overlayColor: widget.color.withOpacity(0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: _sliderValue,
              min: 0,
              max: widget.max.toDouble(),
              onChanged: (value) {
                _updateValue(value.toInt());
              },
            ),
          ),
        ),
      ],
    );
  }
}

class PlayerChatDialog extends StatefulWidget {
  final Player player;
  final io.Socket socket;

  const PlayerChatDialog({
    super.key,
    required this.player,
    required this.socket,
  });

  @override
  State<PlayerChatDialog> createState() => _PlayerChatDialogState();
}

class _PlayerChatDialogState extends State<PlayerChatDialog> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  String _selectedMode = 'RP';

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    widget.socket.on('new_message_${widget.player.id}', (data) {
      if (mounted && data['sender'] != 'host') {
        setState(() {
          _messages.add(data);
        });
        _scrollToBottom();
      }
    });
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await ApiService.getMessages(widget.player.id);
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
    if (text.isEmpty) return;

    final message = {
      'player_id': widget.player.id,
      'sender': 'host',
      'content': text,
      'mode': _selectedMode,
    };

    widget.socket.emit('host_message', message);

    setState(() {
      _messages.add(message);
    });

    _messageController.clear();
    _scrollToBottom();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    widget.socket.off('new_message_${widget.player.id}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.red, width: 1),
      ),
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.player.playerName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Colors.red),
            // Messages area
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isHost = msg['sender'] == 'host';

                  return Align(
                    alignment: isHost ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      constraints: const BoxConstraints(maxWidth: 350),
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
            const SizedBox(height: 8),
            // Input area
            Row(
              children: [
                // Text input
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: const TextStyle(color: Colors.white38),
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
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                // Mode dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: Colors.red),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedMode,
                      dropdownColor: Colors.black,
                      style: const TextStyle(color: Colors.white),
                      items: const [
                        DropdownMenuItem(value: 'RP', child: Text('RP')),
                        DropdownMenuItem(value: '???', child: Text('???')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedMode = value);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Send button
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.red),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
