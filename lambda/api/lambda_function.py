from fileinput import filename
import json
import uuid
import os
import boto3
from datetime import datetime, timezone
from decimal import Decimal

dynamodb = boto3.resource("dynamodb")

s3 = boto3.client("s3")

table = dynamodb.Table(os.environ["TABLE_NAME"])

UPLOAD_BUCKET = os.environ["UPLOAD_BUCKET"]


def decimal_serializer(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Object of type {obj.__class__.__name__} is not JSON serializable")


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=decimal_serializer),
    }


def lambda_handler(event, context):

    method = event["requestContext"]["http"]["method"]

    path = event["requestContext"]["http"]["path"]

    if method == "POST" and path.endswith("/images"):
        return create_image(event)

    if method == "GET" and path.endswith("/images"):
        return list_images(event)

    if method == "GET" and "/images/" in path:
        return get_image(event)

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
            "status": "PENDING",
            "createdAt": timestamp,
            "updatedAt": timestamp,
        }
    )

    upload_url = s3.generate_presigned_url(
        "put_object",
        Params={
            "Bucket": UPLOAD_BUCKET,
            "Key": f"uploads/{user_id}/{image_id}/{filename}",
            "ContentType": content_type,
        },
        ExpiresIn=900,
    )

    return response(201, {"imageId": image_id, "uploadUrl": upload_url})


def list_images(event):
    claims = event["requestContext"]["authorizer"]["jwt"]["claims"]

    user_id = claims["sub"]

    dynamodb_response = table.query(
        IndexName="CreatedAtIndex",
        KeyConditionExpression="userId = :userId",
        ExpressionAttributeValues={":userId": user_id},
        ScanIndexForward=False,
    )

    images = []

    for image in dynamodb_response["Items"]:

        display_contents = {}
        display_contents["imageId"] = image["imageId"]
        display_contents["filename"] = image["filename"]
        display_contents["status"] = image["status"]
        display_contents["createdAt"] = image["createdAt"]
        images.append(display_contents)

    return response(200, {"images": images})


def get_image(event):
    claims = event["requestContext"]["authorizer"]["jwt"]["claims"]

    user_id = claims["sub"]

    path_params = event.get("pathParameters") or {}

    image_id = path_params.get("imageId")

    if not image_id:
        return response(400, {"message": "Image ID required"})

    dynamodb_response = table.get_item(Key={"userId": user_id, "imageId": image_id})

    if "Item" not in dynamodb_response:
        return response(404, {"message": "Image not found"})

    item = dynamodb_response["Item"]

    filename = item.get("filename")

    if not filename:
        return response(500, {"message": "Image record is missing filename"})

    download_url = s3.generate_presigned_url(
        "get_object",
        Params={
            "Bucket": UPLOAD_BUCKET,
            "Key": f"uploads/{user_id}/{image_id}/{filename}",
        },
        ExpiresIn=3600,
    )

    return response(200, {"image": item, "downloadUrl": download_url})
