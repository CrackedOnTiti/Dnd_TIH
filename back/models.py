from app import db

class Player(db.Model):
    __tablename__ = 'players'

    id = db.Column(db.Integer, primary_key=True)
    player_name = db.Column(db.String(100), nullable=False)
    curr_hp = db.Column(db.Integer, default=20)
    max_hp = db.Column(db.Integer, default=20)
    last_dice_roll = db.Column(db.Integer, default=0)

    def to_dict(self):
        return {
            'id': self.id,
            'player_name': self.player_name,
            'curr_hp': self.curr_hp,
            'max_hp': self.max_hp,
            'last_dice_roll': self.last_dice_roll
        }
