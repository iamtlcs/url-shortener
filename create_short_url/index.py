import os
import json
import time
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

def handler(event, context):
    try:
        body = json.loads(event['body'])
        long_url = body['url']
        custom_suffix = body['suffix']
        
        expiry_time = (time.time() + 600)
        
        table.put_item(
            Item={
                'short_url': custom_suffix,
                'long_url': long_url,
                'expiry': expiry_time
            }
        )
        
        short_url = f"{BASE_URL}/{custom_suffix}"
        
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
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
