data "aws_availability_zones" "available" { state = "available" }
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
resource "aws_vpc" "lab" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = var.project }
}
resource "aws_subnet" "lab" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.42.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
}
resource "aws_internet_gateway" "lab" { vpc_id = aws_vpc.lab.id }
resource "aws_route_table" "lab" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }
}
resource "aws_route_table_association" "lab" {
  subnet_id      = aws_subnet.lab.id
  route_table_id = aws_route_table.lab.id
}
resource "aws_key_pair" "admin" {
  key_name   = var.project
  public_key = var.ssh_public_key
}
resource "aws_security_group" "ci" {
  name_prefix = "${var.project}-ci-"
  vpc_id      = aws_vpc.lab.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "app" {
  name_prefix = "${var.project}-app-"
  vpc_id      = aws_vpc.lab.id
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = [var.admin_cidr]
    security_groups = [aws_security_group.ci.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_s3_bucket" "backup" { bucket = var.backup_bucket }
resource "aws_s3_bucket_public_access_block" "backup" {
  bucket                  = aws_s3_bucket.backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    id     = "lab-retention"
    status = "Enabled"
    filter { prefix = "backups/" }
    expiration { days = 14 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}
resource "aws_iam_role" "app" {
  name_prefix = "${var.project}-backup-"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole"
  }] })
}
resource "aws_iam_role_policy" "backup" {
  role = aws_iam_role.app.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.backup.arn,
    Condition = { StringLike = { "s3:prefix" = ["backups/*"] } } },
    { Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject"], Resource = "${aws_s3_bucket.backup.arn}/backups/*" }
  ] })
}
resource "aws_iam_instance_profile" "app" { role = aws_iam_role.app.name }
module "ci" {
  source            = "./modules/host"
  name              = "${var.project}-ci"
  ami               = data.aws_ami.ubuntu.id
  subnet_id         = aws_subnet.lab.id
  security_group_id = aws_security_group.ci.id
  key_name          = aws_key_pair.admin.key_name
  instance_type     = var.ci_instance_type
  depends_on        = [aws_route_table_association.lab]
}
module "app" {
  source            = "./modules/host"
  name              = "${var.project}-app"
  ami               = data.aws_ami.ubuntu.id
  subnet_id         = aws_subnet.lab.id
  security_group_id = aws_security_group.app.id
  key_name          = aws_key_pair.admin.key_name
  instance_type     = var.app_instance_type
  instance_profile  = aws_iam_instance_profile.app.name
  depends_on        = [aws_route_table_association.lab]
}
resource "aws_budgets_budget" "lab" {
  name         = "${var.project}-monthly-account-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
}
output "ci_public_ip" { value = module.ci.public_ip }
output "app_public_ip" { value = module.app.public_ip }
output "app_private_ip" { value = module.app.private_ip }
output "backup_bucket" { value = aws_s3_bucket.backup.id }
