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

# Rol IAM para las funciones Lambda (reutilizamos el mismo rol)
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_s3_access_role" # Renombramos para ser más general

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

# Adjuntar política de S3 al rol de Lambda (ahora también GetObject es crucial)
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "lambda_s3_read_policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:ListBucket",
          "s3:GetObject" # Permiso para leer objetos, necesario para URLs prefirmadas
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

# Nuevo: Recurso AWS Lambda para generar URLs prefirmadas
resource "aws_lambda_function" "s3_download_function" {
  function_name    = "S3DownloadFileFunction"
  runtime          = "python3.9"
  handler          = "main.handler"
  role             = aws_iam_role.lambda_exec_role.arn # Reutilizamos el mismo rol
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

# API Gateway REST API (La API principal sigue siendo la misma)
resource "aws_api_gateway_rest_api" "s3_list_api" {
  name        = "S3OperationsAPI" # Renombramos a algo más general
  description = "API para operaciones en un bucket S3"
}

# Recurso de API Gateway (ruta /files) para listar la raíz
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

# Nuevo: Recurso de API Gateway (ruta /download)
resource "aws_api_gateway_resource" "download_resource" {
  rest_api_id = aws_api_gateway_rest_api.s3_list_api.id
  parent_id   = aws_api_gateway_rest_api.s3_list_api.root_resource_id
  path_part   = "download"
}

# Nuevo: Recurso para la ruta dinámica /download/{file_key+}
resource "aws_api_gateway_resource" "file_key_resource" {
  rest_api_id = aws_api_gateway_rest_api.s3_list_api.id
  parent_id   = aws_api_gateway_resource.download_resource.id # El padre es /download
  path_part   = "{file_key+}" # Captura la clave completa del archivo
}


# Método GET para el recurso /files (para listar la raíz del bucket)
resource "aws_api_gateway_method" "get_files_method" {
  rest_api_id   = aws_api_gateway_rest_api.s3_list_api.id
  resource_id   = aws_api_gateway_resource.files_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Método GET para el recurso /files/{folder+}
resource "aws_api_gateway_method" "get_folder_files_method" {
  rest_api_id   = aws_api_gateway_rest_api.s3_list_api.id
  resource_id   = aws_api_gateway_resource.folder_resource.id
  http_method   = "GET"
  authorization = "NONE"
  request_parameters = {
    "method.request.path.folder" = true
  }
}

# Nuevo: Método GET para el recurso /download/{file_key+}
resource "aws_api_gateway_method" "get_download_method" {
  rest_api_id   = aws_api_gateway_rest_api.s3_list_api.id
  resource_id   = aws_api_gateway_resource.file_key_resource.id # Este es el nuevo recurso
  http_method   = "GET"
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

# Nuevo: Integración de la API Gateway con la función Lambda (para /download/{file_key+})
resource "aws_api_gateway_integration" "lambda_download_integration" {
  rest_api_id             = aws_api_gateway_rest_api.s3_list_api.id
  resource_id             = aws_api_gateway_resource.file_key_resource.id # Este es el nuevo recurso
  http_method             = aws_api_gateway_method.get_download_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.s3_download_function.invoke_arn # Invoca la nueva Lambda
}


# Despliegue de la API Gateway (añade las nuevas dependencias)
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_method.get_files_method,
    aws_api_gateway_integration.lambda_folder_integration,
    aws_api_gateway_method.get_folder_files_method,
    # Nuevas dependencias:
    aws_api_gateway_integration.lambda_download_integration,
    aws_api_gateway_method.get_download_method
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
      # Nuevos recursos en el trigger
      aws_api_gateway_resource.download_resource.id,
      aws_api_gateway_resource.file_key_resource.id,
      aws_api_gateway_method.get_download_method.id,
      aws_api_gateway_integration.lambda_download_integration.id,
    ]))
  }
}

# Etapa de API Gateway
resource "aws_api_gateway_stage" "dev_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.s3_list_api.id
  stage_name    = "dev"
}

# Permiso para que API Gateway invoque la función Lambda de listar
resource "aws_lambda_permission" "apigateway_lambda_list_permission" { # Renombramos
  statement_id  = "AllowAPIGatewayInvokeLambdaList"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_list_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.s3_list_api.execution_arn}/*/GET/files/*"
}

# Nuevo: Permiso para que API Gateway invoque la función Lambda de descarga
resource "aws_lambda_permission" "apigateway_lambda_download_permission" {
  statement_id  = "AllowAPIGatewayInvokeLambdaDownload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_download_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.s3_list_api.execution_arn}/*/GET/download/*" # Ruta de descarga
}

# Salida para la URL base de la API Gateway (general)
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