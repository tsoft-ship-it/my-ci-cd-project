resource "aws_instance" "web" {
  ami = "ami_test"
  instance_type = "t2.small"
  description = "Ec2 Instance"
}

variable "instance_type" {
  type = string
  description = "EC2 instance_type"
  default = t2.small"
}

resource "aws_instance" "web" {
  ami = data.ami_ami.ubunty.id
  instance_type = var.instance_type
  subnet_id = var.subnet_id
}
  tags = {
    Environment = var.environment
	Name = "${var.environment}-web-server"
}
