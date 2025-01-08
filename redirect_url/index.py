import os
import json
import time
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

def handler(event, context):
    try:
        # Get the short URL from the path parameter
        short_url = event['pathParameters']['shortUrl']
        
        # Get the mapping from DynamoDB
        response = table.get_item(
            Key={
                'short_url': short_url
            }
        )
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'URL not found'})
            }
            
        item = response['Item']
        current_time = int(time.time())
        
        if current_time > item['expiry']:
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'URL has expired'})
            }
            
        new_expiry = current_time + 600
        
        table.update_item(
            Key={
                'short_url': short_url
            },
            UpdateExpression='SET expiry = :new_expiry',
            ExpressionAttributeValues={
                ':new_expiry': new_expiry
            }
        )
        
        return {
            'statusCode': 301,
            'headers': {
                'Location': item['long_url']
            }
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
