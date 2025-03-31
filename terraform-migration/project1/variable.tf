variable "ec2_instance_name" {
    description = "The name of ec2 instance"
    type = string
    default = "demo_instance"
  
}

variable "ec2_ami" {
    description = "The ec2 ami"
    type = string
    default =   "ami-00f8e327478dc9016"
  
}