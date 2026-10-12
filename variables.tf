variable "aws_region" {
  description = "AWS region for the deployment"
  type        = string
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Name used to identify project resources"
  type        = string
  default     = "multiaz-nginx"
}

variable "instance_type" {
  description = "EC2 instance type for the web servers"
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  description = "Minimum number of EC2 instances"
  type        = number
  default     = 2
}

variable "desired_capacity" {
  description = "Desired number of EC2 instances"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of EC2 instances"
  type        = number
  default     = 4
}

variable "cpu_target_value" {
  description = "Target average CPU utilization for scaling"
  type        = number
  default     = 50
}