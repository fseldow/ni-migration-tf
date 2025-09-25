# ni-migration-tf
## Prerequest
1. already created one cluster to meet the network isolated cluster limitation
1. modify the variable related to the cluster
## Steps:
1. export ARM_SUBSCRIPTION_ID=<your-subscription-id>
1. terraform init -upgrade
1. terraform plan -out main.tfplan
1. terraform apply main.tfplan
