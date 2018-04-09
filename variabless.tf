########################### Test VPC Config ################################

variable "vpc_ecs_cidr" {
  description = "IP addressing for Test Network"
  default ="10.169.0.0/16"
}

variable "public_ecs_cidr" {
  description = "Public CIDR for externally accessible subnet"
  default = "10.169.2.0/20"
}

variable "private_ecs_cidr" {
  description = "Private CIDR for externally accessible subnet"
  default = "10.169.4.0/20"
}

variable "lb_name" {
   default ="demo-ecs-lb"
}

variable “region” {
 description = “AWS region for hosting our your network”
 default = “us-east-1”
}

variable “amis” {
 description = “Base AMI to launch the instances”
 default = {
 ap-south-1 = “ami-8da8d2e2”
 }

variable “key_name” {
 description = “EC2 instance key name”
 default = “us-east-1”
}



########################### Autoscale Config ################################

variable "max_instance_size" {
  description = "Maximum number of instances in the cluster"
}

variable "min_instance_size" {
  description = "Minimum number of instances in the cluster"
}

variable "desired_capacity" {
  description = "Desired number of instances in the cluster"
}