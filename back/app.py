import eventlet
eventlet.monkey_patch()

from flask import Flask, request, jsonify
from flask_socketio import SocketIO, emit
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS
from functools import wraps
import os

app = Flask(__name__)

# Database configuration
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('DATABASE_URL', 'sqlite:///dnd.db')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# Host password
HOST_PASSWORD = os.environ.get('HOST_PASSWORD', '2251')

db = SQLAlchemy(app)

# Enable CORS for all routes and origins (for local network access)
CORS(app, resources={r"/*": {"origins": "*"}})
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')

def require_host_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        password = request.headers.get('X-Host-Password')
        if password != HOST_PASSWORD:
            return jsonify({'success': False, 'error': 'Unauthorized'}), 401
        return f(*args, **kwargs)
    return decorated

@app.route('/api/auth/host', methods=['POST'])
def auth_host():
    data = request.get_json()
    if data.get('password') == HOST_PASSWORD:
        return jsonify({'success': True})
    return jsonify({'success': False, 'error': 'Wrong password'}), 401

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

        # Notify host of new player
        socketio.emit('player_created', {
            'player_id': new_player.id,
            'player_name': new_player.player_name
        })

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

@app.route('/api/player/<int:player_id>/messages', methods=['GET'])
def api_get_player_messages(player_id):
    from models import Message
    try:
        messages = db.session.query(Message).filter_by(player_id=player_id).all()
        return jsonify({
            'success': True,
            'messages': [msg.to_dict() for msg in messages]
        })
    except Exception as e:
        print(f"Error getting messages: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 400


@app.route('/api/players', methods=['GET'])
@require_host_auth
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

@socketio.on('host_rolled')
def handle_host_rolled(data):
    # Broadcast to all clients (players will receive this)
    emit('host_rolled', data, broadcast=True)

@socketio.on('update_stat')
def handle_update_stat(data):
    from models import Player
    player_id = data.get('player_id')
    stat_type = data.get('stat_type')
    value = data.get('value')

    with app.app_context():
        player = db.session.get(Player, player_id)
        if player:
            if stat_type == 'hp':
                player.curr_hp = value
            elif stat_type == 'stam':
                player.curr_stam = value
            db.session.commit()

            # Broadcast to all clients (including player)
            emit('stat_updated', {
                'player_id': player_id,
                'stat_type': stat_type,
                'value': value,
            }, broadcast=True)

@socketio.on('host_message')
def handle_host_message(data):
    from models import Message
    player_id = data.get('player_id')
    content = data.get('content')
    mode = data.get('mode', 'RP')

    with app.app_context():
        message = Message(
            player_id=player_id,
            sender='host',
            content=content,
            mode=mode
        )
        db.session.add(message)
        db.session.commit()

        # Send to specific player
        emit('new_message_' + str(player_id), message.to_dict(), broadcast=True)


@socketio.on('player_message')
def handle_player_message(data):
    from models import Message
    player_id = data.get('player_id')
    content = data.get('content')

    with app.app_context():
        message = Message(
            player_id=player_id,
            sender='player',
            content=content,
            mode='RP'  # Player messages are always RP mode
        )
        db.session.add(message)
        db.session.commit()

        # Broadcast so host can receive
        emit('new_message_' + str(player_id), message.to_dict(), broadcast=True)


@socketio.on('update_player_field')
def handle_update_player_field(data):
    from models import Player
    player_id = data.get('player_id')
    field = data.get('field')
    value = data.get('value')

    # Allowed fields to update
    allowed_fields = [
        'player_name', 'power', 'power_description', 'sex', 'physical_description',
        'curr_hp', 'max_hp', 'curr_stam', 'max_stam', 'last_dice_roll'
    ]

    if field not in allowed_fields:
        return

    with app.app_context():
        player = db.session.get(Player, player_id)
        if player:
            setattr(player, field, value)
            db.session.commit()

            # Broadcast to all clients
            emit('player_updated', {
                'player_id': player_id,
                'field': field,
                'value': value,
            }, broadcast=True)

if __name__ == '__main__':
    import time
    import sys

    # Wait for database to be ready
    print("Waiting for database...", flush=True)
    time.sleep(5)

    # Create tables
    from models import Player, Message
    with app.app_context():
        try:
            db.create_all()
            print("Database tables created!", flush=True)
        except Exception as e:
            print(f"Error creating tables: {e}", flush=True)
            sys.exit(1)

        # Verify tables exist
        result = db.session.execute(db.text("SELECT to_regclass('public.players')"))
        players_exists = result.scalar()
        result = db.session.execute(db.text("SELECT to_regclass('public.messages')"))
        messages_exists = result.scalar()
        print(f"Players table: {players_exists}, Messages table: {messages_exists}", flush=True)

        if not players_exists or not messages_exists:
            print("WARNING: Tables missing! Creating with explicit SQL...", flush=True)
            db.session.execute(db.text("""
                CREATE TABLE IF NOT EXISTS players (
                    id SERIAL PRIMARY KEY,
                    player_name VARCHAR(100) NOT NULL,
                    power VARCHAR(100) NOT NULL,
                    power_description TEXT NOT NULL,
                    sex VARCHAR(20) NOT NULL,
                    physical_description TEXT NOT NULL,
                    curr_hp INTEGER DEFAULT 100,
                    max_hp INTEGER DEFAULT 100,
                    curr_stam INTEGER DEFAULT 100,
                    max_stam INTEGER DEFAULT 100,
                    last_dice_roll INTEGER DEFAULT 0
                )
            """))
            db.session.execute(db.text("""
                CREATE TABLE IF NOT EXISTS messages (
                    id SERIAL PRIMARY KEY,
                    player_id INTEGER NOT NULL REFERENCES players(id),
                    sender VARCHAR(20) NOT NULL,
                    content TEXT NOT NULL,
                    mode VARCHAR(20) DEFAULT 'RP'
                )
            """))
            db.session.commit()
            print("Tables created with raw SQL!", flush=True)

    socketio.run(app, host='0.0.0.0', port=5000, debug=True, use_reloader=False)
