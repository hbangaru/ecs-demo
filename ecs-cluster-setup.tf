# Define our VPC
resource "aws_vpc" "demo-ecs-vpc" {
cidr_block = "${var.vpc_ecs_cidr}"
enable_dns_hostnames = true
tags {
  Name = "demo-ecs-vpc"
}
}

# Setting up Subnets in the above VPC 
# Define the public subnet

resource "aws_subnet" "demo-ecs-public-subnet" {

  vpc_id = "${aws_vpc.default.id}"

  cidr_block = "${var.public_ecs_cidr}"

  availability_zone = "us-east-1a"

  tags {

    Name = "Public Subnet for ECS demo"

  }
}

# Define the private subnet

resource "aws_subnet" "demo-ecs-private-subnet" {

  vpc_id = "${aws_vpc.default.id}"

  cidr_block = "${var.private_ecs_cidr}"

  availability_zone = "us-east-1b"

  tags {

    Name = "Private Subnet for ECS demo"

  }
}

######################################### Creating IGW & NAT gateway ##############################################

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.demo-ecs-vpc.id}"
}

resource "aws_nat_gateway" "ngw" {
  allocation_id = "${aws_eip.nat.id}"
  subnet_id     = "${aws_subnet.demo-ecs-public-subnet.id}"
  depends_on = ["aws_internet_gateway.igw"]

  tags {
    Name = "NAT-GW"
  }
}

/*
 * Routes for private subnets to use NAT gateway
 */
resource "aws_route_table" "nat_route_table" {
 vpc_id = "${aws_vpc.demo-ecs-public-subnet.id}"
}

resource "aws_route" "nat_route" {
 route_table_id         = "${aws_route_table.nat_route_table.id}"
 destination_cidr_block = "0.0.0.0/0"
 nat_gateway_id         = "${aws_nat_gateway.ngw.id}"
}

resource "aws_route_table_association" "private_route" {
 count          = "${length(var.aws_zones)}"
 subnet_id      = "${aws_subnet.demo-ecs-private-subnet.id}"
 route_table_id = "${aws_route_table.nat_route_table.id}"
}

/*
 * Routes for public subnets to use internet gateway
 */
resource "aws_route_table" "igw_route_table" {
 vpc_id = "${aws_vpc.vpc.id}"
}

resource "aws_route" "igw_route" {
 route_table_id         = "${aws_route_table.igw_route_table.id}"
 destination_cidr_block = "0.0.0.0/0"
 gateway_id             = "${aws_internet_gateway.igw.id}"
}

resource "aws_route_table_association" "public_route" {
 count          = "${length(var.aws_zones)}"
 subnet_id      = "${aws_subnet.public_subnet.demo-ecs-public-subnet.id}"
 route_table_id = "${aws_route_table.igw_route_table.id}"
}


######################################## Security Groups for both EC2 & ELB ########################################

### Creating Security Group for EC2
resource "aws_security_group" "ec2-sg" {
  description = "Security group for EC2 instances"
  ingress {
    from_port = 8080
    to_port = 8080
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

## Security Group for ELB
resource "aws_security_group" "elb-sg" {
  description = "Security group for Load Balancer"
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

####################################### IAM Roles EC2 and Service ##################################################

data "aws_iam_policy_document" "ecs-instance-policy" {
    statement {
        actions = ["sts:AssumeRole"]

        principals {
            type        = "Service"
            identifiers = ["ec2.amazonaws.com"]
        }
    }
}

resource "aws_iam_role" "ecs-instance-role" {
    name                = "ecs-instance-role"
    path                = "/"
    assume_role_policy  = "${data.aws_iam_policy_document.ecs-instance-policy.json}"
}

resource "aws_iam_role_policy_attachment" "ecs-instance-role-attachment" {
    role       = "${aws_iam_role.ecs-instance-role.name}"
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs-instance-profile" {
    name = "ecs-instance-profile"
    path = "/"
    roles = ["${aws_iam_role.ecs-instance-role.id}"]
    provisioner "local-exec" {
      command = "sleep 10"
    }
}

# ECS Service Assume Role

data "aws_iam_policy_document" "ecs-service-policy" {
    statement {
        actions = ["sts:AssumeRole"]

        principals {
            type        = "Service"
            identifiers = ["ecs.amazonaws.com"]
        }
    }
}
resource "aws_iam_role" "ecs-service-role" {
    name                = "ecs-service-role"
    path                = "/"
    assume_role_policy  = "${data.aws_iam_policy_document.ecs-service-policy.json}"
}

resource "aws_iam_role_policy_attachment" "ecs-service-role-attachment" {
    role       = "${aws_iam_role.ecs-service-role.name}"
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}


###########################ELB Configuration##############################################

### Creating ELB
resource "aws_elb" "demo-ecs-lb" {
  name = "demo-ecs-elb"
  security_groups = ["${aws_security_group.elb.id}"]
  availability_zones = ["us-west-1a", "us-west-1b"]

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    interval = 30
    target = "HTTP:8080/"
  }
  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = "8080"
    instance_protocol = "http"
  }
}

####################### Launch Configuration and Autoscaling ################################

## Creating Launch Configuration
resource "aws_launch_configuration" "demo-ecs-launchconfig" {
  image_id               = "${lookup(var.amis,var.region)}"
  instance_type          = "t2.micro"
  security_groups        = ["${aws_security_group.ec2-sg.id}"]
  key_name               = "${var.key_name}"
  user_data = <<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=your_cluster_name >> /etc/ecs/ecs.config
              EOF
  lifecycle {
    create_before_destroy = true
  }
}
## Creating AutoScaling Group
resource "aws_autoscaling_group" "example" {
  launch_configuration = "${aws_launch_configuration.demo-ecs-launchconfig.id}"
  availability_zones = ["us-west-1a", "us-west-1b"]
#  vpc_zone_identifier = ["${aws_subnet.demo-ecs-private-subnet.id}"]
  min_size = 2
  max_size = 2
  load_balancers = ["${aws_elb.demo-ecs-lb.name}"]
  health_check_type = "ELB"
  tag {
    key = "Name"
    value = "demo-ecs-ag"
    propagate_at_launch = true
  }
}

#################################################ECS Task-definition & Service and Task configuration #############################################

# Simply specify the family to find the latest ACTIVE revision in that family.
data "aws_ecs_task_definition" "tomcat" {
  task_definition = "${aws_ecs_task_definition.tomcat.family}"
}

data "aws_ecs_task_definition" "nginx" {
  task_definition = "${aws_ecs_task_definition.nginx.family}"
}

resource "aws_ecs_cluster" "demo-ecs-cluster" {
  name = "demo-application"
}


# ======================  TASKS ===================
resource "aws_ecs_task_definition" "tomcat" {
  family = "tomcat"

  container_definitions = <<DEFINITION
[
  {
    "cpu": 128,
    "environment": [{
      "name": "SECRET",
      "value": "KEY"
    }],
    "essential": true,
    "image": "tomcat:latest",
    "memory": 128,
    "memoryReservation": 64,
    "name": "tomcatapp"
  }
]
DEFINITION
}

resource "aws_ecs_task_definition" "nginx" {
  family = "nginx"

  container_definitions = <<DEFINITION
[
  {
    "cpu": 128,
    "environment": [{
      "name": "SECRET",
      "value": "KEY"
    }],
    "essential": true,
    "image": "nginx:latest",
    "memory": 128,
    "memoryReservation": 64,
    "name": "nginx"
  }
]
DEFINITION
}

# ======================  SERVICES ===================

resource "aws_ecs_service" "tomcat" {
  name          = "mongo"
  cluster       = "${aws_ecs_cluster.demo-ecs-cluster.id}"
  desired_count = 2

  # Track the latest ACTIVE revision
  task_definition = "${aws_ecs_task_definition.tomcat.family}:${max("${aws_ecs_task_definition.tomcat.revision}", "${data.aws_ecs_task_definition.tomcat.revision}")}"
}

resource "aws_ecs_service" "nginx" {
  name          = "nginx"
  cluster       = "${aws_ecs_cluster.demo-ecs-cluster.id}"
  desired_count = 2

  # Track the latest ACTIVE revision
  task_definition = "${aws_ecs_task_definition.nginx.family}:${max("${aws_ecs_task_definition.nginx.revision}", "${data.aws_ecs_task_definition.nginx.revision}")}"
}





  








