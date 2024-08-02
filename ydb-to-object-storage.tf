locals {
  folder_id   = "" # Your cloud folder ID, same as for provider
  bucket_name = "" # Name of an Object Storage bucket. Must be unique in the Cloud

  # Specify these settings ONLY AFTER the YDB database and bucket are created. Then run "terraform apply" command again
  # You should set up endpoints using the GUI to obtain their IDs
  source_endpoint_id = "" # Source endpoint ID
  target_endpoint_id = "" # Target endpoint ID
  transfer_enabled   = 0  # Set to 1 to enable Transfer

  # The following settings are predefined. Change them only if necessary.
  network_name        = "network"                        # Name of the network
  subnet_name         = "subnet-a"                       # Name of the subnet
  security_group_name = "security-group"                 # Name of the security group
  ydb_database_name   = "ydb-database"                   # Name of YDB database
  sa_name             = "sa-for-transfer"                # Name of the service account
  transfer_name       = "ydb-to-object-storage-transfer" # Name of the transfer from the Managed Service for YDB to the Object Storage bucket
}

resource "yandex_vpc_network" "network" {
  description = "Network for the Object Storage bucket and Managed Service for YDB"
  name        = local.network_name
}

resource "yandex_vpc_subnet" "subnet-a" {
  description    = "Subnet in the ru-central1-a availability zone"
  name           = local.subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.1.0.0/16"]
}

resource "yandex_vpc_security_group" "security-group" {
  description = "Security group for the Managed Service for YDB database and Object Storage bucket"
  name        = local.security_group_name
  network_id  = yandex_vpc_network.network.id

  ingress {
    description    = "The rule allows connections to the YDB database from the Internet"
    protocol       = "TCP"
    port           = 2135
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "The rule allows all outgoing traffic"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# Create a service account to manage buckets and access YDB database
resource "yandex_iam_service_account" "sa-for-transfer" {
  description = "A service account to manage buckets and access YDB database"
  folder_id   = local.folder_id
  name        = local.sa_name
}

# Create a serverless YDB database
resource "yandex_ydb_database_serverless" "ydb-database" {
  name        = local.ydb_database_name
  location_id = "ru-central1"
}

# Grant permissions to the service account

resource "yandex_resourcemanager_folder_iam_member" "storage-editor" {
  folder_id = local.folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa-for-transfer.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "ydb-editor" {
  folder_id = local.folder_id
  role      = "ydb.editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa-for-transfer.id}"
}

# Create a static key for the service account
resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  description        = "Static access key for Object Storage"
  service_account_id = yandex_iam_service_account.sa-for-transfer.id
}

# Use the static key to create a bucket
resource "yandex_storage_bucket" "obj-storage-bucket" {
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  bucket     = local.bucket_name
}

# Create transfer
resource "yandex_datatransfer_transfer" "ydb-to-object-storage-transfer" {
  count       = local.transfer_enabled
  description = "Transfer from the YDB database cluster to the Object Storage bucket"
  name        = "ydb-to-object-storage-transfer"
  source_id   = local.source_endpoint_id
  target_id   = local.target_endpoint_id
  type        = "SNAPSHOT_ONLY" # Copy data from the source YDB database
}

