#!/usr/bin/env python3
import os
import sys

base_dir = os.path.dirname(os.path.abspath(__file__))
rust_bin = os.path.join(base_dir, "target", "release", "beautyflow-crm")

if os.path.isfile(rust_bin) and os.access(rust_bin, os.X_OK):
    print("🚀 Iniciando BeautyFlow CRM Backend em Rust (Ultra performance)...")
    env = os.environ.copy()
    env.setdefault("PORT", "3001")
    os.execv(rust_bin, [rust_bin] + sys.argv[1:])

# Fallback para o backend Python original
os.environ.setdefault('FLASK_DEBUG', '1')
os.environ.setdefault('FLASK_RELOAD', '1')

import server

if hasattr(server, 'start_dev_file_watcher'):
    server.start_dev_file_watcher()

if hasattr(server, 'start_postgres_listener'):
    server.start_postgres_listener()

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
