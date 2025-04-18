output "id" {
  description = "EFS filesystem ID"
  value       = aws_efs_file_system.main.id
}

output "dns_name" {
  description = "The DNS name of the EFS filesystem"
  value       = aws_efs_file_system.main.dns_name
}

output "security_group_id" {
  description = "Security group ID for EFS mount targets"
  value       = aws_security_group.efs.id
}
