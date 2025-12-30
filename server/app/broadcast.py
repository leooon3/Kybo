import firebase_admin
from firebase_admin import messaging

def broadcast_message(title: str, body: str, data: dict = None):
    """
    Sends a notification to the 'all_users' topic.
    Ensure your Flutter app subscribes to 'all_users' on startup.
    """
    topic = 'all_users'

    message = messaging.Message(
        notification=messaging.Notification(
            title=title,
            body=body,
        ),
        data=data or {},
        topic=topic,
    )

    try:
        response = messaging.send(message)
        print('Successfully sent message:', response)
        return response
    except Exception as e:
        print('Error sending message:', e)
        raise e