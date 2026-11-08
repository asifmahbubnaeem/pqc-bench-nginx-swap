variable "region" {
  type    = string
  default = "us-east-1"
}

variable "az_suffix" {
  description = "AZ letter; both hosts go in the same AZ (c7g availability varies by AZ)"
  type        = string
  default     = "a"
}

variable "instance_type" {
  description = "nginx target — same as Phases 1-3"
  type        = string
  default     = "c7g.large"
}

variable "loadgen_instance_type" {
  description = "Load generator. Sized up so the client is never the bottleneck."
  type        = string
  default     = "c7g.xlarge"
}

variable "key_name" {
  description = "Existing EC2 key pair name (the one you used for Phases 1-4)"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "Your current public IP as /32. Never 0.0.0.0/0."
  type        = list(string)
  validation {
    condition     = !contains(var.allowed_ssh_cidrs, "0.0.0.0/0")
    error_message = "Refusing to open ssh to the world; use your IP/32."
  }
}
