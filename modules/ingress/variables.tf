# --- Placement ---

variable "name_prefix" {
  description = "Prefix for all named resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC the NLB and collector live in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the NLB: private for an internal NLB, public when internet_facing."
  type        = list(string)
}

variable "discovery_namespace" {
  description = "Cloud Map private DNS namespace. collector.<namespace> is always a SAN on the generated cert so direct in-VPC access verifies too."
  type        = string
}

# --- Load balancer ---

variable "create_load_balancer" {
  description = "Create the NLB in front of the collector. false = in-VPC service-discovery access only; the module still generates and writes the collector's TLS material."
  type        = bool
  default     = true
}

variable "internet_facing" {
  description = "Make the NLB internet-facing. STRONGLY consider keeping this false and reaching the collector over a VPN/DirectConnect instead: the collector authenticates every request (HMAC / bearer), but an internal NLB removes the exposed surface entirely. true requires allowed_ingress_cidrs and public subnet_ids."
  type        = bool
  default     = false

  validation {
    condition     = !var.internet_facing || length(var.allowed_ingress_cidrs) > 0
    error_message = "internet_facing requires a non-empty allowed_ingress_cidrs — scope ingress to your developers' egress CIDRs. Do not use 0.0.0.0/0."
  }

  validation {
    condition     = !var.internet_facing || var.create_load_balancer
    error_message = "internet_facing requires create_load_balancer = true."
  }
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach the NLB on 443. Required (and the only ingress) when internet_facing; for an internal NLB, empty defaults to the VPC CIDR."
  type        = list(string)
  default     = []
}

# --- TLS mode ---

variable "tls_mode" {
  description = "\"acm\": NLB TLS listener terminates with an ACM certificate — clients trust system roots, zero client TLS config (requires acm_certificate_arn and a dns_name the cert covers). \"self_signed\": NLB passes TCP through to the collector's self-signed cert — no domain needed; distribute collector_ca_pem to clients (`tokeniq sync configure --collector-ca`)."
  type        = string
  default     = "acm"

  validation {
    condition     = contains(["acm", "self_signed"], var.tls_mode)
    error_message = "tls_mode must be \"acm\" or \"self_signed\"."
  }

  validation {
    condition     = var.tls_mode != "acm" || !var.create_load_balancer || var.acm_certificate_arn != ""
    error_message = "tls_mode \"acm\" requires acm_certificate_arn (or switch to tls_mode = \"self_signed\")."
  }
}

variable "acm_certificate_arn" {
  description = "ACM certificate for the NLB TLS listener (tls_mode = \"acm\"). Must cover dns_name (or the name clients will use)."
  type        = string
  default     = ""
}

# --- DNS ---

variable "route53_zone_id" {
  description = "Route 53 hosted zone to create the collector alias record in. Empty skips DNS — use the NLB DNS name directly."
  type        = string
  default     = ""
}

variable "dns_name" {
  description = "Fully qualified DNS name clients call the collector by (e.g. tokeniq.example.com). Added to the self-signed cert SANs; with route53_zone_id set, an alias record to the NLB is created."
  type        = string
  default     = ""
}

# --- Core wiring: TLS secret containers (owned by modules/core) ---

variable "collector_tls_cert_secret_id" {
  description = "Secrets Manager ID of the collector TLS cert container this module writes the version into."
  type        = string
}

variable "collector_tls_key_secret_id" {
  description = "Secrets Manager ID of the collector TLS key container this module writes the version into."
  type        = string
}
