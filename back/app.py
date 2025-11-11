from flask import Flask, send_from_directory
from flask_socketio import SocketIO, emit
from flask_sqlalchemy import SQLAlchemy
import os

app = Flask(__name__)

# Database configuration
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('DATABASE_URL', 'sqlite:///dnd.db')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)
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

@socketio.on('increment')
def handle_increment():
    print('Player clicked increment!')
    emit('increment', broadcast=True)

if __name__ == '__main__':
    # Import models and create tables
    from models import Player
    import time

    # Wait for database to be ready
    max_retries = 5
    retry_count = 0
    while retry_count < max_retries:
        try:
            with app.app_context():
                db.create_all()
                print("Database tables created!")
            break
        except Exception as e:
            retry_count += 1
            print(f"Database not ready yet, retrying... ({retry_count}/{max_retries})")
            time.sleep(2)
            if retry_count >= max_retries:
                print("Could not connect to database after multiple retries")
                raise e

    socketio.run(app, host='0.0.0.0', port=5000, debug=True, allow_unsafe_werkzeug=True)
