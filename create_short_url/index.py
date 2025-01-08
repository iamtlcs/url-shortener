import os
import json
import time
import boto3
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

def handler(event, context):
    try:
        # Get base URL from API Gateway event context
        print(event)
        domain_name = event['requestContext']['domainName']
        stage = event['requestContext']['stage']
        base_url = f"https://{domain_name}/{stage}"
        
        body = json.loads(event['body'])
        long_url = body['url']
        custom_suffix = body['suffix']
        
        # Set expiration time (10 minutes from now)
        expiry_time = int(time.time()) + 600
        
        # Store the mapping in DynamoDB
        table.put_item(
            Item={
                'short_url': custom_suffix,
                'long_url': long_url,
                'expiry': Decimal(expiry_time)
            }
        )
        
        # Construct the short URL using the base URL from event context
        short_url = f"{base_url}/{custom_suffix}"
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'short_url': short_url,
                'expiry': expiry_time
            })
        }
    except Exception as e:
        print(f"Error: {str(e)}")  # Add logging
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
