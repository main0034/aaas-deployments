# Recovery, 28 September 2026 (FINDINGS.md #23).
#
# The create apply for deployment PR #17 created every resource, then failed on
# the database: Azure already had `appdb` on the new server, but Terraform's
# state did not. A re-run fails identically. This adopts the database into state
# instead of destroying a stack that is otherwise complete.
#
# Harmless once applied (importing a resource already at this address is a
# no-op); remove it in a later change.
import {
  to = module.app.azurerm_postgresql_flexible_server_database.this
  id = "/subscriptions/da2df6f3-8103-4209-a882-96fbe2f78977/resourceGroups/rg-demo-dev/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-demo-dev-e9fdbf/databases/appdb"
}
