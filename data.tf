# data.tf
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

data "archive_file" "lambda_download_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_download"
  output_path = "${path.module}/lambda_download.zip"
}

data "archive_file" "lambda_list_folders_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_list_folders"
  output_path = "${path.module}/lambda_list_folders.zip"
}

# Nuevo: Archivo ZIP para la función de subida
data "archive_file" "lambda_upload_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_upload"
  output_path = "${path.module}/lambda_upload.zip"
}