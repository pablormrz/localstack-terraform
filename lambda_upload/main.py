# lambda_upload/main.py
import json
import os
import boto3
from botocore.exceptions import ClientError

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

    file_key = None
    # {file_key+} capturará toda la ruta, incluyendo la carpeta y el nombre del archivo
    if 'pathParameters' in event and 'file_key' in event['pathParameters']:
        file_key = event['pathParameters']['file_key']

    if not file_key:
        return {
            'statusCode': 400,
            'headers': { 'Content-Type': 'application/json' },
            'body': json.dumps({'error': 'Missing file_key in path. Usage: /upload/{folder_path}/{file_name}'})
        }

    try:
        # Generar la URL prefirmada para PUT Object
        presigned_url = s3.generate_presigned_url(
            ClientMethod='put_object',
            Params={'Bucket': bucket_name, 'Key': file_key},
            ExpiresIn=300 # La URL será válida por 5 minutos (300 segundos)
        )

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'file_key': file_key,
                'presigned_upload_url': presigned_url
            })
        }
    except ClientError as e:
        print(f"Error generating presigned upload URL: {e}")
        return {
            'statusCode': 500,
            'headers': { 'Content-Type': 'application/json' },
            'body': json.dumps({'error': str(e)})
        }
    except Exception as e:
        print(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'headers': { 'Content-Type': 'application/json' },
            'body': json.dumps({'error': str(e)})
        }