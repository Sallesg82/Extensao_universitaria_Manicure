#!/usr/bin/env python3
import os

os.environ.setdefault('FLASK_DEBUG', '1')
os.environ.setdefault('FLASK_RELOAD', '1')

import server

if hasattr(server, 'start_dev_file_watcher'):
    server.start_dev_file_watcher()

debug = os.environ.get('FLASK_DEBUG', '1') == '1'
use_reloader = os.environ.get('FLASK_RELOAD', '1') == '1'

server.socketio.run(
    server.app,
    host='0.0.0.0',
    port=3001,
    debug=debug,
    allow_unsafe_werkzeug=True,
    use_reloader=use_reloader
)
