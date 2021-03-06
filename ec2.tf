resource "aws_autoscaling_group" "ecs_ec2_asg" {
  name                = "asg_for_ec2_ecs"
  min_size            = var.ecs_cluster_size.min
  max_size            = var.ecs_cluster_size.max
  vpc_zone_identifier = split(",", data.aws_ssm_parameter.public_subnet_ids.value)

  launch_template {
    id      = aws_launch_template.for_ecs_ec2_asg.id
    version = aws_launch_template.for_ecs_ec2_asg.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
  }

  # The ASG used for our ECS-on-EC2 Cluster needs to have
  # the "AmazonECSManaged" tag lest there be issues with scaling-in
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_capacity_provider
  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "composing_ecs_cluster"
    value               = aws_ecs_cluster.ec2_cluster.name
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = data.aws_default_tags.current.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_launch_template" "for_ecs_ec2_asg" {
  name          = "ec2_ecs_cluster_launch_template"
  instance_type = var.ec2_spec_for_ecs_cluster.instance_type
  image_id      = var.ec2_spec_for_ecs_cluster.ami_id
  description = format("The launch template for creating the EC2 instances used to form the ECS cluster %s",
  aws_ecs_cluster.ec2_cluster.name)

  cpu_options {
    core_count       = 1
    threads_per_core = 2
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_instance_role.arn
  }

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    security_groups             = [aws_security_group.for_ec2_composing_ecs_cluster.id]
    description = format("An ENI for an EC2 instance composing the ECS Cluster %s",
    aws_ecs_cluster.ec2_cluster.name)
  }

  # configure the ECS Container Agent to register itself against ECS cluster
  user_data = base64encode("#!/bin/bash\necho ECS_CLUSTER=${aws_ecs_cluster.ec2_cluster.name} >> /etc/ecs/ecs.config")
}
