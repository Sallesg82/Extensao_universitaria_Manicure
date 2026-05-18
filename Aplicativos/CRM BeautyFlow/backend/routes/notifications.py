from flask import Blueprint, jsonify
from db.database import get_notifications, unread_notifications_count, mark_notification_read, mark_all_notifications_read

notifications_bp = Blueprint('notifications', __name__)


@notifications_bp.route('/', methods=['GET'])
def list_notifications():
    return jsonify(get_notifications())


@notifications_bp.route('/unread-count', methods=['GET'])
def unread_count():
    return jsonify({'count': unread_notifications_count()})


@notifications_bp.route('/read/<int:notif_id>', methods=['POST'])
def read_one(notif_id):
    mark_notification_read(notif_id)
    return jsonify({'status': 'ok'})


@notifications_bp.route('/read-all', methods=['POST'])
def read_all():
    mark_all_notifications_read()
    return jsonify({'status': 'ok'})
