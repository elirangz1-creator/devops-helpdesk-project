variable "name" { type = string }
variable "ami" { type = string }
variable "subnet_id" { type = string }
variable "security_group_id" { type = string }
variable "key_name" { type = string }
variable "instance_type" { type = string }
variable "instance_profile" {
  type    = string
  default = null
}
resource "aws_instance" "host" {
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name
  iam_instance_profile   = var.instance_profile
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    encrypted   = true
    volume_size = 50
    volume_type = "gp3"
  }
  tags = { Name = var.name, Project = "rt-helpdesk" }
}
output "public_ip" { value = aws_instance.host.public_ip }
output "private_ip" { value = aws_instance.host.private_ip }
