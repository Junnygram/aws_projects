output "instance_arn" {
  description = "The EC2 instance arn"
  value       = aws_instance.demo.arn
}

output "instance_id" {
  description = "The ID of the EC2 instance"
  value       = aws_instance.demo.id
}

output "instance_public_ip" {
  description = "The public IP of the EC2 instance"
  value       = aws_instance.demo.public_ip
}

output "instance_private_ip" {
  description = "The private IP of the EC2 instance"
  value       = aws_instance.demo.private_ip
}

output "instance_ami" {
  description = "The AMI used for the EC2 instance"
  value       = aws_instance.demo.ami
}

