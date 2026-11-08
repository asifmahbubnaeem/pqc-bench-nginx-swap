output "target_public_ip" {
  value = aws_instance.target.public_ip
}

output "target_private_ip" {
  value = aws_instance.target.private_ip
}

output "loadgen_public_ip" {
  value = aws_instance.loadgen.public_ip
}

output "env" {
  description = "Paste into your shell before ./run.sh"
  value       = <<-EOT
    export TARGET=ubuntu@${aws_instance.target.public_ip}
    export LOADGEN=ubuntu@${aws_instance.loadgen.public_ip}
    export TARGET_ADDR=${aws_instance.target.private_ip}
  EOT
}
