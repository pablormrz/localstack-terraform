# lambda_list_folders/main.py
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

    # Opcional: Permitir un prefijo si se quiere listar carpetas dentro de otra carpeta
    # Esto es útil si un día quieres listar subcarpetas, pero por ahora solo el nivel raíz
    # Si no se envía 'prefix', listará las carpetas desde la raíz del bucket.
    query_prefix = ""
    if 'queryStringParameters' in event and event['queryStringParameters'] and 'prefix' in event['queryStringParameters']:
        query_prefix = event['queryStringParameters']['prefix']
        if not query_prefix.endswith('/'): # Asegurarse que el prefijo termine en /
            query_prefix += '/'


    print(f"Listing top-level folders in bucket: {bucket_name} with prefix: '{query_prefix}'")

    try:
        # Usamos Delimiter='/' para obtener solo los prefijos comunes (carpetas) en el nivel actual
        # y no los objetos (archivos) directamente
        response = s3.list_objects_v2(Bucket=bucket_name, Delimiter='/', Prefix=query_prefix)

        folders = []
        if 'CommonPrefixes' in response:
            for common_prefix in response['CommonPrefixes']:
                # common_prefix['Prefix'] ya termina en '/'
                folder_name = common_prefix['Prefix']
                # Si hay un query_prefix, eliminarlo para mostrar solo el nombre relativo de la carpeta
                if query_prefix and folder_name.startswith(query_prefix):
                    folder_name = folder_name[len(query_prefix):]

                # Solo añadir si el nombre de la carpeta no está vacío (evitar añadir el prefijo mismo)
                if folder_name:
                    folders.append(folder_name.rstrip('/')) # Eliminar la barra final para el nombre de la carpeta

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'folders': folders})
        }
    except ClientError as e:
        print(f"Error listing folders: {e}")
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