"""Serverless contact form handler.

Invoked by API Gateway (HTTP API, payload format 2.0) when someone submits the
form on the website. Validates the input and publishes it to an SNS topic,
which emails it to the site owner.
"""

import base64
import json
import os
from datetime import datetime, timezone

import boto3

sns = boto3.client("sns")

TOPIC_ARN = os.environ["TOPIC_ARN"]
MAX_NAME = 100
MAX_MESSAGE = 1000


def response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event, context):
    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8", errors="replace")

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return response(400, {"error": "Request body must be JSON."})
    if not isinstance(data, dict):
        return response(400, {"error": "Request body must be a JSON object."})

    name = str(data.get("name", "")).strip()
    message = str(data.get("message", "")).strip()

    if not name:
        return response(400, {"error": "Please enter your name."})
    if len(name) > MAX_NAME or len(message) > MAX_MESSAGE:
        return response(400, {"error": "Your name or message is too long."})

    source_ip = event.get("requestContext", {}).get("http", {}).get("sourceIp", "unknown")
    sent_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    body = (
        f"New message from your website contact form.\n\n"
        f"Name: {name}\n"
        f"Message: {message or '(none)'}\n\n"
        f"Sent: {sent_at}\n"
        f"From IP: {source_ip}"
    )

    sns.publish(
        TopicArn=TOPIC_ARN,
        Subject="New message from your website",
        Message=body,
    )

    # Log that a message was sent, but not its contents (avoid storing personal data in logs).
    print(json.dumps({"event": "contact_message_sent", "source_ip": source_ip}))
    return response(200, {"ok": True})
