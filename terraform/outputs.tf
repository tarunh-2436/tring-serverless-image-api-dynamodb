output "processing_queue_url" {
  value = aws_sqs_queue.image_processing_queue.id
}

output "processing_queue_arn" {
  value = aws_sqs_queue.image_processing_queue.arn
}

output "processing_dlq_arn" {
  value = aws_sqs_queue.image_processing_dlq.arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.image_notifications.arn
}

output "api_lambda_arn" {
  value = aws_lambda_function.api.arn
}

output "processor_lambda_arn" {
  value = aws_lambda_function.processor.arn
}

output "pre_token_lambda_arn" {
  value = aws_lambda_function.pre_token_generation.arn
}

output "user_pool_id" {
  value = aws_cognito_user_pool.users.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "user_pool_domain" {
  value = aws_cognito_user_pool_domain.domain.domain
}

output "api_url" {
  value = aws_apigatewayv2_api.image_api.api_endpoint
}

output "cloudfront_url" {
  value = "https://${aws_cloudfront_distribution.website.domain_name}"
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.website.id
}