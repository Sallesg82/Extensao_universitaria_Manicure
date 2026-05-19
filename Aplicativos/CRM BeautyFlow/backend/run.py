#!/usr/bin/env python3
import server
server.socketio.run(server.app, host='0.0.0.0', port=3001, debug=False, allow_unsafe_werkzeug=True, use_reloader=False)
