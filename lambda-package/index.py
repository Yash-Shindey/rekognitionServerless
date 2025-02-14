import json
import boto3
import os
from datetime import datetime
import uuid
from decimal import Decimal

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)  # Convert Decimal to float for JSON serialization
        return super(DecimalEncoder, self).default(obj)

def handler(event, context):
    print("Starting Lambda execution")
    print("Event:", json.dumps(event))
    
    try:
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = event['Records'][0]['s3']['object']['key']
        print(f"Processing {key} from bucket {bucket}")
        
        # Initialize AWS clients
        rekognition = boto3.client('rekognition')
        dynamodb = boto3.resource('dynamodb').Table(os.environ['DYNAMODB_TABLE'])
        
        # Call Rekognition
        print("Calling detect_labels")
        response = rekognition.detect_labels(
            Image={
                'S3Object': {
                    'Bucket': bucket,
                    'Name': key
                }
            },
            MaxLabels=10,
            MinConfidence=70
        )
        print("Rekognition response:", json.dumps(response))
        
        # Process labels
        labels = [{
            'name': label['Name'],
            'confidence': Decimal(str(label['Confidence']))
        } for label in response['Labels']]
        
        # Create metadata
        image_id = str(uuid.uuid4())
        metadata = {
            'imageId': image_id,
            'uploadDate': datetime.utcnow().isoformat(),
            'status': 'processed',
            'url': f"https://{bucket}.s3.amazonaws.com/{key}",
            'aiAnalysis': {
                'labels': labels
            }
        }
        
        # Store in DynamoDB
        print("Storing in DynamoDB:", json.dumps(metadata, cls=DecimalEncoder))
        dynamodb.put_item(Item=metadata)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Image processed successfully',
                'metadata': metadata
            }, cls=DecimalEncoder)
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        import traceback
        print("Traceback:", traceback.format_exc())
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)}, cls=DecimalEncoder)
        }
