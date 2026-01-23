class Player {
  final int id;
  final String playerName;
  final String power;
  final String powerDescription;
  final String sex;
  final String physicalDescription;
  final int currHp;
  final int maxHp;
  final int currStam;
  final int maxStam;
  final int lastDiceRoll;

  Player({
    required this.id,
    required this.playerName,
    required this.power,
    required this.powerDescription,
    required this.sex,
    required this.physicalDescription,
    required this.currHp,
    required this.maxHp,
    required this.currStam,
    required this.maxStam,
    required this.lastDiceRoll,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'],
      playerName: json['player_name'],
      power: json['power'],
      powerDescription: json['power_description'],
      sex: json['sex'],
      physicalDescription: json['physical_description'],
      currHp: json['curr_hp'],
      maxHp: json['max_hp'],
      currStam: json['curr_stam'],
      maxStam: json['max_stam'],
      lastDiceRoll: json['last_dice_roll'],
    );
  }
}
