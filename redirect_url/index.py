import os
import json
import boto3
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

def handler(event, context):
    try:
        print(event)
        short_url = event['pathParameters']['shortUrl']
        print(f"Requested short URL: {short_url}")  # Add logging
        
        # Get the mapping from DynamoDB
        response = table.get_item(
            Key={
                'short_url': short_url
            }
        )
        
        # Check if item exists
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'URL not found'})
            }
        
        # Get the long URL
        long_url = response['Item']['long_url']
        
        # Return redirect response
        return {
            'statusCode': 301,
            'headers': {
                'Location': long_url,
                'Access-Control-Allow-Origin': '*',
                'Cache-Control': 'no-cache'
            },
            'body': ''
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")  # Add logging
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }
