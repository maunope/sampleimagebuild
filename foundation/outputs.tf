output "vpc_name" {
  description = "The name of the VPC network."
  value       = google_compute_network.petshop_vpc.name
}

output "subnet_id" {
  description = "The ID of the petshop subnet."
  value       = google_compute_subnetwork.petshop_subnet.id
}

output "dns_zone_name" {
  description = "The name of the private DNS zone."
  value       = google_dns_managed_zone.petshop_private_zone.name
}

output "dns_name" {
  description = "The DNS name of the private zone."
  value       = google_dns_managed_zone.petshop_private_zone.dns_name
}

output "http_tag" {
  description = "The network tag for HTTP traffic."
  value       = local.http_tag
}

output "db_tag" {
  description = "The network tag for database traffic."
  value       = local.db_tag
}
