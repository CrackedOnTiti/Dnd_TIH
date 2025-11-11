from flask import Flask, send_from_directory
from flask_socketio import SocketIO, emit
import os

app = Flask(__name__)
socketio = SocketIO(app, cors_allowed_origins="*")

FRONT_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'front')

@app.route('/')
def index():
    return "Go to /host or /player"

@app.route('/host')
def host():
    return send_from_directory(FRONT_DIR, 'host.html')

@app.route('/player')
def player():
    return send_from_directory(FRONT_DIR, 'player.html')

@socketio.on('increment')
def handle_increment():
    print('Player clicked increment!')
    emit('increment', broadcast=True)

if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)
