import json
import boto3
import os
from datetime import datetime
from decimal import Decimal

# Custom JSON encoder to handle Decimal values from DynamoDB
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)

# Initialize AWS Clients
s3 = boto3.client('s3')
rekognition = boto3.client('rekognition')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

def handler(event, context):
    """Lambda function triggered by S3 events to process images."""
    print("🛠 FULL EVENT RECEIVED FROM S3:", json.dumps(event, indent=2))

    if "Records" not in event:
        return error_response("Missing 'Records' in event", 400)

    try:
        record = event["Records"][0]
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]
        image_id = key.split('/')[-1]

        print(f"✅ Processing Image: Bucket={bucket}, Key={key}")

        # Detect labels and text from the image
        labels = detect_labels(bucket, key)
        text = detect_text(bucket, key)

        # Generate a searchable term string
        label_names = sorted([label['name'].lower() for label in labels])  # Sorting ensures consistency
        searchable_terms = " ".join(label_names)

        # Check if a record with the same searchable terms exists
        existing_items = table.query(
            IndexName='SearchableTermsIndex',
            KeyConditionExpression=Key('searchableTerms').eq(searchable_terms)
        ).get('Items', [])

        if existing_items:
            print(f"🔁 Found existing images with the same labels. Assigning to existing path.")
            existing_image = existing_items[0]  # Take first image with same terms
            image_url = existing_image['url']
        else:
            print(f"🆕 No existing record found. Creating a new entry.")
            image_url = get_image_url(bucket, key)

        # Construct metadata for DynamoDB
        item = {
            'imageId': image_id,
            'uploadDate': datetime.utcnow().isoformat(),
            'status': 'processed',
            'url': image_url,
            'aiAnalysis': {
                'labels': labels,
                'text': text
            },
            'searchableTerms': searchable_terms  # Dynamic storage of searchable terms
        }

        print(f"📥 Storing item in DynamoDB: {json.dumps(item, cls=DecimalEncoder)}")
        table.put_item(Item=item)

        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Image processed successfully'}, cls=DecimalEncoder)
        }

    except Exception as e:
        print(f"🚨 Error processing image: {str(e)}")
        return error_response(str(e))

def detect_labels(bucket, key):
    """Detect labels in an image using Amazon Rekognition."""
    print(f"🔍 Detecting labels for {bucket}/{key}")
    response = rekognition.detect_labels(
        Image={'S3Object': {'Bucket': bucket, 'Name': key}},
        MaxLabels=10,
        MinConfidence=70
    )
    return [{'name': label['Name'], 'confidence': Decimal(str(label['Confidence']))} for label in response.get('Labels', [])]

def detect_text(bucket, key):
    """Detect text in an image using Amazon Rekognition."""
    print(f"🔍 Detecting text for {bucket}/{key}")
    response = rekognition.detect_text(Image={'S3Object': {'Bucket': bucket, 'Name': key}})
    return [text['DetectedText'] for text in response.get('TextDetections', []) if text['Type'] == 'WORD']

def get_image_url(bucket, key):
    """Construct the S3 URL for an image."""
    return f"https://{bucket}.s3.{os.environ['AWS_REGION']}.amazonaws.com/{key}"

def error_response(message, status_code=500):
    """Generate an error response with proper headers."""
    return {
        'statusCode': status_code,
        'body': json.dumps({'error': message})
    }