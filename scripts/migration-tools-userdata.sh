#!/bin/bash
# User data script for migration tools instance

set -e

# Update system
yum update -y

# Install required tools
yum install -y \
    docker \
    git \
    jq \
    wget \
    curl \
    unzip

# Install kubectl
curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.28.3/2023-11-14/bin/linux/amd64/kubectl
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Velero CLI
wget https://github.com/vmware-tanzu/velero/releases/latest/download/velero-linux-amd64.tar.gz
tar -xvf velero-linux-amd64.tar.gz
mv velero-*/velero /usr/local/bin/
rm -rf velero-*

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Configure AWS region
aws configure set region ${region}

# Configure kubectl for both clusters
aws eks update-kubeconfig --region ${region} --name ${source_cluster} --alias source
aws eks update-kubeconfig --region ${region} --name ${target_cluster} --alias target

# Create migration scripts directory
mkdir -p /opt/migration-scripts

# Create migration environment file
cat > /opt/migration-scripts/migration-env.sh << 'EOF'
#!/bin/bash
export AWS_REGION=${region}
export SOURCE_CLUSTER=${source_cluster}
export TARGET_CLUSTER=${target_cluster}
export MIGRATION_S3_BUCKET=${s3_bucket}
export KUBECTL_SOURCE="kubectl --context source"
export KUBECTL_TARGET="kubectl --context target"
EOF

# Make environment file executable
chmod +x /opt/migration-scripts/migration-env.sh

# Log completion
echo "Migration tools setup completed successfully" >> /var/log/migration-tools-setup.log