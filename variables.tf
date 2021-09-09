variable "zone_name" {
  type = string
  description = "Route53 zone name (e.g., example.com)"
	
}
variable "domain_name" {
  type = string
  description = "Full domain name of host to scale based on (e.g., myhost.example.com)"
}

variable "asg_region" {
  type = string
  description = "Region where your autoscaling group is deployed."
}

variable "scale_to" {  
  type = number
  description = "Desired count the autoscaling group should be set to when scaling event occurs."
}

variable "autoscaling_group_name" {
  type = string
  description = "Name of the autoscaling group to target."
}