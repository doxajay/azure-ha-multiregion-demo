resource "random_string" "suffix" {
  length  = 6
  upper   = false
  numeric = true
  special = false
}

locals {
  suffix = random_string.suffix.result

  rg_primary_name   = "rg-${var.project}-${local.suffix}-p"
  rg_secondary_name = "rg-${var.project}-${local.suffix}-s"

  app_primary_name   = "app-${var.project}-${local.suffix}-p"
  app_secondary_name = "app-${var.project}-${local.suffix}-s"

  asp_primary_name   = "asp-${var.project}-${local.suffix}-p"
  asp_secondary_name = "asp-${var.project}-${local.suffix}-s"

  sql_primary_name   = "sql${replace(var.project, "-", "")}${local.suffix}p"
  sql_secondary_name = "sql${replace(var.project, "-", "")}${local.suffix}s"

  afd_profile_name  = "afd-${var.project}-${local.suffix}"
  afd_endpoint_name = "ep-${var.project}-${local.suffix}"
  og_name           = "og-${var.project}-${local.suffix}"

  db_name = "sqldb-${var.project}-${local.suffix}"
}
