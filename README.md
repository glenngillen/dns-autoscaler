# DNS-based Autoscaler

A Terraform module to scale an autoscaling group based on a DNS query.

By having scaling events happen in response to DNS queries it means instances supporting low demand and non-critical infrastructure can be zealously scaled in to reduce costs. A DNS query will then be enough to rehydrate the environment. The first request however will fail, but after the ASG has finished scaling and instances are healthy subsequent requests will work.

Scaling the group back in once the instance is no longer being used is left as an exercise to the reader.

**Note:** Due to the way Route53 logging works, these resources will be provisioned in `us-east-1`. Your autoscaling group can be in any region.

## Usage

``` 
module "dns-autoscaler" {
  source  = "glenngillen/dns-autoscaler/aws"

  zone_name = "example.com"
  domain_name = "myhost.example.com"  
  asg_region = "ap-southeast-2"
  scale_to = 1
  autoscaling_group_name = "dev-web-group"
}
```