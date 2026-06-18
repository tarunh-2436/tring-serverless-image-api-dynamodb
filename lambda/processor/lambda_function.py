import json
import os
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
sns = boto3.client("sns")

table = dynamodb.Table(os.environ["TABLE_NAME"])

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def lambda_handler(event, context):

    print(json.dumps(event))

    for record in event["Records"]:
        process_record(record)

    return {"statusCode": 200, "body": json.dumps({"message": "Processing complete"})}


def process_record(record):

    body = json.loads(record["body"])

    s3_record = body["Records"][0]

    bucket = s3_record["s3"]["bucket"]["name"]
    key = s3_record["s3"]["object"]["key"]

    print(f"Processing {bucket}/{key}")

    # userId/imageId/filename

    parts = key.split("/")

    user_id = parts[0]
    image_id = parts[1]
    filename = parts[2]

    metadata = s3.head_object(Bucket=bucket, Key=key)

    file_size = metadata["ContentLength"]
    content_type = metadata.get("ContentType", "unknown")

    extension = filename.rsplit(".", 1)[-1].lower()

    timestamp = datetime.now(timezone.utc).isoformat()

    table.update_item(
        Key={"userId": user_id, "imageId": image_id},
        UpdateExpression="""
            SET
                #status = :status,
                fileSize = :fileSize,
                contentType = :contentType,
                extension = :extension,
                processedAt = :processedAt,
                lastUpdated = :lastUpdated
        """,
        ExpressionAttributeNames={"#status": "status"},
        ExpressionAttributeValues={
            ":status": "COMPLETED",
            ":fileSize": file_size,
            ":contentType": content_type,
            ":extension": extension,
            ":processedAt": timestamp,
            ":lastUpdated": timestamp,
        },
    )

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="Image Processed Successfully",
        Message=f"""
Image ID: {image_id}

Filename: {filename}

File Size: {file_size} bytes

Content Type: {content_type}

Extension: {extension}

Processed At: {timestamp}
""",
    )

    print(f"Successfully processed {image_id}")
