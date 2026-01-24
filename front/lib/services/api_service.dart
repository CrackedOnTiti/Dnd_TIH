import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/player.dart';

class ApiService {
  static String baseUrl = 'http://localhost:5000';

  static void setBaseUrl(String url) {
    baseUrl = url;
  }

  static String? _hostPassword;

  static void setHostPassword(String password) {
    _hostPassword = password;
  }

  static Future<bool> authHost(String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/host'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'password': password}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        _hostPassword = password;
        return true;
      }
    }
    return false;
  }

  static Future<List<Player>> getPlayers() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/players'),
      headers: {
        if (_hostPassword != null) 'X-Host-Password': _hostPassword!,
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success']) {
        return (data['players'] as List)
            .map((p) => Player.fromJson(p))
            .toList();
      }
    }
    if (response.statusCode == 401) {
      throw Exception('Unauthorized');
    }
    throw Exception('Failed to load players');
  }

  static Future<Player> getPlayer(int playerId) async {
    final response = await http.get(Uri.parse('$baseUrl/api/player/$playerId'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success']) {
        return Player.fromJson(data['player']);
      }
    }
    throw Exception('Failed to load player');
  }

  static Future<int> createPlayer({
    required String playerName,
    required String power,
    required String powerDescription,
    required String sex,
    required String physicalDescription,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/player/create'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'player_name': playerName,
        'power': power,
        'power_description': powerDescription,
        'sex': sex,
        'physical_description': physicalDescription,
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success']) {
        return data['player_id'];
      }
    }
    throw Exception('Failed to create player');
  }

  static Future<void> rollDice(int playerId, int roll) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/player/$playerId/roll'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'roll': roll}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to save roll');
    }
  }

  static Future<List<Map<String, dynamic>>> getMessages(int playerId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/player/$playerId/messages'),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success']) {
        return List<Map<String, dynamic>>.from(data['messages']);
      }
    }
    throw Exception('Failed to load messages');
  }
}
