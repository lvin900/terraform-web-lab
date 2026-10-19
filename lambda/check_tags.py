"""Event-driven tag compliance check.

Triggered by Amazon EventBridge when an EC2 instance enters the "running" state.
Looks up the instance's tags and publishes an SNS alert if any required tag is missing.
"""

import json
import os

import boto3

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

REQUIRED_TAGS = [t.strip() for t in os.environ["REQUIRED_TAGS"].split(",") if t.strip()]
TOPIC_ARN = os.environ["TOPIC_ARN"]


def handler(event, context):
    instance_id = event["detail"]["instance-id"]
    region = event.get("region", "unknown")
    print(f"Checking tags on {instance_id} in {region}")

    reservations = ec2.describe_instances(InstanceIds=[instance_id])["Reservations"]
    instance = reservations[0]["Instances"][0]
    tags = {t["Key"]: t["Value"] for t in instance.get("Tags", [])}

    missing = [key for key in REQUIRED_TAGS if key not in tags]

    if not missing:
        print(f"{instance_id} is compliant: all required tags present")
        return {"instance_id": instance_id, "compliant": True}

    name = tags.get("Name", "(no Name tag)")
    message = (
        f"EC2 instance {instance_id} ({name}) in {region} started without "
        f"required tags: {', '.join(missing)}.\n\n"
        f"Current tags:\n{json.dumps(tags, indent=2)}"
    )
    print(message)

    sns.publish(
        TopicArn=TOPIC_ARN,
        Subject=f"Tag compliance alert: {instance_id}",
        Message=message,
    )
    return {"instance_id": instance_id, "compliant": False, "missing": missing}
