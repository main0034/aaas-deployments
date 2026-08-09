# State location for this deployment.
#
# Only the key lives here. The storage account, container and resource group
# are supplied by CI from repository variables, so no bootstrap-specific
# values are committed and the backend can be moved without touching every
# deployment directory.
#
# The key MUST be "<environment>/<name>.tfstate" - CI validates this, because
# two deployments sharing a state file is a very unpleasant thing to discover.

key = "dev/demo.tfstate"
