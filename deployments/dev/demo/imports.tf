# Recovery, 29 September 2026 (FINDINGS.md #24) - the same recovery as #23.
#
# The Phase 6 create (deployment PR #21) failed on the database: the Container
# App's migrate init container created `appdb` (EF Core Migrate() creates a
# missing database) one second before Terraform tried to. This adopts the
# database into state. app-stack v0.3.2 makes the app wait for the database, so
# the next create should not need this.
#
# Remove in a follow-up change: on the next create from nothing it would try to
# import a database that does not exist yet.
import {
  to = module.app.azurerm_postgresql_flexible_server_database.this
  id = "/subscriptions/da2df6f3-8103-4209-a882-96fbe2f78977/resourceGroups/rg-demo-dev/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-demo-dev-e9fdbf/databases/appdb"
}
