import os
import json
import time
import boto3
from decimal import Decimal
import random
import string
import validators

def is_valid_url(url):
    return validators.url(url)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

headers = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST',
    'Access-Control-Allow-Headers': 'Content-Type'
}

def handler(event, context):
    try:
        # Get base URL from API Gateway event context
        print(event)
        domain_name = event['requestContext']['domainName']
        stage = event['requestContext']['stage']
        base_url = f"https://{domain_name}/{stage}"
        
        body = json.loads(event['body'])
        long_url = body['url']
        
        print(f"Requested long URL: {long_url}") 
        is_valid = is_valid_url(long_url)
        print(f"Is valid URL: {is_valid}")
        print(bool(is_valid))
        
        if not is_valid:
            print("Invalid URL")
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Invalid URL'})
            }
        
        def generate_unique_suffix():
            suffix_length = 5
            characters = string.ascii_letters + string.digits
            unique_suffix = ''.join(random.choice(characters) for _ in range(suffix_length))
            return unique_suffix
        
        custom_suffix = body.get('suffix', generate_unique_suffix())
        
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
            'headers': headers,
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
