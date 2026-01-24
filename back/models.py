from app import db

class Player(db.Model):
    __tablename__ = 'players'

    id = db.Column(db.Integer, primary_key=True)
    player_name = db.Column(db.String(100), nullable=False)
    power = db.Column(db.String(100), nullable=False)
    power_description = db.Column(db.Text, nullable=False)
    sex = db.Column(db.String(20), nullable=False)
    physical_description = db.Column(db.Text, nullable=False)
    curr_hp = db.Column(db.Integer, default=100)
    max_hp = db.Column(db.Integer, default=100)
    curr_stam = db.Column(db.Integer, default=100)
    max_stam = db.Column(db.Integer, default=100)
    last_dice_roll = db.Column(db.Integer, default=0)

    def to_dict(self):
        return {
            'id': self.id,
            'player_name': self.player_name,
            'power': self.power,
            'power_description': self.power_description,
            'sex': self.sex,
            'physical_description': self.physical_description,
            'curr_hp': self.curr_hp,
            'max_hp': self.max_hp,
            'curr_stam': self.curr_stam,
            'max_stam': self.max_stam,
            'last_dice_roll': self.last_dice_roll
        }


class Message(db.Model):
    __tablename__ = 'messages'

    id = db.Column(db.Integer, primary_key=True)
    player_id = db.Column(db.Integer, db.ForeignKey('players.id'), nullable=False)
    sender = db.Column(db.String(20), nullable=False)  # 'host' or 'player'
    content = db.Column(db.Text, nullable=False)
    mode = db.Column(db.String(20), default='RP')  # 'RP' or '???'

    player = db.relationship('Player', backref=db.backref('messages', lazy=True))

    def to_dict(self):
        return {
            'id': self.id,
            'player_id': self.player_id,
            'sender': self.sender,
            'content': self.content,
            'mode': self.mode
        }
