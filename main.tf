# main.tf

# Proveedor de AWS configurado para LocalStack
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  endpoints {
    s3             = "http://localhost:4566"
    lambda         = "http://localhost:4566"
    apigateway     = "http://localhost:4566"
  }
}

# Recurso S3 Bucket
resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-localstack-bucket"

  tags = {
    Environment = "Dev"
    Project     = "LocalStackAPI"
  }
}

# Configuración de ACL para el bucket S3
resource "aws_s3_bucket_acl" "my_bucket_acl" {
  bucket = aws_s3_bucket.my_bucket.id
  acl    = "private"
}

# Rol IAM para las funciones Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_s3_access_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Adjuntar política de S3 al rol de Lambda (ListBucket, GetObject y ¡PutObject!)
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "lambda_s3_read_write_policy" # Renombrado para reflejar nuevos permisos
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject" # Nuevo: Permiso para subir objetos (necesario para URLs de subida)
        ],
        Effect   = "Allow",
        Resource = [
          aws_s3_bucket.my_bucket.arn,
          "${aws_s3_bucket.my_bucket.arn}/*"
        ]
      },
      {
        Action   = "logs:CreateLogGroup",
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/*:*"
      }
    ]
  })
}

# Recurso AWS Lambda para listar archivos
resource "aws_lambda_function" "s3_list_function" {
  function_name    = "S3ListFilesFunction"
  runtime          = "python3.9"
  handler          = "main.handler"
  role             = aws_iam_role.lambda_exec_role.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  memory_size      = 128
  timeout          = 30

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.my_bucket.bucket
    }
  }
}

# Recurso AWS Lambda para generar URLs prefirmadas de descarga
resource "aws_lambda_function" "s3_download_function" {
  function_name    = "S3DownloadFileFunction"
  runtime          = "python3.9"
  handler          = "main.handler"
  role             = aws_iam_role.lambda_exec_role.arn
  filename         = data.archive_file.lambda_download_zip.output_path
  source_code_hash = data.archive_file.lambda_download_zip.output_base64sha256
  memory_size      = 128
  timeout          = 30

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.my_bucket.bucket
    }
  }
}

# Recurso AWS Lambda para listar solo carpetas
resource "aws_lambda_function" "s3_list_folders_function" {
  function_name    = "S3ListFoldersFunction"
  runtime          = "python3.9"
  handler          = "main.handler"
  role             = aws_iam_role.lambda_exec_role.arn
  filename         = data.archive_file.lambda_list_folders_zip.output_path
  source_code_hash = data.archive_file.lambda_list_folders_zip.output_base64sha256
  memory_size      = 128
  timeout          = 30

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.my_bucket.bucket
    }
  }
}

# Nuevo: Recurso AWS Lambda para generar URLs prefirmadas de subida
resource "aws_lambda_function" "s3_upload_function" {
  function_name    = "S3UploadFileFunction"
  runtime          = "python3.9"
  handler          = "main.handler"
  role             = aws_iam_role.lambda_exec_role.arn # Reutilizamos el mismo rol
  filename         = data.archive_file.lambda_upload_zip.output_path
  source_code_hash = data.archive_file.lambda_upload_zip.output_base64sha256
  memory_size      = 128
  timeout          = 30

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.my_bucket.bucket
    }
  }
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "s3_list_api" {
  name        = "S3OperationsAPI"
  description = "API para operaciones en un bucket S3"
}

# Recurso de API Gateway (ruta /files)
resource "aws_api_gateway_resource" "files_resource" {
  rest_api_id = aws_api_gateway_rest_api.s3_list_api.id
  parent_id   = aws_api_gateway_rest_api.s3_list_api.root_resource_id
  path_part   = "files"
}

# Recurso para la ruta dinámica /files/{folder+}
resource "aws_api_gateway_resource" "folder_resource" {
  rest_api_id = aws_api_gateway_rest_api.s3_list_api.id
  parent_id   = aws_api_gateway_resource.files_resource.id
  path_part   = "{folder+}"
}

# Recurso de API Gateway (ruta /download)
resource "aws_api_gateway_resource" "download_resource" {
  rest_api_id = aws_api_gateway_rest_api.s3_list_api.id
  parent_id   = aws_api_gateway_rest_api.s3_list_api.root_resource_id
  path_part   = "download"
}

# Recurso para la ruta dinámica /download/{file_key+}
resource "aws_api_gateway_resource" "file_key_resource" {
  rest_api_id = aws_api_gateway_rest_api.s3_list_api.id
  parent_id   = aws_api_gateway_resource.download_resource.id
  path_part   = "{file_key+}"
}

# Recurso de API Gateway (ruta /folders)
resource "aws_api_gateway_resource" "folders_resource" {
  rest_api_id = aws_api_gateway_rest_api.s3_list_api.id
  parent_id   = aws_api_gateway_rest_api.s3_list_api.root_resource_id
  path_part   = "folders"
}

# Nuevo: Recurso de API Gateway (ruta /upload)
resource "aws_api_gateway_resource" "upload_resource" {
  rest_api_id = aws_api_gateway_rest_api.s3_list_api.id
  parent_id   = aws_api_gateway_rest_api.s3_list_api.root_resource_id
  path_part   = "upload"
}

# Nuevo: Recurso para la ruta dinámica /upload/{file_key+}
resource "aws_api_gateway_resource" "upload_file_key_resource" {
  rest_api_id = aws_api_gateway_rest_api.s3_list_api.id
  parent_id   = aws_api_gateway_resource.upload_resource.id # El padre es /upload
  path_part   = "{file_key+}" # Captura la clave completa del archivo
}


# Método GET para /files
resource "aws_api_gateway_method" "get_files_method" {
  rest_api_id   = aws_api_gateway_rest_api.s3_list_api.id
  resource_id   = aws_api_gateway_resource.files_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Método GET para /files/{folder+}
resource "aws_api_gateway_method" "get_folder_files_method" {
  rest_api_id   = aws_api_gateway_rest_api.s3_list_api.id
  resource_id   = aws_api_gateway_resource.folder_resource.id
  http_method   = "GET"
  authorization = "NONE"
  request_parameters = {
    "method.request.path.folder" = true
  }
}

# Método GET para /download/{file_key+}
resource "aws_api_gateway_method" "get_download_method" {
  rest_api_id   = aws_api_gateway_rest_api.s3_list_api.id
  resource_id   = aws_api_gateway_resource.file_key_resource.id
  http_method   = "GET"
  authorization = "NONE"
  request_parameters = {
    "method.request.path.file_key" = true
  }
}

# Método GET para /folders
resource "aws_api_gateway_method" "get_folders_method" {
  rest_api_id   = aws_api_gateway_rest_api.s3_list_api.id
  resource_id   = aws_api_gateway_resource.folders_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Nuevo: Método GET para /upload/{file_key+}
resource "aws_api_gateway_method" "get_upload_method" {
  rest_api_id   = aws_api_gateway_rest_api.s3_list_api.id
  resource_id   = aws_api_gateway_resource.upload_file_key_resource.id # Este es el nuevo recurso
  http_method   = "GET" # El cliente hará un GET a este endpoint para obtener la URL prefirmada de subida
  authorization = "NONE"
  request_parameters = {
    "method.request.path.file_key" = true # Indica que el parámetro 'file_key' es requerido
  }
}


# Integración de la API Gateway con la función Lambda (para /files)
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.s3_list_api.id
  resource_id             = aws_api_gateway_resource.files_resource.id
  http_method             = aws_api_gateway_method.get_files_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.s3_list_function.invoke_arn
}

# Integración de la API Gateway con la función Lambda (para /files/{folder+})
resource "aws_api_gateway_integration" "lambda_folder_integration" {
  rest_api_id             = aws_api_gateway_rest_api.s3_list_api.id
  resource_id             = aws_api_gateway_resource.folder_resource.id
  http_method             = aws_api_gateway_method.get_folder_files_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.s3_list_function.invoke_arn
}

# Integración de la API Gateway con la función Lambda (para /download/{file_key+})
resource "aws_api_gateway_integration" "lambda_download_integration" {
  rest_api_id             = aws_api_gateway_rest_api.s3_list_api.id
  resource_id             = aws_api_gateway_resource.file_key_resource.id
  http_method             = aws_api_gateway_method.get_download_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.s3_download_function.invoke_arn
}

# Integración de la API Gateway con la función Lambda (para /folders)
resource "aws_api_gateway_integration" "lambda_list_folders_integration" {
  rest_api_id             = aws_api_gateway_rest_api.s3_list_api.id
  resource_id             = aws_api_gateway_resource.folders_resource.id
  http_method             = aws_api_gateway_method.get_folders_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.s3_list_folders_function.invoke_arn
}

# Nuevo: Integración de la API Gateway con la función Lambda (para /upload/{file_key+})
resource "aws_api_gateway_integration" "lambda_upload_integration" {
  rest_api_id             = aws_api_gateway_rest_api.s3_list_api.id
  resource_id             = aws_api_gateway_resource.upload_file_key_resource.id # Este es el nuevo recurso
  http_method             = aws_api_gateway_method.get_upload_method.http_method
  integration_http_method = "POST" # La Lambda se invoca con POST
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.s3_upload_function.invoke_arn # Invoca la nueva Lambda de subida
}


# Despliegue de la API Gateway (añade las nuevas dependencias)
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_method.get_files_method,
    aws_api_gateway_integration.lambda_folder_integration,
    aws_api_gateway_method.get_folder_files_method,
    aws_api_gateway_integration.lambda_download_integration,
    aws_api_gateway_method.get_download_method,
    aws_api_gateway_integration.lambda_list_folders_integration,
    aws_api_gateway_method.get_folders_method,
    # Nuevas dependencias:
    aws_api_gateway_integration.lambda_upload_integration,
    aws_api_gateway_method.get_upload_method
  ]

  rest_api_id = aws_api_gateway_rest_api.s3_list_api.id
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.files_resource.id,
      aws_api_gateway_method.get_files_method.id,
      aws_api_gateway_integration.lambda_integration.id,
      aws_api_gateway_resource.folder_resource.id,
      aws_api_gateway_method.get_folder_files_method.id,
      aws_api_gateway_integration.lambda_folder_integration.id,
      aws_api_gateway_resource.download_resource.id,
      aws_api_gateway_resource.file_key_resource.id,
      aws_api_gateway_method.get_download_method.id,
      aws_api_gateway_integration.lambda_download_integration.id,
      aws_api_gateway_resource.folders_resource.id,
      aws_api_gateway_method.get_folders_method.id,
      aws_api_gateway_integration.lambda_list_folders_integration.id,
      # Nuevos recursos en el trigger
      aws_api_gateway_resource.upload_resource.id,
      aws_api_gateway_resource.upload_file_key_resource.id,
      aws_api_gateway_method.get_upload_method.id,
      aws_api_gateway_integration.lambda_upload_integration.id,
    ]))
  }
}

# Etapa de API Gateway
resource "aws_api_gateway_stage" "dev_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.s3_list_api.id
  stage_name    = "dev"
}

# Permiso para que API Gateway invoque la función Lambda de listar archivos
resource "aws_lambda_permission" "apigateway_lambda_list_permission" {
  statement_id  = "AllowAPIGatewayInvokeLambdaList"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_list_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.s3_list_api.execution_arn}/*/GET/files/*"
}

# Permiso para que API Gateway invoque la función Lambda de descarga
resource "aws_lambda_permission" "apigateway_lambda_download_permission" {
  statement_id  = "AllowAPIGatewayInvokeLambdaDownload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_download_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.s3_list_api.execution_arn}/*/GET/download/*"
}

# Permiso para que API Gateway invoque la función Lambda de listar carpetas
resource "aws_lambda_permission" "apigateway_lambda_list_folders_permission" {
  statement_id  = "AllowAPIGatewayInvokeLambdaListFolders"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_list_folders_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.s3_list_api.execution_arn}/*/GET/folders"
}

# Nuevo: Permiso para que API Gateway invoque la función Lambda de subida
resource "aws_lambda_permission" "apigateway_lambda_upload_permission" {
  statement_id  = "AllowAPIGatewayInvokeLambdaUpload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_upload_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.s3_list_api.execution_arn}/*/GET/upload/*" # Ruta /upload/{file_key+}
}


# Salida para la URL base de la API Gateway
output "api_base_url" {
  value = "${aws_api_gateway_stage.dev_stage.invoke_url}"
}

# Salida para el endpoint de listar archivos
output "list_files_url" {
  value = "${aws_api_gateway_stage.dev_stage.invoke_url}/files"
}

# Salida para el endpoint de descarga de archivos
output "download_file_base_url" {
  value = "${aws_api_gateway_stage.dev_stage.invoke_url}/download"
}

# Salida para el endpoint de listar carpetas
output "list_folders_url" {
  value = "${aws_api_gateway_stage.dev_stage.invoke_url}/folders"
}

# Nuevo: Salida para el endpoint de subida de archivos
output "upload_file_base_url" {
  value = "${aws_api_gateway_stage.dev_stage.invoke_url}/upload"
}