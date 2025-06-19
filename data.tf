# data.tf
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# Nuevo: Archivo ZIP para la función de descarga
data "archive_file" "lambda_download_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_download"
  output_path = "${path.module}/lambda_download.zip"
}