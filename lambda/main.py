# lambda/main.py
import json
import os
import boto3

def handler(event, context):
    s3 = boto3.client('s3',
                      endpoint_url='http://localstack:4566',
                      aws_access_key_id='test',
                      aws_secret_access_key='test',
                      region_name='us-east-1')

    bucket_name = os.environ.get('BUCKET_NAME')
    if not bucket_name:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'BUCKET_NAME environment variable not set'})
        }

    folder_prefix = ""
    if 'pathParameters' in event and 'folder' in event['pathParameters']:
        folder_prefix = event['pathParameters']['folder']
        if folder_prefix and not folder_prefix.endswith('/'):
            folder_prefix += '/'

    print(f"Listing objects in bucket: {bucket_name} with prefix: '{folder_prefix}'")

    try:
        response = s3.list_objects_v2(Bucket=bucket_name, Prefix=folder_prefix)
        files = []
        if 'Contents' in response:
            for obj in response['Contents']:
                key_name = obj['Key']
                if folder_prefix and key_name.startswith(folder_prefix):
                    key_name = key_name[len(folder_prefix):]

                if key_name == "":
                    continue

                files.append({
                    'Key': key_name,
                    'Size': obj['Size'],
                    'LastModified': obj['LastModified'].isoformat()
                })

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'files': files})
        }
    except Exception as e:
        print(f"Error listing objects: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }