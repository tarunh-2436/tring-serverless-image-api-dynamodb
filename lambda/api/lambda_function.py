import json
import uuid
import os
import boto3

from datetime import datetime, timezone

dynamodb = boto3.resource("dynamodb")

s3 = boto3.client("s3")

table = dynamodb.Table(os.environ["TABLE_NAME"])

UPLOAD_BUCKET = os.environ["UPLOAD_BUCKET"]


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def lambda_handler(event, context):

    method = event["requestContext"]["http"]["method"]

    path = event["requestContext"]["http"]["path"]

    if method == "POST" and path.endswith("/images"):
        return create_image(event)

    return response(404, {"message": "Route not found"})


def create_image(event):

    claims = event["requestContext"]["authorizer"]["jwt"]["claims"]

    user_id = claims["sub"]

    body = json.loads(event["body"])

    filename = body["filename"]

    content_type = body["contentType"]

    image_id = str(uuid.uuid4())

    timestamp = datetime.now(timezone.utc).isoformat()

    table.put_item(
        Item={
            "userId": user_id,
            "imageId": image_id,
            "filename": filename,
            "status": "PENDING_UPLOAD",
            "createdAt": timestamp,
            "updatedAt": timestamp,
        }
    )

    upload_url = s3.generate_presigned_url(
        "put_object",
        Params={
            "Bucket": UPLOAD_BUCKET,
            "Key": f"{user_id}/{image_id}/{filename}",
            "ContentType": content_type,
        },
        ExpiresIn=900,
    )

    return response(201, {"imageId": image_id, "uploadUrl": upload_url})
