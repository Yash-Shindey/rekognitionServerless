import json
import boto3
import os
from datetime import datetime
from decimal import Decimal
from boto3.dynamodb.conditions import Key

# Custom JSON encoder to handle Decimal values
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)  # Convert Decimal to float
        return super(DecimalEncoder, self).default(obj)

# Initialize AWS Clients
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

def get_image_url(bucket, key):
    return f"https://{bucket}.s3.{os.environ['AWS_REGION']}.amazonaws.com/{key}"

def search_images(query):
    """Search for images in DynamoDB based on partial matches in searchableTerms."""
    try:
        print(f"🔍 Searching for images with term: '{query}'")

        # Use Scan instead of Query to allow partial matching
        response = table.scan(
            FilterExpression="contains(searchableTerms, :term)",
            ExpressionAttributeValues={":term": {"S": query}}
        )

        items = response.get('Items', [])
        if not items:
            print(f"⚠ No results found for query: {query}")

        # Convert S3 keys into full URLs and serialize Decimal values
        for item in items:
            item['url'] = get_image_url(os.environ['S3_BUCKET'], item['url'])

        print(f"✅ Search Results: {json.dumps(items, cls=DecimalEncoder, indent=2)}")

        return {
            'statusCode': 200,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'images': items}, cls=DecimalEncoder)  # Use DecimalEncoder to avoid errors
        }
    except Exception as e:
        print(f"🚨 Error in search_images: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': str(e)})
        }