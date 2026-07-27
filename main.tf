############First Terraform code###########

provider "aws" {
  region = "ap-south-1"
 }
 
#First we need to specify Provider and the region where the resource needs to be created ##

#Then what resource we need & the sub-configuration##

resource "aws_instance" "web" {
  ami = "ami-5667900"
  instance_type = "t2.micro"
  key_name = "my-name"
}

  tags = {
    Name = "leran-terraform-1"
}
