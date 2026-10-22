variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_group" { type = string }
variable "allowed_sg" { type = string }
variable "multi_az" {
  type    = bool
  default = false
}
variable "deletion_protection" {
  type    = bool
  default = true # prod default; dev turns it off so the stack can be torn down daily
}
variable "skip_final_snapshot" {
  type    = bool
  default = false
}

resource "aws_security_group" "db" {
  name   = "${var.name}-db"
  vpc_id = var.vpc_id
  ingress { # only EKS nodes
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.allowed_sg]
  }
}

resource "aws_db_instance" "this" {
  identifier                  = var.name
  engine                      = "postgres"
  engine_version              = "16"
  instance_class              = "db.t3.micro"
  allocated_storage           = 20
  db_name                     = "licenses"
  username                    = "app"
  manage_master_user_password = true # password lives in Secrets Manager, never in state
  db_subnet_group_name        = var.subnet_group
  vpc_security_group_ids      = [aws_security_group.db.id]
  multi_az                    = var.multi_az # standby in second AZ for failover
  backup_retention_period     = 7            # point-in-time restore -> RPO ~5 min
  storage_encrypted           = true
  deletion_protection         = var.deletion_protection
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = var.skip_final_snapshot ? null : "${var.name}-final"
}

output "endpoint" { value = aws_db_instance.this.address }
output "secret_arn" { value = aws_db_instance.this.master_user_secret[0].secret_arn }
