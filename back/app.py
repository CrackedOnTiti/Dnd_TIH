from flask import Flask, send_from_directory, request, jsonify
from flask_socketio import SocketIO, emit
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS
import os

app = Flask(__name__)

# Database configuration
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('DATABASE_URL', 'sqlite:///dnd.db')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)

# Enable CORS for all routes and origins (for local network access)
CORS(app, resources={r"/*": {"origins": "*"}})
socketio = SocketIO(app, cors_allowed_origins="*")

FRONT_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'front')

@app.route('/')
def index():
    return send_from_directory(FRONT_DIR, 'index.html')

@app.route('/host')
def host():
    return send_from_directory(FRONT_DIR, 'host.html')

@app.route('/player')
def player():
    return send_from_directory(FRONT_DIR, 'player.html')

@app.route('/player/create')
def player_create():
    return send_from_directory(FRONT_DIR, 'player_create.html')

@app.route('/api/player/create', methods=['POST'])
def api_create_player():
    from models import Player
    try:
        data = request.get_json()

        new_player = Player(
            player_name=data['player_name'],
            power=data['power'],
            power_description=data['power_description'],
            sex=data['sex'],
            physical_description=data['physical_description']
        )

        db.session.add(new_player)
        db.session.commit()

        return jsonify({
            'success': True,
            'player_id': new_player.id
        })
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'error': str(e)
        }), 400

@app.route('/api/player/<int:player_id>', methods=['GET'])
def api_get_player(player_id):
    from models import Player
    try:
        player = db.session.get(Player, player_id)
        if not player:
            return jsonify({
                'success': False,
                'error': 'Player not found'
            }), 404

        return jsonify({
            'success': True,
            'player': player.to_dict()
        })
    except Exception as e:
        print(f"Error getting player: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 400

@app.route('/api/player/<int:player_id>/roll', methods=['POST'])
def api_player_roll(player_id):
    from models import Player
    try:
        data = request.get_json()
        roll = data.get('roll')

        player = db.session.get(Player, player_id)
        if not player:
            return jsonify({
                'success': False,
                'error': 'Player not found'
            }), 404

        player.last_dice_roll = roll
        db.session.commit()

        # Broadcast to all connected clients (especially host)
        socketio.emit('player_rolled', {
            'player_id': player.id,
            'player_name': player.player_name,
            'roll': roll
        })

        return jsonify({
            'success': True,
            'roll': roll
        })
    except Exception as e:
        db.session.rollback()
        print(f"Error saving dice roll: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 400

@app.route('/api/players', methods=['GET'])
def api_get_all_players():
    from models import Player
    try:
        players = db.session.query(Player).all()
        return jsonify({
            'success': True,
            'players': [player.to_dict() for player in players]
        })
    except Exception as e:
        print(f"Error getting players: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            'success': False,
            'error': str(e)
        }), 400

@socketio.on('increment')
def handle_increment():
    print('Player clicked increment!')
    emit('increment', broadcast=True)

if __name__ == '__main__':
    import time

    # Wait for database to be ready
    print("Waiting for database...")
    time.sleep(5)

    # Create tables
    from models import Player
    with app.app_context():
        db.create_all()
        print("Database tables created!")

        # Verify table exists
        result = db.session.execute(db.text("SELECT to_regclass('public.players')"))
        table_exists = result.scalar()
        print(f"Table exists check: {table_exists}")

        if not table_exists:
            print("WARNING: Table was not created! Trying again with explicit SQL...")
            db.session.execute(db.text("""
                CREATE TABLE IF NOT EXISTS players (
                    id SERIAL PRIMARY KEY,
                    player_name VARCHAR(100) NOT NULL,
                    power VARCHAR(100) NOT NULL,
                    power_description TEXT NOT NULL,
                    sex VARCHAR(20) NOT NULL,
                    physical_description TEXT NOT NULL,
                    curr_hp INTEGER DEFAULT 20,
                    max_hp INTEGER DEFAULT 20,
                    last_dice_roll INTEGER DEFAULT 0
                )
            """))
            db.session.commit()
            print("Table created with raw SQL!")

    socketio.run(app, host='0.0.0.0', port=5000, debug=True, use_reloader=False, allow_unsafe_werkzeug=True)
